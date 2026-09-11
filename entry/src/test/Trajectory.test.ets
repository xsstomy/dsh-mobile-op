import { describe, expect, it } from '@ohos/hypium';
import { TrajectoryKind, TrajectoryRow, buildTrajectory, countByKind, turnDurations } from '../main/ets/projection/Trajectory';
import { WireSessionEvent } from '../main/ets/protocol/Types';
import { liveEvent, rawEvent } from './TestHelpers';
import {
  EVENT_ASSISTANT_MESSAGE, EVENT_CHUNK_TEXT, EVENT_TOOL_CALL, EVENT_TOOL_RESULT, EVENT_TURN_END,
  EVENT_USER_MESSAGE, HISTORY_RAW_TOOL_CALL, HISTORY_RAW_TOOL_RESULT, HISTORY_RAW_USER_MESSAGE
} from './fixtures/Frames';

function ev(raw: string): WireSessionEvent {
  return rawEvent(raw);
}

export default function trajectoryTest(): void {
  describe('trajectory', () => {
    it('maps raw history events into timeline rows', 0, () => {
      const rows: TrajectoryRow[] = buildTrajectory([
        ev('{"type":"turn/start","seq":1,"time":1000,"data":{"turn":1}}'),
        ev(HISTORY_RAW_USER_MESSAGE),
        ev(HISTORY_RAW_TOOL_CALL),
        ev(HISTORY_RAW_TOOL_RESULT),
        ev('{"type":"turn/end","seq":20,"time":6000,"data":{"turn":1,"reason":{"kind":"completed"}}}')
      ]);
      expect(rows.length).assertEqual(5);
      expect(rows[0].kind).assertEqual(TrajectoryKind.TURN);
      expect(rows[0].title).assertEqual('第 1 轮');
      expect(rows[1].kind).assertEqual(TrajectoryKind.USER);
      expect(rows[1].subtitle.length > 0).assertTrue();
      expect(rows[2].kind).assertEqual(TrajectoryKind.TOOL);
      expect(rows[2].title.indexOf('工具调用') >= 0).assertTrue();
      expect(rows[3].kind).assertEqual(TrajectoryKind.TOOL_RESULT);
      expect(rows[4].title).assertEqual('第 1 轮');
    });

    it('labels injected context separately from user messages', 0, () => {
      const flat = buildTrajectory([
        ev('{"type":"user/message","seq":2,"time":2000,"data":{"text":"系统注入","source":"plugin"}}')
      ]);
      expect(flat[0].kind).assertEqual(TrajectoryKind.CONTEXT);
      expect(flat[0].title.indexOf('plugin') >= 0).assertTrue();

      // Raw history shape: source is an object.
      const raw = buildTrajectory([
        ev('{"type":"user/message","seq":3,"time":3000,"data":{"content":[{"type":"text","text":"注入"}],"source":{"kind":"skill-catalog"}}}')
      ]);
      expect(raw[0].kind).assertEqual(TrajectoryKind.CONTEXT);
      expect(raw[0].title.indexOf('skill-catalog') >= 0).assertTrue();

      const user = buildTrajectory([
        ev('{"type":"user/message","seq":4,"time":4000,"data":{"content":[{"type":"text","text":"真的用户"}],"source":{"kind":"user"}}}')
      ]);
      expect(user[0].kind).assertEqual(TrajectoryKind.USER);
    });

    it('handles the flat live event shape', 0, () => {
      const user = liveEvent(EVENT_USER_MESSAGE);
      const chunk = liveEvent(EVENT_CHUNK_TEXT);
      const assistant = liveEvent(EVENT_ASSISTANT_MESSAGE);
      const rows = buildTrajectory([user, chunk, assistant]);
      expect(rows[0].kind).assertEqual(TrajectoryKind.USER);
      expect(rows[0].subtitle.length > 0).assertTrue();
      expect(rows[1].kind).assertEqual(TrajectoryKind.REASONING);
      expect(rows[2].kind).assertEqual(TrajectoryKind.ASSISTANT);
      expect(rows[2].subtitle.length > 0).assertTrue();
    });

    it('keeps the raw payload for the detail sheet', 0, () => {
      const rows = buildTrajectory([ev(HISTORY_RAW_TOOL_RESULT)]);
      expect(rows[0].detail.length > 0).assertTrue();
      expect(rows[0].detail.indexOf('tool-result') >= 0).assertTrue();
    });

    it('derives turn durations from start/end pairs', 0, () => {
      const rows = buildTrajectory([
        ev('{"type":"turn/start","seq":1,"time":1000,"data":{"turn":1}}'),
        ev('{"type":"turn/end","seq":9,"time":4500,"data":{"turn":1}}'),
        ev('{"type":"turn/start","seq":10,"time":5000,"data":{"turn":2}}')
      ]);
      const durations = turnDurations(rows);
      expect(durations.get(1)).assertEqual(3500);
      expect(durations.has(2)).assertFalse();
    });

    it('counts rows per kind', 0, () => {
      const rows = buildTrajectory([
        liveEvent(EVENT_TOOL_CALL), liveEvent(EVENT_TOOL_RESULT), liveEvent(EVENT_TURN_END)
      ]);
      expect(countByKind(rows, TrajectoryKind.TOOL)).assertEqual(1);
      expect(countByKind(rows, TrajectoryKind.TOOL_RESULT)).assertEqual(1);
      expect(countByKind(rows, TrajectoryKind.TURN)).assertEqual(1);
    });
  });
}
