/**
 * Session-roster reduction: title ordering and live row metadata.
 *
 * Mirrors the upstream SessionListReducer contract (titles are seq-ordered,
 * duplicate/older notifications are ignored) plus the client-side rule that a
 * `sessions` snapshot must not regress a row the live stream already advanced.
 */
import { describe, expect, it } from '@ohos/hypium';
import {
  applyEventToRoster, applySessionTitle, applySummaryTitles, displayTitleOf, mergeSessionRows,
  nextTitleSeq, projectedTitleOf, projectionsSeqOf, rosterIncludesSession, isTopLevelSession, SessionTitle,
  visibleSessionCount
} from '../main/ets/sync/Sessions';
import { WireSessionSummary, WireWorkspace } from '../main/ets/protocol/Types';
import { asSessionSummaries, decodeFrame } from '../main/ets/protocol/WireDecoder';
import { emptyEvent, titleEvent, userEvent } from './TestHelpers';
import { SESSIONS_FRAME } from './fixtures/Frames';

class Summary implements WireSessionSummary {
  sessionId: string;
  updatedAt: number;
  running: boolean;
  blank: boolean;
  cwd: string;
  agentPreset: string;
  projections?: Object;

  constructor(sessionId: string, updatedAt: number, running: boolean, blank: boolean) {
    this.sessionId = sessionId;
    this.updatedAt = updatedAt;
    this.running = running;
    this.blank = blank;
    this.cwd = '/w';
    this.agentPreset = 'ptc';
  }
}

/** Decode a real `sessions` frame so `projections` is a decoded JSON object. */
function roster(json: string): WireSessionSummary[] {
  const frame = decodeFrame(json);
  return frame === null ? [] : asSessionSummaries(frame);
}

function projectionsOf(title: string, asOfSeq: number): Object | undefined {
  const frame = decodeFrame(
    `{"kind":"sessions","items":[{"sessionId":"s1","projections":{"asOfSeq":${asOfSeq},"values":{"title":"${title}"}}}]}`);
  if (frame === null) {
    return undefined;
  }
  const rows = asSessionSummaries(frame);
  return rows.length > 0 ? rows[0].projections : undefined;
}

export default function sessionsTest(): void {
  describe('sessions', () => {
    it('reads the projected title and snapshot seq off a row', 0, () => {
      const values = roster(`{"kind":"sessions","items":[{"sessionId":"s1","projections":{"asOfSeq":42,"values":{"title":"开发计划"}}}]}`);
      expect(projectedTitleOf(values[0].projections)).assertEqual('开发计划');
      expect(projectionsSeqOf(values[0].projections)).assertEqual(42);
      expect(projectedTitleOf(undefined)).assertEqual('');
      expect(projectionsSeqOf(undefined)).assertEqual(0);
    });

    it('ignores duplicate and older title notifications', 0, () => {
      const titles: Map<string, SessionTitle> = new Map<string, SessionTitle>();
      expect(applySessionTitle(titles, 's1', '新名称', 129)).assertTrue();
      expect(displayTitleOf(titles, 's1')).assertEqual('新名称');
      expect(applySessionTitle(titles, 's1', '重复通知', 129)).assertFalse();
      expect(applySessionTitle(titles, 's1', '旧名称', 128)).assertFalse();
      expect(displayTitleOf(titles, 's1')).assertEqual('新名称');
      expect(applySessionTitle(titles, 's1', '再次改名', 130)).assertTrue();
      expect(displayTitleOf(titles, 's1')).assertEqual('再次改名');
      expect(applySessionTitle(titles, '', 'x', 1)).assertFalse();
      expect(applySessionTitle(titles, 's1', '', 200)).assertFalse();
      expect(nextTitleSeq(titles, 's1')).assertEqual(131);
      expect(nextTitleSeq(titles, 'missing')).assertEqual(1);
    });

    it('lets a live event outrank an older sessions snapshot and vice versa', 0, () => {
      const titles: Map<string, SessionTitle> = new Map<string, SessionTitle>();
      const stale = [new Summary('s1', 10, false, true)];
      stale[0].projections = projectionsOf('列表旧名', 2);
      expect(applySummaryTitles(titles, stale)).assertTrue();
      expect(displayTitleOf(titles, 's1')).assertEqual('列表旧名');
      // A live title at seq 5 is newer than the asOfSeq=2 snapshot.
      expect(applySessionTitle(titles, 's1', '实时新名', 5)).assertTrue();
      // A lagging snapshot (asOfSeq=4) must not roll it back.
      const lagging = [new Summary('s1', 10, false, true)];
      lagging[0].projections = projectionsOf('过期旧名', 4);
      expect(applySummaryTitles(titles, lagging)).assertFalse();
      expect(displayTitleOf(titles, 's1')).assertEqual('实时新名');
      // A snapshot that has caught up wins.
      const caught = [new Summary('s1', 10, false, true)];
      caught[0].projections = projectionsOf('最新名称', 9);
      expect(applySummaryTitles(titles, caught)).assertTrue();
      expect(displayTitleOf(titles, 's1')).assertEqual('最新名称');
    });

    it('falls back to the short id only when no title is known', 0, () => {
      const titles: Map<string, SessionTitle> = new Map<string, SessionTitle>();
      expect(displayTitleOf(titles, 'session-e1e01e03-feec-4270-ae29-fa1e8c7a1bd7'))
        .assertEqual('e1e01e03');
      expect(displayTitleOf(titles, 'plain')).assertEqual('plain');
      expect(displayTitleOf(titles, '')).assertEqual('');
    });

    it('decoded sessions fixture keeps null titles out of the name slot', 0, () => {
      const rows = roster(SESSIONS_FRAME);
      const titles: Map<string, SessionTitle> = new Map<string, SessionTitle>();
      expect(applySummaryTitles(titles, rows)).assertFalse();
      expect(titles.size).assertEqual(0);
    });

    it('folds live activity into the roster row', 0, () => {
      const rows: WireSessionSummary[] = [new Summary('s1', 1, false, true)];
      expect(applyEventToRoster(rows, 's1', userEvent(8, '你好', 'user'))).assertTrue();
      expect(rows[0].blank).assertFalse();
      expect(rows[0].updatedAt).assertEqual(8);
      expect(applyEventToRoster(rows, 's1', emptyEvent(9, 'turn/start'))).assertTrue();
      expect(rows[0].running).assertTrue();
      expect(rows[0].updatedAt).assertEqual(9);
      expect(applyEventToRoster(rows, 's1', titleEvent(10, '标题'))).assertFalse();
      expect(applyEventToRoster(rows, 's1', emptyEvent(11, 'assistant/chunk'))).assertFalse();
      expect(applyEventToRoster(rows, 's1', emptyEvent(12, 'turn/end'))).assertTrue();
      expect(rows[0].running).assertFalse();
      expect(applyEventToRoster(rows, 'unknown', emptyEvent(13, 'turn/end'))).assertFalse();
    });

    it('does not let a stale snapshot regress a fresh row', 0, () => {
      const current: WireSessionSummary[] = [new Summary('s1', 500, false, false)];
      const incoming: WireSessionSummary[] = [new Summary('s1', 100, false, true)];
      const merged = mergeSessionRows(current, incoming);
      expect(merged[0].updatedAt).assertEqual(500);
      expect(merged[0].blank).assertFalse();
      // A newer snapshot still wins.
      const newer: WireSessionSummary[] = [new Summary('s1', 900, false, false)];
      expect(mergeSessionRows(current, newer)[0].updatedAt).assertEqual(900);
      // A row with no local history is left alone.
      const born = mergeSessionRows(current, [new Summary('s2', 10, false, true)]);
      expect(born[0].blank).assertTrue();
    });

    it('keeps the roster scoped but never hides an ungrouped session', 0, () => {
      const workspaces: WireWorkspace[] = [
        { workspaceId: 'w1', sessionIds: ['s1', 's2'] },
        { workspaceId: 'w2', sessionIds: ['s3'] }
      ];
      // No selection: nothing is filtered.
      expect(rosterIncludesSession(workspaces, '', 's3')).assertTrue();
      // The selected workspace's own sessions show.
      expect(rosterIncludesSession(workspaces, 'w1', 's1')).assertTrue();
      // Another workspace's session stays scoped out.
      expect(rosterIncludesSession(workspaces, 'w1', 's3')).assertFalse();
      // A session no workspace owns (desktop-created by path only) must show.
      expect(rosterIncludesSession(workspaces, 'w1', 'ungrouped')).assertTrue();
      // A stale selection shows everything instead of an empty list.
      expect(rosterIncludesSession(workspaces, 'gone', 's3')).assertTrue();
      // A workspace with no ids listed never filters.
      expect(rosterIncludesSession([{ workspaceId: 'w1' }], 'w1', 'anything')).assertTrue();
    });

    it('keeps subagent sessions out of the roster', 0, () => {
      // The host marks a subagent's own session; the gateway forwards both fields.
      expect(isTopLevelSession({ sessionId: 'session-a' })).assertTrue();
      expect(isTopLevelSession({ sessionId: 'child', origin: 'subagent' })).assertFalse();
      expect(isTopLevelSession({ sessionId: 'child', parentSessionId: 'session-a' })).assertFalse();
      // Either marker alone is enough, and an unrelated origin still counts as
      // top-level (only the measured 'subagent' value means "not a conversation").
      expect(isTopLevelSession({ sessionId: 'child', origin: 'subagent', parentSessionId: 'session-a' })).assertFalse();
      expect(isTopLevelSession({ sessionId: 'session-b', origin: 'user' })).assertTrue();
    });

    it('counts only the sessions a workspace tile can actually open', 0, () => {
      const rows: WireSessionSummary[] = [
        { sessionId: 'session-a' },
        { sessionId: 'child', origin: 'subagent', parentSessionId: 'session-a' },
        { sessionId: 'session-b' }
      ];
      // The subagent row is listed by the host but hidden by the roster.
      expect(visibleSessionCount(['session-a', 'child', 'session-b'], rows, [])).assertEqual(2);
      // Archived ones are gone from the list too.
      expect(visibleSessionCount(['session-a', 'session-b'], rows, ['session-b'])).assertEqual(1);
      // An id the roster has not seen yet still counts (no row to judge).
      expect(visibleSessionCount(['session-a', 'unknown'], rows, [])).assertEqual(2);
      expect(visibleSessionCount([], rows, [])).assertEqual(0);
    });
  });
}
