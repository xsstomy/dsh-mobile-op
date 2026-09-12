import { describe, expect, it } from '@ohos/hypium';
import {
  ChannelLane, LanePolicy, NotConnectedError, RequestBusyError, RequestTracker, buildRequest,
  fallbackResponseKindFor, isTransportUnavailable, laneForRequest, laneKeyFor, lanePolicyFor, requestTimeoutFor,
  resolveSettleKey, responseKindFor
} from '../main/ets/gateway/RequestTracker';
import { WireFrame } from '../main/ets/protocol/Types';
import { SESSION_CREATED_FRAME } from './fixtures/Frames';
import { decodeFrame } from '../main/ets/protocol/WireDecoder';
import { SessionPayload, TypePayload } from '../main/ets/protocol/Payloads';
import { frameOf } from './TestHelpers';

function frame(kind: string): WireFrame {
  return frameOf(kind);
}

export default function requestTrackerTest(): void {
  describe('requestTracker', () => {
    it('maps request types to lane policies like the protocol contract', 0, () => {
      expect(lanePolicyFor('sessions')).assertEqual(LanePolicy.COALESCE_LATEST);
      expect(lanePolicyFor('history')).assertEqual(LanePolicy.COALESCE_LATEST);
      expect(lanePolicyFor('session-create')).assertEqual(LanePolicy.REJECT_IF_BUSY);
      expect(lanePolicyFor('message')).assertEqual(LanePolicy.FIFO);
      expect(lanePolicyFor('attachment')).assertEqual(LanePolicy.FIFO);
    });

    it('maps request types to the correct lane and response kind', 0, () => {
      expect(laneForRequest('message')).assertEqual(ChannelLane.CONVERSATION);
      expect(laneForRequest('history')).assertEqual(ChannelLane.CONVERSATION);
      expect(laneForRequest('session-create')).assertEqual(ChannelLane.CONTROL);
      expect(responseKindFor('session-create')).assertEqual('session-created');
      expect(responseKindFor('session-archive')).assertEqual('session-archived');
      expect(responseKindFor('command-execute')).assertEqual('command-executed');
      expect(responseKindFor('file-download-read')).assertEqual('file-download-chunk');
      expect(requestTimeoutFor('session-create') > requestTimeoutFor('sessions')).assertTrue();
    });

    it('keys same-kind requests by correlation id so they never share a lane', 0, () => {
      const first = laneKeyFor('attachment', 'attachment', 'att-1');
      const second = laneKeyFor('attachment', 'attachment', 'att-2');
      expect(first === second).assertFalse();
      expect(first).assertEqual('attachment#att-1');
    });

    it('shares one coalesced flight between two callers', 0, async () => {
      const tracker = new RequestTracker();
      const request = buildRequest('sessions', new TypePayload('sessions'));
      const token = tracker.register(request);
      const first = tracker.await(request, token);
      const secondToken = tracker.register(request);
      expect(secondToken).assertEqual(token);
      const second = tracker.await(request, secondToken);

      const payload = decodeFrame(SESSION_CREATED_FRAME) as WireFrame;
      expect(tracker.settle(request.key, payload)).assertTrue();
      const firstFrame = await first;
      const secondFrame = await second;
      expect(firstFrame.kind).assertEqual('session-created');
      expect(secondFrame.kind).assertEqual('session-created');
      expect(tracker.pendingCount).assertEqual(0);
    });

    it('refuses a second REJECT_IF_BUSY request instead of queueing it', 0, () => {
      const tracker = new RequestTracker();
      const create = buildRequest('session-create', new TypePayload('session-create'), 'r1');
      tracker.register(create);
      tracker.await(create, 1);
      let busy = false;
      try {
        tracker.register(create);
      } catch (error) {
        busy = error instanceof RequestBusyError;
      }
      expect(busy).assertTrue();
    });

    it('resolves FIFO waiters oldest first', 0, async () => {
      const tracker = new RequestTracker();
      const first = buildRequest('message', new TypePayload('message'));
      const second = buildRequest('message', new TypePayload('message'));
      const token = tracker.register(first);
      const firstPromise = tracker.await(first, token);
      tracker.register(second);
      const secondPromise = tracker.await(second, token);
      expect(tracker.settle('sent', frame('sent'))).assertTrue();
      const firstFrame = await firstPromise;
      expect(firstFrame.kind).assertEqual('sent');
      expect(tracker.hasFlight('sent')).assertTrue();
      expect(tracker.settle('sent', frame('sent'))).assertTrue();
      const secondFrame = await secondPromise;
      expect(secondFrame.kind).assertEqual('sent');
    });

    it('only the owning token may expire a flight', 0, async () => {
      const tracker = new RequestTracker();
      const request = buildRequest('sessions', new TypePayload('sessions'));
      const token = tracker.register(request);
      const promise = tracker.await(request, token);
      expect(tracker.expire(request.key, token + 1, 'stale')).assertFalse();
      expect(tracker.expire(request.key, token, '请求超时')).assertTrue();
      let message = '';
      try {
        await promise;
      } catch (error) {
        message = (error as Error).message;
      }
      expect(message).assertEqual('请求超时');
    });

    it('drops a late response after a timeout instead of resolving a new request', 0, async () => {
      const tracker = new RequestTracker();
      const request = buildRequest('sessions', new TypePayload('sessions'));
      const token = tracker.register(request);
      const promise = tracker.await(request, token);
      tracker.expire(request.key, token, '请求超时');
      let failed = false;
      try {
        await promise;
      } catch (error) {
        failed = true;
      }
      expect(failed).assertTrue();
      expect(tracker.settle(request.key, frame('sessions'))).assertFalse();
    });

    it('fails every waiter when the connection drops', 0, async () => {
      const tracker = new RequestTracker();
      const request = buildRequest('workspaces', new TypePayload('workspaces'));
      const token = tracker.register(request);
      const promise = tracker.await(request, token);
      tracker.failAll('连接已断开');
      let message = '';
      try {
        await promise;
      } catch (error) {
        message = (error as Error).message;
      }
      expect(message).assertEqual('连接已断开');
      expect(tracker.pendingCount).assertEqual(0);
    });

    it('settles a bare message error frame on the message lane', 0, () => {
      const waiting: string[] = ['sent'];
      const has = (key: string): boolean => waiting.indexOf(key) >= 0;
      expect(resolveSettleKey('error', '', '', has)).assertEqual('sent');
    });

    it('prefers the requestType mapping when the error names it', 0, () => {
      const waiting: string[] = ['history'];
      const has = (key: string): boolean => waiting.indexOf(key) >= 0;
      expect(resolveSettleKey('error', 'history', '', has)).assertEqual('history');
      expect(resolveSettleKey('error', 'history', 'abc', has)).assertEqual('');
    });

    it('settles a correlated response by its wire correlation', 0, () => {
      const waiting: string[] = ['attachment#att-9'];
      const has = (key: string): boolean => waiting.indexOf(key) >= 0;
      expect(resolveSettleKey('attachment', '', 'att-9', has)).assertEqual('attachment#att-9');
      expect(resolveSettleKey('attachment', '', 'att-1', has)).assertEqual('');
    });

    it('returns empty when nothing is waiting', 0, () => {
      expect(resolveSettleKey('sessions', '', '', () => false)).assertEqual('');
      expect(resolveSettleKey('error', '', '', () => false)).assertEqual('');
    });

    it('treats only transport failures as retryable (B16)', 0, () => {
      const missing: Error = new NotConnectedError() as Error;
      const unwritten: Error = new Error('workspaces 发送失败：连接不可用');
      const dropped: Error = new Error('连接已断开');
      const refused: Error = new Error('bad-request');
      const timeout: Error = new Error('请求超时');
      expect(isTransportUnavailable(missing)).assertTrue();
      expect(isTransportUnavailable(unwritten)).assertTrue();
      expect(isTransportUnavailable(dropped)).assertTrue();
      expect(isTransportUnavailable(refused)).assertFalse();
      expect(isTransportUnavailable(timeout)).assertFalse();
    });

    it('never requires a second event-stream consumer', 0, () => {
      const tracker = new RequestTracker();
      const request = buildRequest('sessions', new TypePayload('sessions'));
      tracker.register(request);
      expect(tracker.hasFlight(request.key)).assertTrue();
      expect(tracker.pendingCount).assertEqual(1);
    });

    it('puts the target session in the lane key (session-bleed fix)', 0, () => {
      const first = buildRequest('history', new SessionPayload('history', 'session-a'));
      const second = buildRequest('history', new SessionPayload('history', 'session-b'));
      expect(first.key).assertEqual('history@session-a');
      expect(second.key).assertEqual('history@session-b');
      expect(first.targetSessionId).assertEqual('session-a');
      // A global query keeps the plain response-kind lane.
      const global = buildRequest('models', new TypePayload('models'));
      expect(global.key).assertEqual('models');
      // A per-request correlation still wins over the session suffix.
      const correlated = buildRequest('history', new SessionPayload('history', 'session-a'), 'r1');
      expect(correlated.key).assertEqual('history#r1');
    });

    it('never shares one flight between two sessions', 0, async () => {
      const tracker = new RequestTracker();
      const first = buildRequest('history', new SessionPayload('history', 'session-a'));
      const second = buildRequest('history', new SessionPayload('history', 'session-b'));
      const tokenA = tracker.register(first);
      const promiseA = tracker.await(first, tokenA);
      const tokenB = tracker.register(second);
      expect(tokenB === tokenA).assertFalse();
      const promiseB = tracker.await(second, tokenB);
      expect(tracker.pendingCount).assertEqual(2);

      const frameA = decodeFrame('{"kind":"history","sessionId":"session-a"}') as WireFrame;
      const frameB = decodeFrame('{"kind":"history","sessionId":"session-b"}') as WireFrame;
      expect(tracker.settle('history@session-a', frameA)).assertTrue();
      const resolvedA = await promiseA;
      expect(resolvedA.sessionId).assertEqual('session-a');
      expect(tracker.hasFlight('history@session-b')).assertTrue();
      expect(tracker.settle('history@session-b', frameB)).assertTrue();
      const resolvedB = await promiseB;
      expect(resolvedB.sessionId).assertEqual('session-b');
      expect(tracker.pendingCount).assertEqual(0);
    });

    it('still coalesces duplicate reads of the SAME session', 0, () => {
      const tracker = new RequestTracker();
      const first = buildRequest('tasks', new SessionPayload('tasks', 'session-a'));
      const second = buildRequest('tasks', new SessionPayload('tasks', 'session-a'));
      const token = tracker.register(first);
      expect(tracker.register(second)).assertEqual(token);
      expect(tracker.pendingCount).assertEqual(1);
    });

    it('settles a session-scoped reply by the frame session id', 0, () => {
      const has = (key: string): boolean => key === 'history@session-a';
      expect(resolveSettleKey('history', '', '', has, 'session-a')).assertEqual('history@session-a');
      expect(resolveSettleKey('history', '', '', has, 'session-b')).assertEqual('');
      // A reply without a session id must not borrow the session lane.
      expect(resolveSettleKey('history', '', '', has)).assertEqual('');
    });

    it('never falls back for a reply that names its exchange (session-bleed)', 0, () => {
      // A labeled reply belongs to exactly one lane: no global fallback at all.
      expect(fallbackResponseKindFor('history', '', 'session-a', '')).assertEqual('');
      expect(fallbackResponseKindFor('history', 'r1', '', '')).assertEqual('');
      // A session-less error that names a requestType cannot be attributed to a
      // session, so it must not settle a session-scoped lane either.
      expect(fallbackResponseKindFor('error', '', '', 'history')).assertEqual('');
      expect(fallbackResponseKindFor('error', '', '', '')).assertEqual('');
      // The measured session-less replies keep the oldest-first fallback.
      expect(fallbackResponseKindFor('models', '', '', '')).assertEqual('models');
      expect(fallbackResponseKindFor('history', '', '', '')).assertEqual('history');
    });

    it('settles the oldest same-kind lane when the reply has no session id', 0, async () => {
      const tracker = new RequestTracker();
      const first = buildRequest('models', new SessionPayload('models', 'session-a'));
      const second = buildRequest('models', new SessionPayload('models', 'session-b'));
      const tokenA = tracker.register(first);
      const promiseA = tracker.await(first, tokenA);
      const tokenB = tracker.register(second);
      const promiseB = tracker.await(second, tokenB);
      expect(tracker.pendingCount).assertEqual(2);

      // The gateway does not echo sessionId on `models`; oldest-first keeps the
      // two answers with the two requests instead of resolving both at once.
      const frameA = frame('models');
      expect(tracker.settleAny('models', frameA)).assertEqual('models@session-a');
      expect((await promiseA).kind).assertEqual('models');
      expect(tracker.settleAny('models', frame('models'))).assertEqual('models@session-b');
      expect((await promiseB).kind).assertEqual('models');
      expect(tracker.pendingCount).assertEqual(0);
    });
  });
}
