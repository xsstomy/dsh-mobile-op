/**
 * Session-roster title + row reduction (pure logic, unit tested).
 *
 * A session's display name is the same slot in three places:
 *  - the live `session/title` event of a subscribed conversation,
 *  - the `session-title-changed` / `session-renamed` metadata push,
 *  - the `projections.values.title` cell of a `sessions` / `history` row.
 *
 * They can arrive in any order (a `sessions` round trip can be one beat older
 * than a live event; a rename is echoed twice). Every observation therefore
 * carries a sequence and only a newer sequence may replace the stored title,
 * otherwise the home roster and the open conversation would drift apart and
 * an old snapshot would roll a rename back.
 *
 * The live roster row (blank / running / updatedAt) is folded from the events
 * too, so the home list reflects activity instead of waiting for the next
 * full `sessions` request.
 */
import { WireSessionEvent, WireSessionSummary, WireWorkspace } from '../protocol/Types';

/** One session's display title plus the sequence that produced it. */
export class SessionTitle {
  title: string;
  seq: number;

  constructor(title: string, seq: number) {
    this.title = title;
    this.seq = seq;
  }
}

/** Event types that change a roster row's activity fields. */
const ROSTER_EVENTS: string[] = ['user/message', 'turn/start', 'turn/end', 'assistant/message'];

/** `projections.values` of a `sessions` / `history` frame, when present. */
function projectionValues(projections: Object | undefined): Record<string, Object> | undefined {
  if (projections === undefined || projections === null) {
    return undefined;
  }
  const values = (projections as Record<string, Object>)['values'];
  if (values === undefined || values === null || typeof values !== 'object' || Array.isArray(values)) {
    return undefined;
  }
  return values as Record<string, Object>;
}

/** The projected title of a `sessions` / `history` projection block ('' when none). */
export function projectedTitleOf(projections: Object | undefined): string {
  const values = projectionValues(projections);
  if (values === undefined) {
    return '';
  }
  const title = values['title'];
  return typeof title === 'string' ? title : '';
}

/**
 * The snapshot sequence of a projection block. The title cell is the latest
 * title at or before this seq, so it is a safe upper bound for ordering.
 */
export function projectionsSeqOf(projections: Object | undefined): number {
  if (projections === undefined || projections === null) {
    return 0;
  }
  const seq = (projections as Record<string, Object>)['asOfSeq'];
  return typeof seq === 'number' ? seq : 0;
}

/**
 * Record one title observation. Returns true when the stored title changed.
 * An equal or older seq is a replay or a lagging snapshot and is ignored, so
 * the `session/title` event and its `session-title-changed` twin stay idempotent.
 */
export function applySessionTitle(
  titles: Map<string, SessionTitle>, sessionId: string, title: string, seq: number
): boolean {
  if (sessionId.length === 0 || title.length === 0) {
    return false;
  }
  const previous = titles.get(sessionId);
  if (previous !== undefined && seq <= previous.seq) {
    return false;
  }
  titles.set(sessionId, new SessionTitle(title, seq));
  return true;
}

/** Apply every `sessions` row's projected title, ordered by its `asOfSeq`. */
export function applySummaryTitles(
  titles: Map<string, SessionTitle>, sessions: WireSessionSummary[]
): boolean {
  let changed = false;
  for (const session of sessions) {
    const title = projectedTitleOf(session.projections);
    if (title.length === 0) {
      continue;
    }
    if (applySessionTitle(titles, session.sessionId ?? '', title, projectionsSeqOf(session.projections))) {
      changed = true;
    }
  }
  return changed;
}

/** Display name for a session: the stored title, else the short id. */
export function displayTitleOf(titles: Map<string, SessionTitle>, sessionId: string): string {
  const entry = titles.get(sessionId);
  if (entry !== undefined && entry.title.length > 0) {
    return entry.title;
  }
  if (sessionId.length === 0) {
    return '';
  }
  return sessionId.startsWith('session-') ? sessionId.substring(8, 16) : sessionId;
}

/** Next seq for a local write that has no server sequence yet. */
export function nextTitleSeq(titles: Map<string, SessionTitle>, sessionId: string): number {
  const entry = titles.get(sessionId);
  return entry === undefined ? 1 : entry.seq + 1;
}

/**
 * Fold one live event into a roster row so the home list tracks activity
 * without waiting for the next full `sessions` request. Returns true when a
 * field changed.
 */
export function applyEventToSummary(session: WireSessionSummary, event: WireSessionEvent): boolean {
  const type = event.type ?? '';
  if (ROSTER_EVENTS.indexOf(type) < 0) {
    return false;
  }
  let changed = false;
  if (typeof event.time === 'number' && event.time > (session.updatedAt ?? 0)) {
    session.updatedAt = event.time;
    changed = true;
  }
  if (type === 'turn/start') {
    if (session.running !== true) {
      session.running = true;
      changed = true;
    }
    if (session.blank === true) {
      session.blank = false;
      changed = true;
    }
  } else if (type === 'turn/end') {
    if (session.running === true) {
      session.running = false;
      changed = true;
    }
  } else if (type === 'user/message' && session.blank === true) {
    session.blank = false;
    changed = true;
  }
  return changed;
}

/** Apply a live event to the matching roster row. */
export function applyEventToRoster(
  sessions: WireSessionSummary[], sessionId: string, event: WireSessionEvent
): boolean {
  for (const session of sessions) {
    if ((session.sessionId ?? '') === sessionId) {
      return applyEventToSummary(session, event);
    }
  }
  return false;
}

/**
 * Reconcile a fresh `sessions` snapshot with the rows already in hand. The
 * server may still describe a session that local events already moved past
 * (blank / older timestamp); a regression would make the home roster
 * contradict the conversation that is open right above it.
 */
export function mergeSessionRows(
  current: WireSessionSummary[], incoming: WireSessionSummary[]
): WireSessionSummary[] {
  const previous = new Map<string, WireSessionSummary>();
  for (const session of current) {
    previous.set(session.sessionId ?? '', session);
  }
  for (const session of incoming) {
    const old = previous.get(session.sessionId ?? '');
    if (old === undefined) {
      continue;
    }
    if (typeof old.updatedAt === 'number' && old.updatedAt > (session.updatedAt ?? 0)) {
      session.updatedAt = old.updatedAt;
    }
    if (old.blank === false && session.blank === true) {
      session.blank = false;
    }
  }
  return incoming;
}

/**
 * Whether a session belongs on the home roster for the workspace in view.
 *
 * The host groups a session under the workspace it was created in
 * (`workspace.sessionIds`), but a session created elsewhere by path only — the
 * desktop WebUI sends `cwd` and no `workspaceId` — belongs to no workspace at
 * all. Those "ungrouped" sessions were dropped together with the other
 * workspaces' rows, so a conversation just created on the desktop stayed
 * invisible on the phone even after tapping 刷新 (its `cwd` matches the
 * workspace, so the host still lists it under that project).
 *
 * Keep the roster scoped to the selected workspace, but never hide a session
 * that no workspace owns. A session owned by a *different* workspace still
 * stays out, so switching the workspace keeps scoping the list.
 */
/**
 * Whether a roster row belongs in the session list the user sees.
 *
 * A subagent runs its own session, and the host marks those rows with
 * `origin: 'subagent'` plus the `parentSessionId` they belong to. They are not
 * conversations the user opened, and the host refuses to serve their history
 * (`session/agent-busy`), so listing them only produces dead entries.
 */
export function isTopLevelSession(session: WireSessionSummary): boolean {
  if (session.origin === 'subagent') {
    return false;
  }
  const parent = session.parentSessionId ?? '';
  return parent.length === 0;
}

/**
 * Count the sessions a workspace tile should advertise.
 *
 * `workspace.sessionIds` lists every session the host attached, subagent sessions
 * included, but the roster hides those (see `isTopLevelSession`) — the tile must
 * count what the user can actually open, or the list and the badge disagree.
 * Ids the host did not attach to this workspace are left uncounted here; the
 * roster's ungrouped rule is applied when a session has no workspace at all.
 */
export function visibleSessionCount(
  sessionIds: string[], rows: WireSessionSummary[], archived: string[]
): number {
  let count = 0;
  for (const sessionId of sessionIds) {
    if (sessionId.length === 0 || archived.indexOf(sessionId) >= 0) {
      continue;
    }
    let known: WireSessionSummary | undefined = undefined;
    for (const row of rows) {
      if ((row.sessionId ?? '') === sessionId) {
        known = row;
        break;
      }
    }
    if (known === undefined || isTopLevelSession(known)) {
      count += 1;
    }
  }
  return count;
}

export function rosterIncludesSession(
  workspaces: WireWorkspace[], selectedWorkspaceId: string, sessionId: string
): boolean {
  if (selectedWorkspaceId.length === 0) {
    return true;
  }
  let selected: WireWorkspace | undefined = undefined;
  for (const workspace of workspaces) {
    if ((workspace.workspaceId ?? '') === selectedWorkspaceId) {
      selected = workspace;
      break;
    }
  }
  if (selected === undefined) {
    // The persisted selection is gone; showing everything beats an empty list.
    return true;
  }
  const ids = selected.sessionIds ?? [];
  if (ids.length === 0 || ids.indexOf(sessionId) >= 0) {
    return true;
  }
  for (const workspace of workspaces) {
    if ((workspace.workspaceId ?? '') === selectedWorkspaceId) {
      continue;
    }
    if ((workspace.sessionIds ?? []).indexOf(sessionId) >= 0) {
      return false;
    }
  }
  return true;
}
