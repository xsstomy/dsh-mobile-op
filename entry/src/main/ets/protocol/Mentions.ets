/**
 * `@file` mention grammar, candidate filtering and splice (pure logic, tested).
 *
 * The host already treats an `@path` (or `@"path with spaces"`) token in the
 * prompt as a workspace path (`FILE_REFERENCE_PROMPT`), so the client only has
 * to detect the token at the caret, offer candidates and splice the path back.
 * Ported from `@deepseek-ai/dsh-file-reference/grammar`.
 */
import { FileEntryRow } from './Files';

/** Active `@` token ending at the caret. */
export interface ActiveAtToken {
  /** Complete token replaced when a completion is accepted. */
  prefix: string;
  /** Path query after `@` or `@"`. */
  query: string;
  /** True when the user opened a quoted path. */
  quoted: boolean;
}

/** Which directory to list and which entry-name prefix to keep. */
export interface MentionTarget {
  /** Directory relative to the session cwd; empty means the cwd itself. */
  directory: string;
  /** Entry names must start with this (case-insensitive). */
  prefix: string;
}

/** Draft + caret after splicing one completion in. */
export interface MentionSplice {
  text: string;
  caret: number;
}

function isWhitespace(value: string): boolean {
  return value.length > 0 && /^\s$/.test(value);
}

function clamp(value: number, min: number, max: number): number {
  if (value < min) {
    return min;
  }
  if (value > max) {
    return max;
  }
  return value;
}

/**
 * `@path` / `@"path` token ending at the caret. An `@` inside another token
 * (an email address) is not a completion trigger.
 */
export function activeAtToken(line: string, cursorCol: number): ActiveAtToken | undefined {
  const end = clamp(cursorCol, 0, line.length);
  const before = line.substring(0, end);
  const quoteStart = before.lastIndexOf('@"');
  if (quoteStart >= 0 && (quoteStart === 0 || isWhitespace(before.charAt(quoteStart - 1)))) {
    const body = before.substring(quoteStart + 2);
    if (body.indexOf('"') < 0) {
      return { prefix: before.substring(quoteStart), query: body, quoted: true };
    }
  }
  const at = before.lastIndexOf('@');
  if (at < 0) {
    return undefined;
  }
  if (at > 0 && !isWhitespace(before.charAt(at - 1))) {
    return undefined;
  }
  const body = before.substring(at + 1);
  for (let i = 0; i < body.length; i += 1) {
    if (isWhitespace(body.charAt(i))) {
      return undefined;
    }
  }
  return { prefix: before.substring(at), query: body, quoted: false };
}

/**
 * `@` token at the caret inside a multi-line draft. `activeAtToken` works on
 * the caret's own line, which is what the quoted-path grammar expects.
 */
export function activeAtTokenInDraft(draft: string, caret: number): ActiveAtToken | undefined {
  const end = clamp(caret, 0, draft.length);
  const lineStart = end > 0 ? draft.lastIndexOf('\n', end - 1) + 1 : 0;
  return activeAtToken(draft.substring(lineStart), end - lineStart);
}

/** Split the query after `@` into a directory to list and a name prefix. */
export function mentionTargetOf(query: string): MentionTarget {
  const slash = query.lastIndexOf('/');
  if (slash < 0) {
    return { directory: '', prefix: query };
  }
  return { directory: query.substring(0, slash), prefix: query.substring(slash + 1) };
}

/** File rows whose name starts with `prefix` (case-insensitive). */
export function filterMentionEntries(entries: FileEntryRow[], prefix: string): FileEntryRow[] {
  const needle = prefix.toLowerCase();
  const result: FileEntryRow[] = [];
  for (const entry of entries) {
    if (needle.length === 0 || entry.name.toLowerCase().startsWith(needle)) {
      result.push(entry);
    }
  }
  return result;
}

/**
 * Format a selected path as prompt text. Whitespace uses the quoted
 * `@"path"` grammar; a quoted directory keeps the quote open after its
 * trailing slash so the completion can descend another level.
 */
export function formatFileMention(path: string, isDirectory: boolean, preserveQuote: boolean): string | undefined {
  const target = isDirectory && !path.endsWith('/') ? `${path}/` : path;
  if (/[\u0000-\u001f\u007f-\u009f"]/.test(target)) {
    return undefined;
  }
  const quoted = preserveQuote || /\s/.test(target);
  if (!quoted) {
    return `@${target}`;
  }
  if (isDirectory) {
    return `@"${target}`;
  }
  return `@"${target}"`;
}

/** Replace the active token with `insertion` and report the new caret. */
export function applyMention(draft: string, caret: number, token: ActiveAtToken, insertion: string): MentionSplice {
  const end = clamp(caret, 0, draft.length);
  const start = clamp(end - token.prefix.length, 0, end);
  return {
    text: draft.substring(0, start) + insertion + draft.substring(end),
    caret: start + insertion.length
  };
}
