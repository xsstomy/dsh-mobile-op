/**
 * Request lanes + correlation table.
 *
 * One "flight" per correlation key. The socket receive loop is the ONLY caller of
 * `settle()`, so several UI consumers observe frames through broadcast callbacks
 * and never compete for a single-consumer channel (the upstream Android defect).
 *
 * Policies:
 *  - COALESCE_LATEST: while a flight is open, another request of the same kind
 *    joins it and shares the result (idempotent state queries).
 *  - FIFO: several waiters of the same kind are resolved oldest-first ('sent').
 *  - REJECT_IF_BUSY: a second concurrent request is refused.
 *
 * A request timeout only fails that flight; it must never close the connection.
 */
import { GatewayLimits } from '../common/Constants';
import { WireFrame } from '../protocol/Types';

export enum ChannelLane {
  CONTROL = 'control',
  CONVERSATION = 'conversation'
}

export enum LanePolicy {
  COALESCE_LATEST = 'coalesce-latest',
  FIFO = 'fifo',
  REJECT_IF_BUSY = 'reject-if-busy'
}

export interface GatewayRequest {
  readonly type: string;
  readonly key: string;
  readonly responseKind: string;
  readonly lane: ChannelLane;
  readonly lanePolicy: LanePolicy;
  readonly payload: string;
  readonly timeoutMs: number;
  readonly targetSessionId?: string;
}

export class RequestBusyError extends Error {
  constructor(type: string) {
    super(`上一个 ${type} 请求仍在处理中，请稍后重试`);
  }
}

export class NotConnectedError extends Error {
  constructor() {
    super('尚未连接到 DeepSeek Harness');
  }
}

/**
 * True when a request never reached the wire: the socket was still handshaking
 * or mid-teardown when the caller wrote. These are the only failures a caller
 * may safely retry - every other error is a real answer from the host.
 */
export function isTransportUnavailable(error: Error): boolean {
  if (error instanceof NotConnectedError) {
    return true;
  }
  const message = error.message;
  return message.indexOf('连接不可用') >= 0 || message.indexOf('连接已断开') >= 0;
}

interface Waiter {
  readonly token: number;
  readonly resolve: (frame: WireFrame) => void;
  readonly reject: (error: Error) => void;
}

interface Flight {
  readonly token: number;
  readonly policy: LanePolicy;
  readonly type: string;
  readonly waiters: Waiter[];
}

export function laneKeyFor(type: string, responseKind: string, correlationId?: string): string {
  if (correlationId !== undefined && correlationId.length > 0) {
    return `${responseKind}#${correlationId}`;
  }
  return responseKind;
}

const CONVERSATION_TYPES: string[] = ['message', 'history', 'subscribe', 'unsubscribe'];

export function laneForRequest(type: string): ChannelLane {
  return CONVERSATION_TYPES.indexOf(type) >= 0 ? ChannelLane.CONVERSATION : ChannelLane.CONTROL;
}

const COALESCE_TYPES: string[] = [
  'workspaces', 'sessions', 'history', 'models', 'providers', 'permission-options', 'context-usage',
  'session-stats', 'tasks', 'goal', 'agent-presets', 'defaults', 'default-model', 'commands',
  'directories', 'host', 'search', 'file-list'
];

const REJECT_TYPES: string[] = [
  'session-create', 'session-archive', 'session-rename', 'session-cancel', 'fork',
  'goal-edit', 'goal-pause', 'goal-resume', 'goal-clear', 'queue-update',
  'select-model', 'permission', 'set-default', 'save-default-model'
];

export function lanePolicyFor(type: string): LanePolicy {
  if (COALESCE_TYPES.indexOf(type) >= 0) {
    return LanePolicy.COALESCE_LATEST;
  }
  if (REJECT_TYPES.indexOf(type) >= 0) {
    return LanePolicy.REJECT_IF_BUSY;
  }
  return LanePolicy.FIFO;
}

/** Expected response kind for a request type (identity unless the protocol differs). */
export function responseKindFor(type: string): string {
  switch (type) {
    case 'ping':
      return 'pong';
    case 'message':
      return 'sent';
    case 'subscribe':
    case 'unsubscribe':
      return 'subscribed';
    case 'command-options':
      return 'command-options';
    case 'command-select':
      return 'command-selected';
    case 'queue-update':
      return 'queue-item-updated';
    case 'session-create':
      return 'session-created';
    case 'session-archive':
      return 'session-archived';
    case 'session-rename':
      return 'session-renamed';
    case 'session-cancel':
      return 'session-cancelled';
    case 'command-execute':
      return 'command-executed';
    case 'question-answer':
    case 'question-cancel':
      return 'question-response';
    case 'file-download-open':
      return 'file-download-opened';
    case 'file-download-read':
      return 'file-download-chunk';
    case 'file-download-cancel':
      return 'file-download-cancelled';
    default:
      return type;
  }
}

export function requestTimeoutFor(type: string): number {
  return type === 'session-create' ? GatewayLimits.SESSION_CREATE_TIMEOUT_MS : GatewayLimits.REQUEST_TIMEOUT_MS;
}

export function buildRequest(type: string, payload: Object, correlationId?: string): GatewayRequest {
  const responseKind = responseKindFor(type);
  return {
    type: type,
    key: laneKeyFor(type, responseKind, correlationId),
    responseKind: responseKind,
    lane: laneForRequest(type),
    lanePolicy: lanePolicyFor(type),
    payload: JSON.stringify(payload),
    timeoutMs: requestTimeoutFor(type)
  };
}

/**
 * Which pending lane does an incoming frame settle? Returns '' when nothing waits.
 *
 * Subtlety (measured on a real device): `message` failures arrive as a bare
 * `error` frame WITHOUT `requestType`, so they must settle the pending message
 * lane instead of being broadcast and left to time out.
 */
export function resolveSettleKey(kind: string, requestType: string, correlation: string,
  hasFlight: (key: string) => boolean): string {
  const direct = laneKeyFor(kind, kind, correlation.length > 0 ? correlation : undefined);
  if (hasFlight(direct)) {
    return direct;
  }
  if (kind !== 'error') {
    return '';
  }
  if (requestType.length > 0) {
    const mapped = laneKeyFor(requestType, responseKindFor(requestType), correlation.length > 0 ? correlation : undefined);
    return hasFlight(mapped) ? mapped : '';
  }
  // Direct-send failure: only the message lane can be waiting without correlation.
  return hasFlight('sent') ? 'sent' : '';
}

export class RequestTracker {
  private readonly flights: Map<string, Flight> = new Map<string, Flight>();
  private tokenSeq: number = 0;

  /** Claim (or join) a flight. Throws RequestBusyError when the policy refuses. */
  register(request: GatewayRequest): number {
    const existing = this.flights.get(request.key);
    if (existing !== undefined) {
      if (request.lanePolicy === LanePolicy.REJECT_IF_BUSY) {
        throw new RequestBusyError(request.type);
      }
      return existing.token;
    }
    this.tokenSeq += 1;
    this.flights.set(request.key, {
      token: this.tokenSeq,
      policy: request.lanePolicy,
      type: request.type,
      waiters: []
    });
    return this.tokenSeq;
  }

  /** Wait for the flight to settle. Resolves immediately for a joined flight. */
  await(request: GatewayRequest, token: number): Promise<WireFrame> {
    return new Promise<WireFrame>((resolve: (frame: WireFrame) => void, reject: (error: Error) => void) => {
      const flight = this.flights.get(request.key);
      if (flight === undefined) {
        reject(new Error(`${request.type} 请求已被取消`));
        return;
      }
      const waiter: Waiter = { token: token, resolve: resolve, reject: reject };
      flight.waiters.push(waiter);
    });
  }

  hasFlight(key: string): boolean {
    return this.flights.has(key);
  }

  tokenOf(key: string): number {
    const flight = this.flights.get(key);
    return flight === undefined ? 0 : flight.token;
  }

  /** Resolve waiters. COALESCE_LATEST resolves every waiter; others oldest-first. */
  settle(key: string, frame: WireFrame): boolean {
    const flight = this.flights.get(key);
    if (flight === undefined) {
      return false;
    }
    if (flight.policy === LanePolicy.COALESCE_LATEST) {
      this.flights.delete(key);
      for (const waiter of flight.waiters) {
        waiter.resolve(frame);
      }
      return true;
    }
    const waiter = flight.waiters.shift();
    if (flight.waiters.length === 0) {
      this.flights.delete(key);
    }
    if (waiter === undefined) {
      return false;
    }
    waiter.resolve(frame);
    return true;
  }

  /** Timeout fired: only the owning token may fail the flight. */
  expire(key: string, token: number, message: string): boolean {
    const flight = this.flights.get(key);
    if (flight === undefined || flight.token !== token) {
      return false;
    }
    this.flights.delete(key);
    for (const waiter of flight.waiters) {
      waiter.reject(new Error(message));
    }
    return true;
  }

  fail(key: string, message: string): boolean {
    const flight = this.flights.get(key);
    if (flight === undefined) {
      return false;
    }
    this.flights.delete(key);
    for (const waiter of flight.waiters) {
      waiter.reject(new Error(message));
    }
    return true;
  }

  failAll(message: string): void {
    const keys: string[] = [];
    this.flights.forEach((flight: Flight, key: string) => {
      void flight;
      keys.push(key);
    });
    for (const key of keys) {
      this.fail(key, message);
    }
  }

  get pendingCount(): number {
    return this.flights.size;
  }
}
