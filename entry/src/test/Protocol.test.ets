import { describe, expect, it } from '@ohos/hypium';
import { asSessionEvents, asSessionSummaries, asWorkspaces, decodeFrame, supportsCapability } from '../main/ets/protocol/WireDecoder';
import { HELLO_FRAME, HISTORY_FRAME, SESSIONS_FRAME, WORKSPACES_FRAME, WRONG_CHANNEL_ERROR } from './fixtures/Frames';

export default function protocolTest(): void {
  describe('protocol', () => {
    it('decodes every captured frame kind', 0, () => {
      const hello = decodeFrame(HELLO_FRAME);
      expect(hello !== null).assertTrue();
      expect(hello?.kind).assertEqual('hello');
      expect(hello?.protocol).assertEqual(3);
      expect(supportsCapability(hello?.capabilities ?? [], 'split-channels')).assertTrue();
      expect(supportsCapability(hello?.capabilities ?? [], 'session-create')).assertTrue();
      expect(supportsCapability(hello?.capabilities ?? [], 'file-downloads')).assertTrue();

      const workspaces = decodeFrame(WORKSPACES_FRAME);
      expect(workspaces !== null).assertTrue();
      expect(asWorkspaces(workspaces!).length > 0).assertTrue();

      const sessions = decodeFrame(SESSIONS_FRAME);
      expect(sessions !== null).assertTrue();
      expect(asSessionSummaries(sessions!).length > 0).assertTrue();

      const history = decodeFrame(HISTORY_FRAME);
      expect(history !== null).assertTrue();
      expect(asSessionEvents(history!).length > 0).assertTrue();
    });

    it('keeps unknown kinds instead of throwing', 0, () => {
      const future = decodeFrame('{"kind":"brand-new-frame","payload":{"a":1}}');
      expect(future !== null).assertTrue();
      expect(future?.kind).assertEqual('brand-new-frame');
    });

    it('rejects malformed input without throwing', 0, () => {
      expect(decodeFrame('not json')).assertNull();
      expect(decodeFrame('[]')).assertNull();
      expect(decodeFrame('{"noKind":true}')).assertNull();
      expect(decodeFrame('"a string"')).assertNull();
    });

    it('surfaces the wrong-channel error frame with its requestType', 0, () => {
      const frame = decodeFrame(WRONG_CHANNEL_ERROR);
      expect(frame?.kind).assertEqual('error');
      expect(frame?.code).assertEqual('wrong-channel');
      expect(frame?.requestType).assertEqual('history');
    });

    it('normalises an unknown capability gate to false', 0, () => {
      expect(supportsCapability([], 'goals')).assertFalse();
    });
  });
}
