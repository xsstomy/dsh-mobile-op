import { describe, expect, it } from '@ohos/hypium';
import { mergeHistoryPage, mergeLiveEvent, normalizeEvents, titleOf } from '../main/ets/sync/History';
import { WireSessionEvent } from '../main/ets/protocol/Types';
import { HISTORY_FRAME, SESSION_TITLE_CHANGED_FRAME } from './fixtures/Frames';
import { asSessionEvents, decodeFrame } from '../main/ets/protocol/WireDecoder';
import { emptyEvent, titleEvent } from './TestHelpers';

function event(seq: number, type: string): WireSessionEvent {
  return emptyEvent(seq, type);
}

export default function historyTest(): void {
  describe('history', () => {
    it('projects the captured history page without duplication', 0, () => {
      const frame = decodeFrame(HISTORY_FRAME);
      const events = asSessionEvents(frame!);
      const first = mergeHistoryPage([], events);
      expect(first.events.length).assertEqual(events.length);
      const second = mergeHistoryPage(first.events, events);
      expect(second.events.length).assertEqual(events.length);
      expect(second.added).assertEqual(0);
    });

    it('sorts by seq and keeps the newest duplicate', 0, () => {
      const normalized = normalizeEvents([
        event(3, 'c'),
        event(1, 'old'),
        event(1, 'new'),
        event(2, 'b')
      ]);
      expect(normalized.length).assertEqual(3);
      expect(normalized[0].type).assertEqual('new');
      expect(normalized[1].type).assertEqual('b');
      expect(normalized[2].type).assertEqual('c');
    });

    it('extends history backwards without replacing the live baseline', 0, () => {
      const baseline = [event(10, 'a'), event(11, 'b')];
      const older = [event(5, 'x'), event(6, 'y')];
      const outcome = mergeHistoryPage(baseline, older);
      expect(outcome.prepended).assertTrue();
      expect(outcome.replaced).assertFalse();
      expect(outcome.events.length).assertEqual(4);
      expect(outcome.events[0].seq).assertEqual(5);
    });

    it('replaces the baseline when a page overlaps it', 0, () => {
      const baseline = [event(10, 'a'), event(11, 'b')];
      const overlapping = [event(11, 'b2'), event(12, 'c')];
      const outcome = mergeHistoryPage(baseline, overlapping);
      expect(outcome.replaced).assertTrue();
      expect(outcome.prepended).assertFalse();
      expect(outcome.events.length).assertEqual(3);
      expect(outcome.events[2].seq).assertEqual(12);
    });

    it('merges a page that only fills the gap before the live tail', 0, () => {
      const live = [event(20, 'live')];
      const page = [event(15, 'p1'), event(16, 'p2')];
      const outcome = mergeHistoryPage(live, page);
      expect(outcome.prepended).assertTrue();
      expect(outcome.replaced).assertFalse();
      expect(outcome.events.length).assertEqual(3);
      expect(outcome.events[2].seq).assertEqual(20);
    });

    it('upserts a live event by seq and appends new ones in order', 0, () => {
      let events: WireSessionEvent[] = [event(1, 'a'), event(3, 'c')];
      events = mergeLiveEvent(events, event(2, 'b')).events;
      expect(events.length).assertEqual(3);
      expect(events[1].type).assertEqual('b');
      const replaced = mergeLiveEvent(events, event(3, 'c-updated'));
      expect(replaced.replaced).assertTrue();
      expect(replaced.events.length).assertEqual(3);
      expect(replaced.events[2].type).assertEqual('c-updated');
    });

    it('reads the title from a session/title event', 0, () => {
      expect(titleOf(titleEvent(4, 'hello'))).assertEqual('hello');
    });

    it('keeps the session-title-changed push shape stable', 0, () => {
      const frame = decodeFrame(SESSION_TITLE_CHANGED_FRAME);
      expect(frame?.kind).assertEqual('session-title-changed');
      expect(typeof frame?.title).assertEqual('string');
      expect(typeof frame?.seq).assertEqual('number');
    });
  });
}
