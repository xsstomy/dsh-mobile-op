/**
 * Pure formatting helpers: relative time and a small Markdown segmenter.
 *
 * The upstream clients render Markdown with Markwon / MarkdownUI. ArkUI has no
 * Markdown component, so this module splits a message into displayable segments
 * (heading / code fence / rule / quote / list / paragraph) that the UI renders
 * with the design system's typography. No inline styling is applied yet.
 */
export enum SegmentKind {
  HEADING = 'heading',
  CODE = 'code',
  RULE = 'rule',
  QUOTE = 'quote',
  LIST = 'list',
  PARAGRAPH = 'paragraph',
  TABLE = 'table'
}

/** Inline emphasis kinds produced by `parseInline`. */
export enum InlineKind {
  PLAIN = 'plain',
  BOLD = 'bold',
  ITALIC = 'italic',
  CODE = 'code',
  LINK = 'link',
  STRIKE = 'strike'
}

export interface InlineSpan {
  text: string;
  kind: InlineKind;
}

/** Syntax classes produced by `highlightCode`. */
export enum TokenKind {
  PLAIN = 'plain',
  KEYWORD = 'keyword',
  STRING = 'string',
  COMMENT = 'comment',
  NUMBER = 'number',
  FUNCTION = 'function'
}

export interface CodeSpan {
  text: string;
  kind: TokenKind;
}

export interface MarkdownSegment {
  kind: SegmentKind;
  /** Heading level (1..6), 0 otherwise. */
  level: number;
  /** Fence language label (`bash`, `ts`, …), empty when unknown. */
  language: string;
  text: string;
  /** Table rows (first row is the header) when `kind` is TABLE. */
  rows: string[][];
}

function segment(kind: SegmentKind, level: number, language: string, text: string): MarkdownSegment {
  return { kind: kind, level: level, language: language, text: text, rows: [] };
}

/** Parse `**bold**`, `*italic*`, `` `code` ``, `~~strike~~` and `[text](url)`. */
export function parseInline(text: string): InlineSpan[] {
  const spans: InlineSpan[] = [];
  let index = 0;
  let buffer = '';
  const push = (value: string, kind: InlineKind): void => {
    if (value.length === 0) {
      return;
    }
    spans.push({ text: value, kind: kind });
  };
  const flush = (): void => {
    push(buffer, InlineKind.PLAIN);
    buffer = '';
  };
  while (index < text.length) {
    const rest = text.substring(index);
    if (rest.startsWith('**')) {
      const end = rest.indexOf('**', 2);
      if (end > 2) {
        flush();
        push(rest.substring(2, end), InlineKind.BOLD);
        index += end + 2;
        continue;
      }
    }
    if (rest.startsWith('~~')) {
      const end = rest.indexOf('~~', 2);
      if (end > 2) {
        flush();
        push(rest.substring(2, end), InlineKind.STRIKE);
        index += end + 2;
        continue;
      }
    }
    if (rest.startsWith('`')) {
      const end = rest.indexOf('`', 1);
      if (end > 1) {
        flush();
        push(rest.substring(1, end), InlineKind.CODE);
        index += end + 1;
        continue;
      }
    }
    if (rest.startsWith('[')) {
      const labelEnd = rest.indexOf('](');
      const urlEnd = labelEnd > 0 ? rest.indexOf(')', labelEnd + 2) : -1;
      if (labelEnd > 0 && urlEnd > labelEnd) {
        flush();
        push(rest.substring(1, labelEnd), InlineKind.LINK);
        index += urlEnd + 1;
        continue;
      }
    }
    if (rest.startsWith('*') && !rest.startsWith('**')) {
      const end = rest.indexOf('*', 1);
      if (end > 1 && rest.charAt(end + 1) !== '*') {
        flush();
        push(rest.substring(1, end), InlineKind.ITALIC);
        index += end + 1;
        continue;
      }
    }
    buffer += text.charAt(index);
    index += 1;
  }
  flush();
  return spans;
}

const LANGUAGE_KEYWORDS: string[] = [
  'const', 'let', 'var', 'function', 'return', 'if', 'else', 'for', 'while', 'import', 'from', 'export',
  'default', 'class', 'extends', 'new', 'await', 'async', 'try', 'catch', 'throw', 'interface', 'type',
  'enum', 'public', 'private', 'readonly', 'static', 'this', 'null', 'undefined', 'true', 'false',
  'sudo', 'cd', 'echo', 'export', 'npm', 'npx', 'node', 'git', 'tail', 'grep', 'curl', 'dsh', 'pnpm'
];

function isKeyword(word: string): boolean {
  return LANGUAGE_KEYWORDS.indexOf(word) >= 0;
}

/** Very small tokenizer for the languages that show up in agent output. */
export function highlightCode(code: string, language: string): CodeSpan[] {
  const spans: CodeSpan[] = [];
  const isHash = language === 'bash' || language === 'sh' || language === 'shell' || language === 'yaml';
  let index = 0;
  let plain = '';
  const flushPlain = (): void => {
    if (plain.length > 0) {
      spans.push({ text: plain, kind: TokenKind.PLAIN });
      plain = '';
    }
  };
  while (index < code.length) {
    const rest = code.substring(index);
    if ((isHash && rest.startsWith('#')) || (!isHash && rest.startsWith('//'))) {
      const end = rest.indexOf('\n');
      const comment = end < 0 ? rest : rest.substring(0, end);
      flushPlain();
      spans.push({ text: comment, kind: TokenKind.COMMENT });
      index += comment.length;
      continue;
    }
    if (rest.startsWith('/*')) {
      const end = rest.indexOf('*/', 2);
      const comment = end < 0 ? rest : rest.substring(0, end + 2);
      flushPlain();
      spans.push({ text: comment, kind: TokenKind.COMMENT });
      index += comment.length;
      continue;
    }
    const ch = code.charAt(index);
    if (ch === '"' || ch === '\'' || ch === '`') {
      let end = index + 1;
      while (end < code.length && code.charAt(end) !== ch) {
        if (code.charAt(end) === '\\') {
          end += 1;
        }
        end += 1;
      }
      const literal = code.substring(index, Math.min(end + 1, code.length));
      flushPlain();
      spans.push({ text: literal, kind: TokenKind.STRING });
      index += literal.length;
      continue;
    }
    if (ch >= '0' && ch <= '9') {
      let end = index;
      while (end < code.length && ((code.charAt(end) >= '0' && code.charAt(end) <= '9') || code.charAt(end) === '.')) {
        end += 1;
      }
      flushPlain();
      spans.push({ text: code.substring(index, end), kind: TokenKind.NUMBER });
      index = end;
      continue;
    }
    if ((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch === '_' || ch === '$') {
      let end = index;
      while (end < code.length) {
        const next = code.charAt(end);
        if ((next >= 'a' && next <= 'z') || (next >= 'A' && next <= 'Z') ||
          (next >= '0' && next <= '9') || next === '_' || next === '$') {
          end += 1;
        } else {
          break;
        }
      }
      const word = code.substring(index, end);
      flushPlain();
      if (isKeyword(word)) {
        spans.push({ text: word, kind: TokenKind.KEYWORD });
      } else if (code.charAt(end) === '(') {
        spans.push({ text: word, kind: TokenKind.FUNCTION });
      } else {
        spans.push({ text: word, kind: TokenKind.PLAIN });
      }
      index = end;
      continue;
    }
    plain += ch;
    index += 1;
  }
  flushPlain();
  return spans;
}

function splitTableRow(line: string): string[] {
  let body = line.replace(/^\s+/, '').replace(/\s+$/, '');
  if (body.startsWith('|')) {
    body = body.substring(1);
  }
  if (body.endsWith('|')) {
    body = body.substring(0, body.length - 1);
  }
  const cells: string[] = [];
  for (const cell of body.split('|')) {
    cells.push(cell.replace(/^\s+|\s+$/g, ''));
  }
  return cells;
}

function isTableSeparator(line: string): boolean {
  const cells = splitTableRow(line);
  if (cells.length === 0) {
    return false;
  }
  for (const cell of cells) {
    if (cell.length < 3) {
      return false;
    }
    for (let index = 0; index < cell.length; index += 1) {
      const ch = cell.charAt(index);
      if (ch !== '-' && ch !== ':' && ch !== ' ') {
        return false;
      }
    }
  }
  return true;
}

/**
 * Elapsed-time label: `12.3s` / `1m20s`. Empty for an unknown duration (`<= 0`),
 * so callers can omit the segment instead of printing `—` next to real data.
 * `views/SessionStatsBar.formatDuration` delegates here (single implementation).
 */
export function durationLabel(milliseconds: number): string {
  if (!Number.isFinite(milliseconds) || milliseconds <= 0) {
    return '';
  }
  const seconds = milliseconds / 1000;
  if (seconds < 60) {
    return `${seconds.toFixed(1)}s`;
  }
  const minutes = Math.floor(seconds / 60);
  const rest = Math.round(seconds - minutes * 60);
  return `${minutes}m${rest}s`;
}

/**
 * Compact token count: `999`, `1.2k`, `1.5M`. Kept next to `durationLabel` so the
 * stats bar and the turn footer agree on how a number is shortened.
 */
export function tokenLabel(tokens: number): string {
  if (!Number.isFinite(tokens) || tokens <= 0) {
    return '0';
  }
  if (tokens >= 1000000) {
    return `${(tokens / 1000000).toFixed(1)}M`;
  }
  if (tokens >= 1000) {
    return `${(tokens / 1000).toFixed(1)}k`;
  }
  return `${tokens}`;
}

/**
 * Wall-clock point of an answer: `HH:mm` for today, `MM-DD HH:mm` for older
 * turns, and empty when the timestamp is unknown (`<= 0` / not finite).
 */
export function clockTimeOf(epochMillis: number, nowMillis: number): string {
  if (!Number.isFinite(epochMillis) || epochMillis <= 0) {
    return '';
  }
  const date = new Date(epochMillis);
  const hours = `${date.getHours()}`.padStart(2, '0');
  const minutes = `${date.getMinutes()}`.padStart(2, '0');
  const now = new Date(Number.isFinite(nowMillis) && nowMillis > 0 ? nowMillis : epochMillis);
  const sameDay = date.getFullYear() === now.getFullYear() && date.getMonth() === now.getMonth() &&
    date.getDate() === now.getDate();
  if (sameDay) {
    return `${hours}:${minutes}`;
  }
  const month = `${date.getMonth() + 1}`.padStart(2, '0');
  const dayOfMonth = `${date.getDate()}`.padStart(2, '0');
  return `${month}-${dayOfMonth} ${hours}:${minutes}`;
}

/**
 * One-line turn footer: `1.2k tokens · 用时 12.3s · 20:15` (upstream: the answer
 * meta line). Segments whose data is missing are omitted — never `0 tokens`, a
 * bare `—` or a dangling `·` — and the whole line is empty when nothing is known.
 */
export function turnFooterText(tokens: number, startedAt: number, endedAt: number, now: number): string {
  const segments: string[] = [];
  if (Number.isFinite(tokens) && tokens > 0) {
    segments.push(`${tokenLabel(tokens)} tokens`);
  }
  if (startedAt > 0 && endedAt > startedAt) {
    const label = durationLabel(endedAt - startedAt);
    if (label.length > 0) {
      segments.push(`用时 ${label}`);
    }
  }
  const clock = clockTimeOf(endedAt, now);
  if (clock.length > 0) {
    segments.push(clock);
  }
  return segments.join(' · ');
}

export function relativeTime(epochMillis: number, nowMillis: number): string {
  if (!Number.isFinite(epochMillis) || epochMillis <= 0) {
    return '';
  }
  const delta = nowMillis - epochMillis;
  if (delta < 0) {
    return '刚刚';
  }
  const minute = 60 * 1000;
  const hour = 60 * minute;
  const day = 24 * hour;
  if (delta < minute) {
    return '刚刚';
  }
  if (delta < hour) {
    return `${Math.floor(delta / minute)} 分钟前`;
  }
  if (delta < day) {
    return `${Math.floor(delta / hour)} 小时前`;
  }
  if (delta < 2 * day) {
    return '昨天';
  }
  if (delta < 30 * day) {
    return `${Math.floor(delta / day)} 天前`;
  }
  const date = new Date(epochMillis);
  const month = `${date.getMonth() + 1}`.padStart(2, '0');
  const dayOfMonth = `${date.getDate()}`.padStart(2, '0');
  return `${date.getFullYear()}-${month}-${dayOfMonth}`;
}

function headingLevelOf(line: string): number {
  let level = 0;
  while (level < line.length && line.charAt(level) === '#') {
    level += 1;
  }
  if (level === 0 || level > 6 || level >= line.length || line.charAt(level) !== ' ') {
    return 0;
  }
  return level;
}

function isRuleLine(line: string): boolean {
  const trimmed = line.replace(/\s/g, '');
  if (trimmed.length < 3) {
    return false;
  }
  for (let index = 0; index < trimmed.length; index += 1) {
    const ch = trimmed.charAt(index);
    if (ch !== '-' && ch !== '*' && ch !== '_') {
      return false;
    }
  }
  return true;
}

function listMarkerLength(line: string): number {
  const trimmed = line.replace(/^\s+/, '');
  if (trimmed.startsWith('- ') || trimmed.startsWith('* ') || trimmed.startsWith('+ ')) {
    return 2;
  }
  let digits = 0;
  while (digits < trimmed.length && trimmed.charAt(digits) >= '0' && trimmed.charAt(digits) <= '9') {
    digits += 1;
  }
  if (digits > 0 && digits + 1 < trimmed.length &&
    trimmed.charAt(digits) === '.' && trimmed.charAt(digits + 1) === ' ') {
    return digits + 2;
  }
  return 0;
}

function flushParagraph(buffer: string[], segments: MarkdownSegment[]): void {
  if (buffer.length === 0) {
    return;
  }
  const text = buffer.join('\n').replace(/\s+$/, '');
  buffer.length = 0;
  if (text.replace(/\s/g, '').length === 0) {
    // Blank lines separate blocks; they must not render as empty paragraphs.
    return;
  }
  segments.push(segment(SegmentKind.PARAGRAPH, 0, '', text));
}

/** Split a Markdown message into renderable segments. */
export function segmentMarkdown(text: string): MarkdownSegment[] {
  const segments: MarkdownSegment[] = [];
  if (text.length === 0) {
    return segments;
  }
  const lines = text.split('\n');
  const paragraph: string[] = [];
  let index = 0;
  while (index < lines.length) {
    const line = lines[index];
    const fenceMatch = line.replace(/^\s+/, '').startsWith('```');
    if (fenceMatch) {
      flushParagraph(paragraph, segments);
      const language = line.replace(/^\s+/, '').substring(3).replace(/\s+$/, '');
      const code: string[] = [];
      index += 1;
      while (index < lines.length && !lines[index].replace(/^\s+/, '').startsWith('```')) {
        code.push(lines[index]);
        index += 1;
      }
      index += 1;
      segments.push(segment(SegmentKind.CODE, 0, language.toLowerCase(), code.join('\n')));
      continue;
    }
    const level = headingLevelOf(line.replace(/^\s+/, '').replace(/^\s{0,3}/, ''));
    if (level > 0) {
      flushParagraph(paragraph, segments);
      segments.push(segment(SegmentKind.HEADING, level, '', line.replace(/^\s+/, '').substring(level + 1)));
      index += 1;
      continue;
    }
    // Table: a header row followed by a separator row.
    if (line.indexOf('|') >= 0 && index + 1 < lines.length && isTableSeparator(lines[index + 1])) {
      flushParagraph(paragraph, segments);
      const rows: string[][] = [splitTableRow(line)];
      index += 2;
      while (index < lines.length && lines[index].indexOf('|') >= 0 &&
        lines[index].replace(/\s/g, '').length > 0) {
        rows.push(splitTableRow(lines[index]));
        index += 1;
      }
      const table = segment(SegmentKind.TABLE, 0, '', '');
      table.rows = rows;
      segments.push(table);
      continue;
    }
    if (isRuleLine(line)) {
      flushParagraph(paragraph, segments);
      segments.push(segment(SegmentKind.RULE, 0, '', ''));
      index += 1;
      continue;
    }
    const trimmedLine = line.replace(/^\s+/, '');
    if (trimmedLine.startsWith('> ')) {
      flushParagraph(paragraph, segments);
      segments.push(segment(SegmentKind.QUOTE, 0, '', trimmedLine.substring(2)));
      index += 1;
      continue;
    }
    const marker = listMarkerLength(line);
    if (marker > 0) {
      flushParagraph(paragraph, segments);
      segments.push(segment(SegmentKind.LIST, 0, '', trimmedLine.substring(marker)));
      index += 1;
      continue;
    }
    if (line.replace(/\s/g, '').length === 0) {
      // A blank line always ends the current paragraph.
      flushParagraph(paragraph, segments);
      index += 1;
      continue;
    }
    paragraph.push(line);
    index += 1;
  }
  flushParagraph(paragraph, segments);
  return segments;
}

/** Short single-line preview of a message body (lists / notifications). */
export function previewOf(text: string, limit: number): string {
  const flat = text.replace(/\s+/g, ' ').replace(/[`*#>]/g, '').replace(/^\s+|\s+$/g, '');
  if (flat.length <= limit) {
    return flat;
  }
  return `${flat.substring(0, limit)}…`;
}
