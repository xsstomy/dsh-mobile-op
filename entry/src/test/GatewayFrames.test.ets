import { describe, expect, it } from '@ohos/hypium';
import { asQueueItems, asSessionSummaries, asWorkspaces, decodeFrame, supportsCapability } from '../main/ets/protocol/WireDecoder';
import {
  SESSION_ARCHIVES_FRAME, SESSION_QUEUES_FRAME, SESSION_QUEUE_FRAME, SESSIONS_FRAME, WORKSPACES_FRAME
} from './fixtures/Frames';

export default function gatewayFramesTest(): void {
  describe('gatewayFrames', () => {
    it('reads workspaces from the host `items` field', 0, () => {
      const frame = decodeFrame(WORKSPACES_FRAME);
      const workspaces = asWorkspaces(frame!);
      expect(workspaces.length > 0).assertTrue();
      expect(typeof workspaces[0].workspaceId).assertEqual('string');
    });

    it('reads session summaries with the projection block', 0, () => {
      const frame = decodeFrame(SESSIONS_FRAME);
      const sessions = asSessionSummaries(frame!);
      expect(sessions.length > 0).assertTrue();
      expect(typeof sessions[0].sessionId).assertEqual('string');
      expect(sessions[0].projections !== undefined).assertTrue();
    });

    it('decodes the queue snapshot and per-session replacement frames', 0, () => {
      const snapshot = decodeFrame(SESSION_QUEUES_FRAME);
      expect(snapshot?.kind).assertEqual('session-queues');
      expect(snapshot?.queues !== undefined).assertTrue();

      const replacement = decodeFrame(SESSION_QUEUE_FRAME);
      expect(replacement?.kind).assertEqual('session-queue');
      expect(Array.isArray(replacement?.items)).assertTrue();
      expect(asQueueItems(replacement!).length >= 0).assertTrue();
    });

    it('decodes the archived session id set', 0, () => {
      const frame = decodeFrame(SESSION_ARCHIVES_FRAME);
      expect(Array.isArray(frame?.archivedSessionIds)).assertTrue();
    });

    it('does not treat an unknown capability as supported', 0, () => {
      const frame = decodeFrame(WORKSPACES_FRAME);
      expect(supportsCapability(frame?.capabilities ?? [], 'split-channels')).assertFalse();
    });
  });
}
