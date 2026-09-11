import { describe, expect, it } from '@ohos/hypium';
import { applyTurnActivity, turnIdle, turnRunning } from '../main/ets/projection/TurnActivity';

const NOW = 1789045000000;

export default function turnActivityTest(): void {
  describe('turnActivity', () => {
    it('starts idle', 0, () => {
      const state = turnIdle();
      expect(state.active).assertFalse();
      expect(state.startedAt).assertEqual(0);
    });

    it('treats an unknown start as unknown, not as now', 0, () => {
      expect(turnRunning(0).active).assertTrue();
      expect(turnRunning(0).startedAt).assertEqual(0);
      expect(turnRunning(NOW).startedAt).assertEqual(NOW);
    });

    it('opens a turn on turn/start using the event clock', 0, () => {
      const state = applyTurnActivity(turnIdle(), 'turn/start', NOW - 500, NOW);
      expect(state.active).assertTrue();
      expect(state.startedAt).assertEqual(NOW - 500);
    });

    it('falls back to the local clock when the frame has no time', 0, () => {
      const state = applyTurnActivity(turnIdle(), 'turn/start', 0, NOW);
      expect(state.startedAt).assertEqual(NOW);
    });

    it('opens a turn on user/message but keeps the first known start', 0, () => {
      const opened = applyTurnActivity(turnIdle(), 'user/message', NOW - 100, NOW);
      expect(opened.active).assertTrue();
      expect(opened.startedAt).assertEqual(NOW - 100);
      // A following steering message must not restart the elapsed clock.
      const steered = applyTurnActivity(opened, 'user/message', NOW, NOW);
      expect(steered.startedAt).assertEqual(NOW - 100);
    });

    it('closes the turn on turn/end and on both error events', 0, () => {
      const running = turnRunning(NOW - 100);
      expect(applyTurnActivity(running, 'turn/end', NOW, NOW).active).assertFalse();
      expect(applyTurnActivity(running, 'agent/error', NOW, NOW).active).assertFalse();
      expect(applyTurnActivity(running, 'session/error', NOW, NOW).active).assertFalse();
      expect(applyTurnActivity(running, 'turn/end', NOW, NOW).startedAt).assertEqual(0);
    });

    it('ignores unrelated events, including a turn/end when already idle', 0, () => {
      const running = turnRunning(NOW - 100);
      const after = applyTurnActivity(running, 'assistant/chunk', NOW, NOW);
      expect(after.startedAt).assertEqual(NOW - 100);
      const idle = applyTurnActivity(turnIdle(), 'turn/end', NOW, NOW);
      expect(idle.active).assertFalse();
    });
  });
}
