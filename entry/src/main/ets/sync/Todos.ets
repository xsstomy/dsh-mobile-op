/**
 * Todo-list projection maths (pure, unit tested).
 *
 * Frames (PROTOCOL.md 6.1): the `tasks` reply and the `tasks-updated` push
 * both carry a flat `todos: [{content, status}]`; `todos: null` means the
 * session never wrote a list, so the panel hides instead of showing empty.
 */
import { WireTodo } from '../protocol/Types';

export interface TodoRow {
  content: string;
  status: string;
}

export interface TodoProgress {
  done: number;
  active: number;
  pending: number;
  total: number;
}

/** U+2002 en space + middle dot, matching the WebUI progress line. */
const PROGRESS_SEPARATOR =
  String.fromCharCode(0x2002) + String.fromCharCode(0xb7) + String.fromCharCode(0x2002);

/** `null` is meaningful (never written) and is preserved. */
export function todoRowsOf(todos: WireTodo[] | null | undefined): TodoRow[] | null {
  if (todos === undefined || todos === null) {
    return null;
  }
  const rows: TodoRow[] = [];
  for (const todo of todos) {
    rows.push({ content: todo.content ?? '', status: todo.status ?? 'pending' });
  }
  return rows;
}

export function todoProgressOf(todos: TodoRow[] | null): TodoProgress {
  const rows: TodoRow[] = todos ?? [];
  let done = 0;
  let active = 0;
  for (const row of rows) {
    if (row.status === 'completed') {
      done = done + 1;
    } else if (row.status === 'in_progress') {
      active = active + 1;
    }
  }
  return { done: done, active: active, pending: rows.length - done - active, total: rows.length };
}

/** e.g. `1 进行中 · 7 待处理` - zero segments are dropped as noise (WebUI parity). */
export function todoProgressLabel(progress: TodoProgress): string {
  const parts: string[] = [];
  if (progress.done > 0) {
    parts.push(progress.done.toString() + ' 已完成');
  }
  if (progress.active > 0) {
    parts.push(progress.active.toString() + ' 进行中');
  }
  if (progress.pending > 0) {
    parts.push(progress.pending.toString() + ' 待处理');
  }
  return parts.join(PROGRESS_SEPARATOR);
}

/**
 * Apply a frame only when its `asOfSeq` is not older than the applied one, so a
 * slow `tasks` query result cannot overwrite a newer `tasks-updated` push.
 */
export function shouldApplyTodos(incomingSeq: number | undefined, appliedSeq: number): boolean {
  if (incomingSeq === undefined) {
    return true;
  }
  return incomingSeq >= appliedSeq;
}