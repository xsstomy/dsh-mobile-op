/**
 * WebSocket gateway client.
 *
 * Responsibilities: two-channel transport (`control` + `conversation`), pairing,
 * token authentication, request/response correlation, heartbeat, reconnect.
 *
 * Hard rules (see AGENTS.md):
 *  - the socket receive loop is the single consumer; UI gets broadcast callbacks
 *  - a request timeout never tears down the connection
 *  - `session-create` is idempotent by `requestId`; never blind-resend
 */
import { webSocket } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { buffer } from '@kit.ArkTS';
import { GatewayLimits } from '../common/Constants';
import { WireFrame } from '../protocol/Types';
import { decodeFrame } from '../protocol/WireDecoder';
import { MessagePayload, SessionCreatePayload, TypePayload } from '../protocol/Payloads';
import {
  ChannelLane, GatewayRequest, NotConnectedError, RequestTracker, buildRequest, resolveSettleKey
} from './RequestTracker';

export enum GatewayConnectionState {
  DISCONNECTED = 'disconnected',
  CONNECTING = 'connecting',
  AUTHENTICATING = 'authenticating',
  CONNECTED = 'connected',
  FAILED = 'failed'
}

export enum GatewayFailureKind {
  UPGRADE_REJECTED = 'upgrade-rejected',
  NETWORK = 'network',
  GATEWAY_DISABLED = 'gateway-disabled',
  AUTH_RESET = 'auth-reset',
  INTERNAL = 'internal'
}

export interface GatewayCredentials {
  endpoint: string;
  deviceId: string;
  /** Long-lived device token; absent while pairing. */
  token?: string;
  /** One-time pairing code; present only for the pairing attempt. */
  pairingCode?: string;
}

export interface GatewayListener {
  onFrame: (frame: WireFrame, raw: string) => void;
  onState: (state: GatewayConnectionState, detail: string) => void;
  onFailure: (kind: GatewayFailureKind, detail: string) => void;
  /** `paired` was received: persist the token immediately. */
  onPaired: (token: string) => void;
}

class ChannelSocket {
  readonly lane: ChannelLane;
  private readonly socket: webSocket.WebSocket;
  private opened: boolean = false;
  private closed: boolean = false;

  constructor(lane: ChannelLane) {
    this.lane = lane;
    this.socket = webSocket.createWebSocket();
  }

  isUsable(): boolean {
    return this.opened && !this.closed;
  }

  attach(onMessage: (text: string) => void, onFailure: (detail: string, closeCode: number) => void,
    onOpen: () => void): void {
    this.socket.on('open', (error: BusinessError, value: Object) => {
      void error;
      void value;
      this.opened = true;
      onOpen();
    });
    this.socket.on('message', (error: BusinessError, value: string | ArrayBuffer) => {
      void error;
      if (this.closed) {
        // Frames from a replaced socket must never drive the client.
        return;
      }
      const text: string = typeof value === 'string' ? value : buffer.from(value as ArrayBuffer).toString('utf8');
      onMessage(text);
    });
    this.socket.on('error', (error: BusinessError) => {
      if (this.closed) {
        return;
      }
      this.closed = true;
      onFailure(`upgrade failed (code=${error.code})`, Number(error.code));
    });
    this.socket.on('close', (error: BusinessError, value: webSocket.CloseResult) => {
      void error;
      if (this.closed) {
        return;
      }
      this.closed = true;
      onFailure(`closed (code=${value.code} ${value.reason})`, value.code);
    });
  }

  open(credentials: GatewayCredentials, laneHeader: string): void {
    const header: Record<string, string> = { 'X-DSH-Device-ID': credentials.deviceId };
    if (credentials.token !== undefined && credentials.token.length > 0) {
      header['Authorization'] = `Bearer ${credentials.token}`;
    }
    header['X-DSH-Channel'] = laneHeader;
    const protocol: string = credentials.pairingCode !== undefined && credentials.pairingCode.length > 0
      ? `dsh-mobile-v1, dsh-pair.${credentials.pairingCode}`
      : 'dsh-mobile-v1';
    const options: webSocket.WebSocketRequestOptions = {
      header: header as Object,
      protocol: protocol
    };
    this.socket.connect(credentials.endpoint, options, (error: BusinessError, value: boolean) => {
      void value;
      if (error && !this.closed) {
        this.closed = true;
      }
    });
  }

  send(text: string): boolean {
    if (!this.isUsable()) {
      return false;
    }
    this.socket.send(text, (error: BusinessError) => {
      if (error) {
        void error;
      }
    });
    return true;
  }

  close(): void {
    if (this.closed) {
      return;
    }
    this.closed = true;
    try {
      this.socket.close();
    } catch (error) {
      void error;
    }
  }
}

interface ArmedTimeout {
  readonly key: string;
  readonly token: number;
  readonly timer: number;
}

export class GatewayClient {
  private readonly tracker: RequestTracker = new RequestTracker();
  private readonly listeners: GatewayListener[] = [];
  private readonly timeouts: Map<string, ArmedTimeout> = new Map<string, ArmedTimeout>();

  private control: ChannelSocket | undefined;
  private conversation: ChannelSocket | undefined;
  /** Conversation-lane requests queued before that socket finished connecting. */
  private pendingConversation: GatewayRequest[] = [];
  private credentials: GatewayCredentials | undefined;
  private state: GatewayConnectionState = GatewayConnectionState.DISCONNECTED;
  private capabilities: string[] = [];
  private reconnectAttempt: number = 0;
  private reconnectTimer: number = -1;
  private pingTimer: number = -1;
  private stopped: boolean = true;
  /** Reconnect attempts only run while the app is in the foreground. */
  private foreground: boolean = true;
  /** A reconnect was requested while backgrounded; fire it on return to foreground. */
  private reconnectPending: boolean = false;
  private lastDetail: string = '';

  subscribe(listener: GatewayListener): void {
    this.listeners.push(listener);
  }

  unsubscribe(listener: GatewayListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  get connectionState(): GatewayConnectionState {
    return this.state;
  }

  get capabilitiesSnapshot(): string[] {
    return this.capabilities;
  }

  get failureDetail(): string {
    return this.lastDetail;
  }

  supports(capability: string): boolean {
    return this.capabilities.indexOf(capability) >= 0;
  }

  get isConnected(): boolean {
    return this.state === GatewayConnectionState.CONNECTED;
  }

  get canCreateSession(): boolean {
    return this.isConnected && this.supports('session-create');
  }

  private emitState(state: GatewayConnectionState, detail: string): void {
    this.state = state;
    this.lastDetail = detail;
    for (const listener of this.listeners) {
      listener.onState(state, detail);
    }
  }

  private emitFailure(kind: GatewayFailureKind, detail: string): void {
    this.lastDetail = detail;
    for (const listener of this.listeners) {
      listener.onFailure(kind, detail);
    }
  }

  startPairing(credentials: GatewayCredentials): void {
    this.stopped = false;
    this.credentials = credentials;
    this.reconnectAttempt = 0;
    this.reconnectPending = false;
    this.openChannels();
  }

  connect(credentials: GatewayCredentials): void {
    this.stopped = false;
    this.credentials = credentials;
    this.reconnectAttempt = 0;
    this.reconnectPending = false;
    this.openChannels();
  }

  disconnect(): void {
    this.stopped = true;
    this.reconnectPending = false;
    this.teardown();
    this.emitState(GatewayConnectionState.DISCONNECTED, '已断开');
  }

  /**
   * Ability lifecycle gate: reconnect attempts only run while the app is in the
   * foreground. Backgrounding cancels the armed timer (the OS freezes timers
   * anyway) and remembers the attempt; returning to the foreground fires it at
   * once instead of waiting out another backoff step.
   */
  setForeground(active: boolean): void {
    if (this.foreground === active) {
      return;
    }
    this.foreground = active;
    if (active) {
      this.flushPendingReconnect();
    } else if (this.reconnectTimer >= 0) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = -1;
      this.reconnectPending = true;
    }
  }

  /** Fire a reconnect that was requested while backgrounded (if any). */
  private flushPendingReconnect(): void {
    if (!this.reconnectPending) {
      return;
    }
    this.reconnectPending = false;
    if (this.stopped || this.credentials?.pairingCode !== undefined) {
      return;
    }
    this.openChannels();
  }

  /**
   * The default network came back (ohos.net.connection): skip the rest of the
   * backoff and try now. Ignored while a connection is up or in flight, after an
   * explicit disconnect, and while backgrounded (the attempt is remembered and
   * fired by setForeground(true)).
   */
  retryNow(): void {
    if (this.stopped || this.credentials === undefined) {
      return;
    }
    if (this.credentials.pairingCode !== undefined) {
      return;
    }
    const state = this.state;
    if (state === GatewayConnectionState.CONNECTED || state === GatewayConnectionState.CONNECTING ||
      state === GatewayConnectionState.AUTHENTICATING) {
      return;
    }
    if (!this.foreground) {
      this.reconnectPending = true;
      return;
    }
    this.reconnectPending = false;
    if (this.reconnectTimer >= 0) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = -1;
    }
    this.openChannels();
  }

  private openChannels(): void {
    const credentials = this.credentials;
    if (credentials === undefined) {
      this.emitFailure(GatewayFailureKind.INTERNAL, '缺少连接凭据');
      return;
    }
    this.teardown();
    this.capabilities = [];
    this.emitState(GatewayConnectionState.CONNECTING, credentials.endpoint);
    const control = new ChannelSocket(ChannelLane.CONTROL);
    this.control = control;
    control.attach((text: string) => this.handleFrame(ChannelLane.CONTROL, text),
      (detail: string, closeCode: number) => this.handleChannelFailure(ChannelLane.CONTROL, detail, closeCode),
      () => this.emitState(GatewayConnectionState.AUTHENTICATING, '握手完成'));
    control.open(credentials, 'control');
  }

  private openConversation(): void {
    const credentials = this.credentials;
    if (credentials === undefined || this.conversation !== undefined) {
      return;
    }
    if (credentials.token === undefined || credentials.token.length === 0) {
      // Conversation never re-pairs; it needs the token returned by `paired`.
      return;
    }
    const conversation = new ChannelSocket(ChannelLane.CONVERSATION);
    this.conversation = conversation;
    const spec: GatewayCredentials = {
      endpoint: credentials.endpoint,
      deviceId: credentials.deviceId,
      token: credentials.token
    };
    conversation.attach((text: string) => this.handleFrame(ChannelLane.CONVERSATION, text),
      (detail: string, closeCode: number) => this.handleChannelFailure(ChannelLane.CONVERSATION, detail, closeCode),
      () => this.flushConversation());
    conversation.open(spec, 'conversation');
  }

  private teardown(): void {
    if (this.reconnectTimer >= 0) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = -1;
    }
    if (this.pingTimer >= 0) {
      clearTimeout(this.pingTimer);
      this.pingTimer = -1;
    }
    this.timeouts.forEach((armed: ArmedTimeout) => {
      clearTimeout(armed.timer);
    });
    this.timeouts.clear();
    this.pendingConversation = [];
    this.tracker.failAll('连接已断开');
    if (this.conversation !== undefined) {
      this.conversation.close();
      this.conversation = undefined;
    }
    if (this.control !== undefined) {
      this.control.close();
      this.control = undefined;
    }
  }

  private handleChannelFailure(lane: ChannelLane, detail: string, closeCode: number): void {
    if (lane === ChannelLane.CONVERSATION && this.state === GatewayConnectionState.CONNECTED) {
      this.conversation = undefined;
      this.emitFailure(GatewayFailureKind.NETWORK, `对话通道断开：${detail}`);
      this.openConversation();
      return;
    }
    if (closeCode === 4004) {
      this.stopped = true;
      this.teardown();
      this.emitState(GatewayConnectionState.DISCONNECTED, '移动网关已关闭');
      this.emitFailure(GatewayFailureKind.GATEWAY_DISABLED, '移动网关已关闭，请在 WebUI 重新开启');
      return;
    }
    if (closeCode === 4003) {
      this.teardown();
      this.emitState(GatewayConnectionState.FAILED, '鉴权已重新开启');
      this.emitFailure(GatewayFailureKind.AUTH_RESET, '服务端已重新开启鉴权，请用 token 重连或重新配对');
      return;
    }
    const pairing = this.credentials?.pairingCode !== undefined;
    this.teardown();
    if (this.stopped) {
      return;
    }
    if (pairing || this.reconnectAttempt === 0) {
      this.emitState(GatewayConnectionState.FAILED, detail);
      this.emitFailure(GatewayFailureKind.UPGRADE_REJECTED, detail);
      if (!pairing) {
        this.scheduleReconnect();
      }
      return;
    }
    this.emitFailure(GatewayFailureKind.NETWORK, detail);
    this.scheduleReconnect();
  }

  private scheduleReconnect(): void {
    if (this.stopped || this.credentials?.pairingCode !== undefined) {
      return;
    }
    if (!this.foreground) {
      // Backgrounded: arm nothing (the OS freezes timers while suspended anyway)
      // and remember the attempt; setForeground(true) fires it on return.
      this.reconnectPending = true;
      return;
    }
    this.reconnectAttempt += 1;
    const delay = Math.min(1000 * Math.pow(2, Math.min(this.reconnectAttempt, 5)), 30000);
    this.emitState(GatewayConnectionState.CONNECTING, `第 ${this.reconnectAttempt} 次重连，${Math.round(delay / 1000)}s 后`);
    if (this.reconnectTimer >= 0) {
      clearTimeout(this.reconnectTimer);
    }
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = -1;
      this.openChannels();
    }, delay);
  }

  private startHeartbeat(): void {
    if (this.pingTimer >= 0) {
      clearTimeout(this.pingTimer);
    }
    this.pingTimer = setTimeout(() => {
      this.pingTimer = -1;
      if (this.isConnected) {
        this.request('ping', new TypePayload('ping')).then((frame: WireFrame) => {
          void frame;
        }).catch((error: Error) => {
          void error;
        });
        this.startHeartbeat();
      }
    }, GatewayLimits.PING_INTERVAL_MS);
  }

  private handleFrame(lane: ChannelLane, text: string): void {
    const frame = decodeFrame(text);
    if (frame === null) {
      return;
    }
    const kind: string = frame.kind as string;

    if (kind === 'paired') {
      const token = frame.token;
      if (typeof token === 'string' && token.length > 0) {
        const current = this.credentials;
        if (current !== undefined) {
          this.credentials = { endpoint: current.endpoint, deviceId: current.deviceId, token: token };
        }
        for (const listener of this.listeners) {
          listener.onPaired(token);
        }
      }
      return;
    }

    if (kind === 'hello') {
      this.capabilities = Array.isArray(frame.capabilities) ? frame.capabilities : [];
      this.reconnectAttempt = 0;
      this.reconnectPending = false;
      this.emitState(GatewayConnectionState.CONNECTED, `端口 ${frame.port ?? 0}`);
      if (this.capabilities.indexOf('split-channels') >= 0 && lane === ChannelLane.CONTROL) {
        this.openConversation();
      }
      this.startHeartbeat();
    }

    if (this.settleIfPending(kind, frame, text)) {
      return;
    }

    for (const listener of this.listeners) {
      listener.onFrame(frame, text);
    }
  }

  private settleIfPending(kind: string, frame: WireFrame, raw: string): boolean {
    const correlation = correlationOf(frame) ?? '';
    const requestType = typeof frame.requestType === 'string' ? frame.requestType : '';
    const key = resolveSettleKey(kind, requestType, correlation,
      (candidate: string) => this.tracker.hasFlight(candidate));
    if (key.length === 0) {
      return false;
    }
    this.clearTimeoutFor(key);
    this.tracker.settle(key, frame);
    void raw;
    return true;
  }

  private clearTimeoutFor(key: string): void {
    const armed = this.timeouts.get(key);
    if (armed !== undefined) {
      clearTimeout(armed.timer);
      this.timeouts.delete(key);
    }
  }

  private armTimeout(request: GatewayRequest, token: number): void {
    if (this.timeouts.has(request.key)) {
      return;
    }
    const timer = setTimeout(() => {
      this.timeouts.delete(request.key);
      this.tracker.expire(request.key, token, `${request.type} 请求超时（${Math.round(request.timeoutMs / 1000)}s）`);
    }, request.timeoutMs);
    this.timeouts.set(request.key, { key: request.key, token: token, timer: timer });
  }

  private write(request: GatewayRequest): boolean {
    if (request.lane === ChannelLane.CONVERSATION) {
      const conversation = this.conversation;
      if (conversation !== undefined && conversation.isUsable()) {
        return conversation.send(request.payload);
      }
      if (this.capabilities.indexOf('split-channels') < 0) {
        // Legacy single-socket gateway: every lane rides the control socket.
        const legacy = this.control;
        return legacy !== undefined && legacy.isUsable() && legacy.send(request.payload);
      }
      // The gateway enforces channel ownership (message/history/subscribe/
      // unsubscribe must use the conversation socket) and answers the same
      // request on the control socket with `wrong-channel`. Queue it until that
      // socket opens; the armed request timeout still guards it.
      this.pendingConversation.push(request);
      return true;
    }
    const target = this.control;
    return target !== undefined && target.isUsable() && target.send(request.payload);
  }

  /**
   * Conversation socket is up: deliver what was queued meanwhile. A request that
   * already timed out (its flight is gone) is dropped — flushing it late would
   * send a message the user was told had failed.
   */
  private flushConversation(): void {
    const conversation = this.conversation;
    if (conversation === undefined || !conversation.isUsable() || this.pendingConversation.length === 0) {
      return;
    }
    const queued = this.pendingConversation;
    this.pendingConversation = [];
    for (const request of queued) {
      if (this.tracker.hasFlight(request.key)) {
        conversation.send(request.payload);
      }
    }
  }

  /** Send a request and await the correlated response. */
  async request(type: string, payload: Object, correlationId?: string): Promise<WireFrame> {
    if (!this.isConnected) {
      throw new NotConnectedError();
    }
    const request = buildRequest(type, payload, correlationId);
    const token = this.tracker.register(request);
    const promise = this.tracker.await(request, token);
    if (!this.write(request)) {
      this.tracker.fail(request.key, `${type} 发送失败：连接不可用`);
      throw new Error(`${type} 发送失败：连接不可用`);
    }
    this.armTimeout(request, token);
    const frame = await promise;
    // An error frame settles the lane like any other response, so it must be
    // turned into a rejection here — otherwise a refused write reports success
    // and the UI claims “已更新” while nothing changed on the host.
    if (frame.kind === 'error') {
      throw new Error(errorMessageOf(frame));
    }
    return frame;
  }

  /** Send without awaiting the response (subscribe / receipts). */
  notify(type: string, payload: Object): void {
    this.request(type, payload).then((frame: WireFrame) => {
      void frame;
    }).catch((error: Error) => {
      void error;
    });
  }

  /**
   * Idempotent session creation: the same `requestId` maps to the same result on
   * the server, so a retry can never create a second session.
   */
  async createSession(requestId: string, workspaceId?: string): Promise<string> {
    const payload = new SessionCreatePayload(requestId, workspaceId);
    const frame = await this.request('session-create', payload, requestId);
    if (frame.kind === 'error') {
      throw new Error(frame.message ?? '创建会话失败');
    }
    const sessionId = frame.sessionId;
    if (typeof sessionId !== 'string' || sessionId.length === 0) {
      throw new Error('创建会话失败：服务端未返回 sessionId');
    }
    return sessionId;
  }

  /**
   * Fallback for gateways without the `session-create` capability: an empty
   * `message` without `sessionId` makes the host create and enter the session.
   */
  async createSessionViaMessage(text: string, workspaceId?: string): Promise<string> {
    const payload = new MessagePayload(text, 'queue', undefined, workspaceId);
    const frame = await this.request('message', payload);
    const sessionId = frame.sessionId;
    if (typeof sessionId !== 'string' || sessionId.length === 0) {
      throw new Error('创建会话失败：服务端未返回 sessionId');
    }
    return sessionId;
  }
}

/** Human-readable text for a protocol error frame (`message` + `code`). */
export function errorMessageOf(frame: WireFrame): string {
  const message = typeof frame.message === 'string' && frame.message.length > 0
    ? frame.message
    : '请求被服务端拒绝';
  const code = typeof frame.code === 'string' ? frame.code : '';
  return code.length > 0 ? `${message}（${code}）` : message;
}

function correlationOf(frame: WireFrame): string | undefined {
  if (typeof frame.requestId === 'string' && frame.requestId.length > 0) {
    return frame.requestId;
  }
  if (typeof frame.transferId === 'string' && frame.transferId.length > 0) {
    return frame.transferId;
  }
  if (typeof frame.rpcId === 'string' && frame.rpcId.length > 0) {
    return frame.rpcId;
  }
  const attachment = frame.attachment;
  if (attachment !== undefined && typeof attachment.attachmentId === 'string') {
    return attachment.attachmentId;
  }
  return undefined;
}
