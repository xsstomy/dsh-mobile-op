/**
 * History paging + live tail merge (pure logic, unit tested).
 *
 * Rules (see docs/PROTOCOL.md §5 and upstream HistorySyncEngine):
 *  - pages are requested with `beforeSeq: nextBeforeSeq` and shrink per byte budget
 *  - events are deduplicated by `seq`; a live event may arrive before its page
 *  - `session/title` changes arrive both as a live event and as the
 *    `session-title-changed` push: handling must stay idempotent
 */
import { WireSessionEvent } from '../protocol/Types';

export interface HistoryPage {
  events: WireSessionEvent[];
  hasMore: boolean;
  nextBeforeSeq?: number;
  bytes: number;
  projections?: Object;
}

export interface MergeOutcome {
  events: WireSessionEvent[];
  /**
   * True when the page overlaps the local baseline (a fresh reload of the same
   * range). A page that is entirely older only extends history backwards.
   */
  replaced: boolean;
  /** True when the page extended history backwards. */
  prepended: boolean;
  added: number;
}

function seqOf(event: WireSessionEvent): number {
  return typeof event.seq === 'number' ? event.seq : -1;
}

function headerValueOf(event: WireSessionEvent): string {
  const type = event.type ?? '';
  const time = typeof event.time === 'number' ? String(event.time) : '';
  return `${type}#${time}#${JSON.stringify(event.data ?? {})}`;
}

/** Sort by seq, drop duplicates (keep newest), keep events without seq in arrival order. */
export function normalizeEvents(events: WireSessionEvent[]): WireSessionEvent[] {
  const withSeq: WireSessionEvent[] = [];
  const withoutSeq: WireSessionEvent[] = [];
  const seen: Map<number, number> = new Map<number, number>();
  for (const event of events) {
    const seq = seqOf(event);
    if (seq < 0) {
      withoutSeq.push(event);
      continue;
    }
    const previous = seen.get(seq);
    if (previous === undefined) {
      seen.set(seq, withSeq.length);
      withSeq.push(event);
    } else {
      withSeq[previous] = event;
    }
  }
  withSeq.sort((left: WireSessionEvent, right: WireSessionEvent) => seqOf(left) - seqOf(right));
  const result: WireSessionEvent[] = [];
  for (const event of withoutSeq) {
    result.push(event);
  }
  for (const event of withSeq) {
    result.push(event);
  }
  return result;
}

/**
 * Merge one history page into the local timeline.
 * Pages that start before the local baseline replace the baseline; a page that
 * only fills gaps merges in place (live tail is never dropped).
 */
export function mergeHistoryPage(existing: WireSessionEvent[], page: WireSessionEvent[]): MergeOutcome {
  const normalizedPage = normalizeEvents(page);
  if (normalizedPage.length === 0) {
    return { events: existing, replaced: false, prepended: false, added: 0 };
  }
  const pageNewest = seqOf(normalizedPage[normalizedPage.length - 1]);
  const localOldest = existing.length > 0 ? seqOf(existing[0]) : -1;
  // A page whose newest seq is below the local oldest only extends the past.
  const prepended = existing.length > 0 && pageNewest >= 0 && localOldest >= 0 && pageNewest < localOldest;
  const replaced = existing.length > 0 && !prepended;
  const merged: WireSessionEvent[] = [];
  for (const event of existing) {
    merged.push(event);
  }
  for (const event of normalizedPage) {
    merged.push(event);
  }
  const before = existing.length;
  const result = normalizeEvents(merged);
  return { events: result, replaced: replaced, prepended: prepended, added: Math.max(0, result.length - before) };
}

/** Upsert one live event by seq. */
export function mergeLiveEvent(existing: WireSessionEvent[], event: WireSessionEvent): MergeOutcome {
  const seq = seqOf(event);
  if (seq < 0) {
    const appended: WireSessionEvent[] = [];
    for (const item of existing) {
      appended.push(item);
    }
    appended.push(event);
    return { events: appended, replaced: false, prepended: false, added: 1 };
  }
  const result: WireSessionEvent[] = [];
  let replacedEvent = false;
  for (const item of existing) {
    if (seqOf(item) === seq) {
      result.push(event);
      replacedEvent = true;
    } else {
      result.push(item);
    }
  }
  if (!replacedEvent) {
    result.push(event);
    result.sort((left: WireSessionEvent, right: WireSessionEvent) => seqOf(left) - seqOf(right));
    return { events: result, replaced: false, prepended: false, added: 1 };
  }
  return { events: result, replaced: true, prepended: false, added: 0 };
}

export function isTitleEvent(event: WireSessionEvent): boolean {
  return (event.type ?? '') === 'session/title';
}

export function titleOf(event: WireSessionEvent): string {
  const data = event.data;
  if (data === undefined || data === null) {
    return '';
  }
  const record = data as Record<string, Object>;
  const title = record['title'];
  return typeof title === 'string' ? title : '';
}

export function dedupeKeyOf(event: WireSessionEvent): string {
  return `${seqOf(event)}:${headerValueOf(event)}`;
}
