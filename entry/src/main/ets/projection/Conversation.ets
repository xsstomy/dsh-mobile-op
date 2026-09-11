/**
 * Conversation projection (pure logic, unit tested).
 *
 * Live events and history events go through the SAME reducer so a reconnect that
 * replays history cannot duplicate or reorder what the stream already rendered.
 */
import { WireEventPayload, WireSessionEvent, WireImageAttachment } from '../protocol/Types';
import { durationLabel } from '../common/Format';

export enum ConversationRole {
  USER = 'user',
  ASSISTANT = 'assistant',
  SYSTEM = 'system',
  TOOL = 'tool'
}

export interface ToolCallView {
  callId: string;
  name: string;
  arguments: string;
  result: string;
  isError: boolean;
  done: boolean;
  /** Event times (ms) used for the per-call duration label. */
  startedAt: number;
  endedAt: number;
}

export interface ConversationItem {
  key: string;
  role: ConversationRole;
  text: string;
  reasoning: string;
  streaming: boolean;
  time: number;
  images: WireImageAttachment[];
  toolCalls: ToolCallView[];
  /** Turn/step this bubble belongs to; 0 when the frame did not carry one. */
  turn: number;
  step: number;
  /** Turn timing (ms). Stamped by the turn's first visible event, refined by `turn/start`. */
  turnStartedAt: number;
  /** `turn/end` time (ms); 0 while the turn is still running. */
  turnEndedAt: number;
  /** Token usage reported for THIS step; `turnTokenTotals` sums a turn's steps. */
  stepInputTokens: number;
  stepOutputTokens: number;
}

/** Token totals accumulated for one step or turn. */
export interface TokenPairView {
  input: number;
  output: number;
}


/** Content-part helpers: raw history events nest text, live frames do not. */
function textOfContent(content: Object | undefined): string {
  if (!Array.isArray(content)) {
    return '';
  }
  let text = '';
  for (const part of content as Object[]) {
    if (part === null || typeof part !== 'object') {
      continue;
    }
    const record = part as Record<string, Object>;
    if (record['type'] === 'text' && typeof record['text'] === 'string') {
      text += record['text'] as string;
    }
  }
  return text;
}

/** `user/message` text: flattened live frame or raw `content[]`. */
function userTextOf(payload: WireEventPayload): string {
  if (typeof payload.text === 'string') {
    return payload.text;
  }
  return textOfContent(payload.content);
}

/** `assistant/message` text: flattened live frame or raw `message.content[]`. */
function assistantTextOf(payload: WireEventPayload): string {
  if (typeof payload.text === 'string') {
    return payload.text;
  }
  const message = payload.message;
  if (message === undefined || message === null) {
    return '';
  }
  return textOfContent((message as Record<string, Object>)['content']);
}

/** `source` is a bare string on live frames and `{kind}` on raw history events. */
function sourceKindOf(payload: WireEventPayload): string {
  const source = payload.source;
  if (typeof source === 'string') {
    return source;
  }
  if (source !== undefined && source !== null) {
    const kind = (source as Record<string, Object>)['kind'];
    return typeof kind === 'string' ? kind : '';
  }
  return '';
}

function readField(record: Record<string, Object>, keys: string[]): string {
  for (const key of keys) {
    const value = record[key];
    if (typeof value === 'string' && value.length > 0) {
      return value;
    }
  }
  return '';
}

/** Tool call normalisation: live frames pass objects, raw history passes a JSON string. */
interface ToolCallInfo {
  callId: string;
  name: string;
  argsText: string;
}

/** Tool result normalisation: live frames are flat, raw history nests content. */
interface ToolResultInfo {
  callId: string;
  text: string;
  isError: boolean;
}

function normalizeToolCall(payload: WireEventPayload): ToolCallInfo {
  const record = payload as Record<string, Object>;
  const callId = readField(record, ['callId', 'id', 'toolCallId']);
  const name = readField(record, ['name', 'toolName']);
  const args = record['arguments'] !== undefined ? record['arguments']
    : (record['input'] !== undefined ? record['input'] : record['args']);
  let argsText = '';
  if (typeof args === 'string') {
    argsText = args;
  } else if (args !== undefined && args !== null) {
    argsText = JSON.stringify(args);
  }
  return { callId: callId, name: name, argsText: argsText };
}

function joinTextParts(content: Object | undefined): string {
  if (!Array.isArray(content)) {
    return '';
  }
  let text = '';
  for (const part of content as Object[]) {
    if (part === null || typeof part !== 'object') {
      continue;
    }
    const record = part as Record<string, Object>;
    const nested = record['content'];
    if (Array.isArray(nested)) {
      text += joinTextParts(nested);
      continue;
    }
    const value = record['text'];
    if (typeof value === 'string') {
      text += value;
    }
  }
  return text;
}

function normalizeToolResult(payload: WireEventPayload): ToolResultInfo {
  const record = payload as Record<string, Object>;
  const flatCallId = readField(record, ['callId', 'id', 'toolCallId']);
  const message = payload.message;
  let callId = flatCallId;
  let text = typeof payload.preview === 'string' ? payload.preview : '';
  let isError = payload.isError === true;
  if (message !== undefined && message !== null) {
    const messageRecord = message as Record<string, Object>;
    const source = messageRecord['source'];
    if (callId.length === 0 && source !== undefined && source !== null) {
      callId = readField(source as Record<string, Object>, ['callId']);
    }
    const content = messageRecord['content'];
    if (Array.isArray(content) && (content as Object[]).length > 0) {
      const first = (content as Object[])[0] as Record<string, Object>;
      if (callId.length === 0) {
        callId = readField(first, ['toolCallId', 'callId']);
      }
      if (text.length === 0) {
        text = joinTextParts(first['content']);
      }
      if (first['isError'] === true) {
        isError = true;
      }
    }
  }
  return { callId: callId, text: text, isError: isError };
}

/** Tool calls: live frames carry `toolCalls[]`, raw history nests them in content. */
function toolCallsOf(payload: WireEventPayload): Record<string, Object>[] {
  const result: Record<string, Object>[] = [];
  const live = payload.toolCalls;
  if (Array.isArray(live)) {
    for (const item of live) {
      if (item !== null && typeof item === 'object') {
        result.push(item as Record<string, Object>);
      }
    }
  }
  if (result.length > 0) {
    return result;
  }
  const message = payload.message;
  if (message === undefined || message === null) {
    return result;
  }
  const content = (message as Record<string, Object>)['content'];
  if (!Array.isArray(content)) {
    return result;
  }
  for (const part of content as Object[]) {
    if (part === null || typeof part !== 'object') {
      continue;
    }
    const record = part as Record<string, Object>;
    const type = record['type'];
    if (type === 'tool-call' || type === 'tool_call') {
      result.push(record);
    }
  }
  return result;
}

/** ArkTS forbids `{}` literals, so an explicit empty argument object is used. */
class EmptyArguments {
}

function toolArguments(record: Record<string, Object>): Object {
  const direct = record['arguments'];
  if (direct !== undefined && direct !== null) {
    return direct;
  }
  const input = record['input'];
  if (input !== undefined && input !== null) {
    return input;
  }
  const args = record['args'];
  if (args !== undefined && args !== null) {
    return args;
  }
  return new EmptyArguments();
}

function emptyItem(key: string, role: ConversationRole, time: number): ConversationItem {
  return {
    key: key,
    role: role,
    text: '',
    reasoning: '',
    streaming: false,
    time: time,
    images: [],
    toolCalls: [],
    turn: 0,
    step: 0,
    turnStartedAt: 0,
    turnEndedAt: 0,
    stepInputTokens: 0,
    stepOutputTokens: 0
  };
}

function cloneItem(item: ConversationItem): ConversationItem {
  const toolCalls: ToolCallView[] = [];
  for (const call of item.toolCalls) {
    toolCalls.push({
      callId: call.callId,
      name: call.name,
      arguments: call.arguments,
      result: call.result,
      isError: call.isError,
      done: call.done,
      startedAt: call.startedAt,
      endedAt: call.endedAt
    });
  }
  const images: WireImageAttachment[] = [];
  for (const image of item.images) {
    images.push(image);
  }
  return {
    key: item.key,
    role: item.role,
    text: item.text,
    reasoning: item.reasoning,
    streaming: item.streaming,
    time: item.time,
    images: images,
    toolCalls: toolCalls,
    turn: item.turn,
    step: item.step,
    turnStartedAt: item.turnStartedAt,
    turnEndedAt: item.turnEndedAt,
    stepInputTokens: item.stepInputTokens,
    stepOutputTokens: item.stepOutputTokens
  };
}

export function cloneItems(items: ConversationItem[]): ConversationItem[] {
  const result: ConversationItem[] = [];
  for (const item of items) {
    result.push(cloneItem(item));
  }
  return result;
}

function findLastAssistant(items: ConversationItem[]): number {
  for (let index = items.length - 1; index >= 0; index -= 1) {
    if (items[index].role === ConversationRole.ASSISTANT) {
      return index;
    }
  }
  return -1;
}

function turnOf(payload: WireEventPayload): number {
  return typeof payload.turn === 'number' ? payload.turn : 0;
}

function stepOf(payload: WireEventPayload): number {
  return typeof payload.step === 'number' ? payload.step : 0;
}

function ensureAssistant(items: ConversationItem[], key: string, time: number, turn: number, step: number): number {
  const existing = findLastAssistant(items);
  if (existing >= 0) {
    const last = items[existing];
    if (last.key === key) {
      return existing;
    }
    const keyed = key.indexOf('-t') > 0;
    const lastKeyed = last.key.indexOf('-t') > 0;
    // A live delta that cannot name its step continues whatever is streaming…
    if (!keyed && last.streaming) {
      return existing;
    }
    // …and once the step is known, that streamed bubble adopts its identity so
    // the step's remaining events land here.
    if (keyed && !lastKeyed && last.streaming) {
      last.key = key;
      last.turn = turn;
      last.step = step;
      if (last.turnStartedAt === 0) {
        last.turnStartedAt = time;
      }
      return existing;
    }
  }
  const created = emptyItem(key, ConversationRole.ASSISTANT, time);
  created.turn = turn;
  created.step = step;
  // The turn's first visible event bounds its start even when `turn/start` was
  // never delivered (the captured live turn had no streaming chunks at all).
  created.turnStartedAt = time;
  items.push(created);
  return items.length - 1;
}

/**
 * Bubble identity for assistant output: one (turn, step) is one bubble. Keying by
 * `seq` splits a single step across two bubbles — the `assistant/message` that
 * announces a tool call closed the bubble, so the following `tool/call` opened a
 * second one and the tool card was rendered twice (and the step's answer text
 * ended up glued to the tool card instead of in its own reply).
 */
function assistantKeyOf(payload: WireEventPayload, seq: number): string {
  const turn = payload.turn;
  const step = payload.step;
  if (typeof turn === 'number' && typeof step === 'number') {
    return `a-t${turn}s${step}`;
  }
  return `a-${seq}`;
}

function applyToolCall(items: ConversationItem[], payload: WireEventPayload, time: number, seq: number): ConversationItem[] {
  const next = cloneItems(items);
  const index = ensureAssistant(next, assistantKeyOf(payload, seq), time, turnOf(payload), stepOf(payload));
  const item = next[index];
  item.streaming = true;
  const record = payload as Record<string, Object>;
  const callId = readField(record, ['callId', 'id', 'toolCallId']);
  const name = readField(record, ['name', 'toolName']);
  let found = false;
  for (const call of item.toolCalls) {
    if (call.callId === callId && callId.length > 0) {
      call.name = name.length > 0 ? name : call.name;
      call.arguments = JSON.stringify(toolArguments(record));
      found = true;
    }
  }
  if (!found) {
    item.toolCalls.push({
      callId: callId,
      name: name,
      arguments: JSON.stringify(payload.arguments ?? {}),
      result: '',
      isError: false,
      done: false,
      startedAt: time,
      endedAt: 0
    });
  } else if (time > 0) {
    // The call was first seen through `assistant/message`, which lists the
    // requested calls but carries no clock: stamp the start here. An unset start
    // makes the one-line summary report the epoch as a duration (measured:
    // `1 个工具 · 29818317m25s`).
    for (const call of item.toolCalls) {
      if (call.callId === callId && call.startedAt === 0) {
        call.startedAt = time;
      }
    }
  }
  return next;
}

function applyToolResult(items: ConversationItem[], payload: WireEventPayload, time: number): ConversationItem[] {
  const next = cloneItems(items);
  const result = normalizeToolResult(payload);
  if (result.callId.length === 0) {
    return next;
  }
  for (let index = next.length - 1; index >= 0; index -= 1) {
    const item = next[index];
    for (const call of item.toolCalls) {
      if (call.callId === result.callId) {
        if (result.text.length > 0) {
          call.result = result.text;
        }
        call.isError = result.isError;
        call.done = true;
        if (call.startedAt === 0 && time > 0) {
          // A result with no matching call event (trimmed live payload): keep the
          // span meaningful instead of measuring from the epoch.
          call.startedAt = time;
        }
        if (call.endedAt === 0) {
          // Event time first: a replayed turn must not measure its tools against
          // today's clock (it would report hours for calls that took 200 ms).
          call.endedAt = time > 0 ? time : Date.now();
        }
        return next;
      }
    }
  }
  return next;
}

function numberField(record: Record<string, Object>, key: string): number {
  const value = record[key];
  if (typeof value === 'number' && Number.isFinite(value) && value > 0) {
    return value;
  }
  return 0;
}

/**
 * Token usage has two documented shapes: the `{totals}` wrapper (PROTOCOL.md §5)
 * and the flat measured frame. Input tokens are `inputTokens` when present
 * (raw history), otherwise the sum of the flat input buckets — a cached read is
 * still a token the turn consumed.
 */
export function usageTotalsOf(usage: Object | undefined): TokenPairView {
  if (usage === undefined || usage === null) {
    return { input: 0, output: 0 };
  }
  const record = usage as Record<string, Object>;
  const totals = record['totals'];
  if (totals !== undefined && totals !== null && typeof totals === 'object') {
    const totalsRecord = totals as Record<string, Object>;
    return {
      input: numberField(totalsRecord, 'inputTokens'),
      output: numberField(totalsRecord, 'outputTokens')
    };
  }
  const directInput = numberField(record, 'inputTokens');
  const input = directInput > 0 ? directInput
    : numberField(record, 'uncachedInputTokens') + numberField(record, 'cacheReadTokens') +
      numberField(record, 'cacheWriteTokens');
  return { input: input, output: numberField(record, 'outputTokens') };
}

/**
 * Usage frames can trail the step they describe, so they attach to the matching
 * bubble when it exists and otherwise to the last assistant bubble — never to a
 * freshly created (empty) one.
 */
function applyUsage(items: ConversationItem[], payload: WireEventPayload, seq: number): ConversationItem[] {
  const totals = usageTotalsOf(payload.usage);
  if (totals.input <= 0 && totals.output <= 0) {
    return items;
  }
  const key = assistantKeyOf(payload, seq);
  let target = -1;
  for (let index = items.length - 1; index >= 0; index -= 1) {
    if (items[index].role === ConversationRole.ASSISTANT && items[index].key === key) {
      target = index;
      break;
    }
  }
  if (target < 0) {
    target = findLastAssistant(items);
  }
  if (target < 0) {
    return items;
  }
  const next = cloneItems(items);
  next[target].stepInputTokens += totals.input;
  next[target].stepOutputTokens += totals.output;
  return next;
}

function applyAssistantMessage(items: ConversationItem[], payload: WireEventPayload, time: number, seq: number): ConversationItem[] {
  const next = cloneItems(items);
  const index = ensureAssistant(next, assistantKeyOf(payload, seq), time, turnOf(payload), stepOf(payload));
  const item = next[index];
  const text = assistantTextOf(payload);
  if (text.length > 0) {
    item.text = text;
  }
  if (typeof payload.reasoning === 'string' && payload.reasoning.length > 0) {
    item.reasoning = payload.reasoning;
  }
  const usage = usageTotalsOf(payload.usage);
  item.stepInputTokens += usage.input;
  item.stepOutputTokens += usage.output;
  item.streaming = false;
  for (const record of toolCallsOf(payload)) {
    const callId = readField(record, ['callId', 'id', 'toolCallId']);
    const name = readField(record, ['name', 'toolName']);
    let found = false;
    for (const call of item.toolCalls) {
      if (call.callId === callId && callId.length > 0) {
        call.name = name.length > 0 ? name : call.name;
        found = true;
      }
    }
    if (!found && (callId.length > 0 || name.length > 0)) {
      item.toolCalls.push({
        callId: callId,
        name: name,
        arguments: JSON.stringify(toolArguments(record)),
        result: '',
        isError: false,
        done: false,
        // Live payloads already expose the call inside `assistant/message`, and
        // `tool/call` (which carries the clock) may never arrive separately.
        startedAt: time,
        endedAt: 0
      });
    }
  }
  return next;
}

/** Apply one wire event (live or replayed from history). */
export function applyEvent(items: ConversationItem[], seq: number, event: WireSessionEvent): ConversationItem[] {
  const type = event.type ?? '';
  const time = typeof event.time === 'number' ? event.time : 0;
  const data = event.data as WireEventPayload | undefined;
  if (data === undefined || data === null) {
    return items;
  }
  if (type === 'user/message') {
    const source = sourceKindOf(data);
    if (source !== '' && source !== 'user') {
      return items;
    }
    const next = cloneItems(items);
    const item = emptyItem(`u-${seq}`, ConversationRole.USER, time);
    item.text = userTextOf(data);
    if (Array.isArray(data.images)) {
      for (const image of data.images) {
        item.images.push(image);
      }
    }
    next.push(item);
    return next;
  }
  if (type === 'assistant/chunk') {
    const chunkType = data.chunkType ?? '';
    if (chunkType === 'usage') {
      return applyUsage(items, data, seq);
    }
    if (chunkType !== 'text-delta' && chunkType !== 'reasoning-delta') {
      return items;
    }
    const next = cloneItems(items);
    const index = ensureAssistant(next, assistantKeyOf(data, seq), time, turnOf(data), stepOf(data));
    const item = next[index];
    item.streaming = true;
    if (chunkType === 'text-delta') {
      item.text = `${item.text}${data.text ?? ''}`;
    } else {
      item.reasoning = `${item.reasoning}${data.text ?? ''}`;
    }
    return next;
  }
  if (type === 'assistant/message') {
    return applyAssistantMessage(items, data, time, seq);
  }
  if (type === 'tool/call') {
    return applyToolCall(items, data, time, seq);
  }
  if (type === 'tool/result') {
    return applyToolResult(items, data, time);
  }
  if (type === 'turn/start') {
    const turn = turnOf(data);
    if (turn <= 0) {
      return items;
    }
    const next = cloneItems(items);
    for (const item of next) {
      if (item.turn === turn && time > 0 && (item.turnStartedAt === 0 || time < item.turnStartedAt)) {
        item.turnStartedAt = time;
      }
    }
    return next;
  }
  if (type === 'turn/end') {
    const turn = turnOf(data);
    const next = cloneItems(items);
    for (const item of next) {
      if (item.role !== ConversationRole.ASSISTANT) {
        continue;
      }
      // A bubble whose turn is unknown (delta without turn/step) belongs to the
      // ending turn, and a turn/end without `turn` closes everything. A LATER
      // turn/end only clears the streaming flag of the earlier bubbles (they are
      // certainly over) — it must never re-stamp their end time, or turn 1's
      // footer would inherit turn 2's clock (measured: 4m48s instead of 5.0s).
      const owned = turn === 0 || item.turn === 0 || turn === item.turn;
      if (item.turn > 0 && turn > 0 && item.turn > turn) {
        continue;
      }
      item.streaming = false;
      if (owned && time > 0 && (item.turnEndedAt === 0 || time < item.turnEndedAt)) {
        item.turnEndedAt = time;
      }
    }
    return next;
  }
  return items;
}

/** Rebuild the whole conversation from a history batch. */
export function projectFromEvents(events: WireSessionEvent[]): ConversationItem[] {
  let items: ConversationItem[] = [];
  for (const event of events) {
    const seq = typeof event.seq === 'number' ? event.seq : 0;
    items = applyEvent(items, seq, event);
  }
  return items;
}

// --------------------------------------------------------------- selectors

/** True when this assistant bubble is the LAST one of its turn (footer host). */
export function isTurnTail(items: ConversationItem[], index: number): boolean {
  if (index < 0 || index >= items.length) {
    return false;
  }
  const item = items[index];
  if (item.role !== ConversationRole.ASSISTANT || item.turn <= 0) {
    return false;
  }
  for (let next = index + 1; next < items.length; next += 1) {
    if (items[next].turn === item.turn) {
      return false;
    }
  }
  return true;
}

/** Token totals of a whole turn: the footer sums what every step reported. */
export function turnTokenTotals(items: ConversationItem[], turn: number): TokenPairView {
  let input = 0;
  let output = 0;
  if (turn > 0) {
    for (const item of items) {
      if (item.turn === turn) {
        input += item.stepInputTokens;
        output += item.stepOutputTokens;
      }
    }
  }
  return { input: input, output: output };
}

function anyStreaming(items: ConversationItem[]): boolean {
  for (const item of items) {
    if (item.role === ConversationRole.ASSISTANT && item.streaming) {
      return true;
    }
  }
  return false;
}

/**
 * 「深度求索中」 shows while the turn is running (or a bubble is still streaming)
 * and no answer text is currently being typed — then the streamed text itself is
 * the feedback and an extra indicator would sit below the answer being written.
 */
export interface TurnSpan {
  startedAt: number;
  endedAt: number;
}

/**
 * Wall-clock span of one turn: from the prompt that opened it to its `turn/end`.
 *
 * Each assistant bubble knows `turnStartedAt`/`turnEndedAt`, but a multi-step
 * turn creates one bubble per step and only the LAST one carries the footer, so
 * the tail bubble alone would report the last step's duration (measured: 0.0s for
 * a 5.0s turn). The span therefore starts at the earliest assistant event of the
 * turn and is widened to the user bubble above it — `user/message` carries no
 * `turn`, but it is always the turn's first visible item. Turns without a
 * preceding user bubble (mid-turn history page) fall back to the assistant
 * events.
 */
export function turnTimeSpan(items: ConversationItem[], turn: number): TurnSpan {
  if (turn <= 0) {
    return { startedAt: 0, endedAt: 0 };
  }
  let startedAt = 0;
  let endedAt = 0;
  let first = -1;
  for (let index = 0; index < items.length; index += 1) {
    const item = items[index];
    if (item.turn !== turn) {
      continue;
    }
    if (first < 0) {
      first = index;
    }
    if (item.turnStartedAt > 0 && (startedAt === 0 || item.turnStartedAt < startedAt)) {
      startedAt = item.turnStartedAt;
    }
    if (item.turnEndedAt > endedAt) {
      endedAt = item.turnEndedAt;
    }
  }
  if (first < 0) {
    return { startedAt: 0, endedAt: 0 };
  }
  for (let index = first - 1; index >= 0; index -= 1) {
    const item = items[index];
    if (item.role !== ConversationRole.USER) {
      continue;
    }
    if (item.time > 0 && (startedAt === 0 || item.time < startedAt)) {
      startedAt = item.time;
    }
    break;
  }
  return { startedAt: startedAt, endedAt: endedAt };
}

export function shouldShowThinking(items: ConversationItem[], turnActive: boolean): boolean {
  if (!turnActive && !anyStreaming(items)) {
    return false;
  }
  for (let index = items.length - 1; index >= 0; index -= 1) {
    const item = items[index];
    if (item.role !== ConversationRole.ASSISTANT) {
      continue;
    }
    return !(item.streaming && item.text.length > 0);
  }
  return true;
}

/**
 * List items the conversation page renders: [0] the history header, one per
 * message, the optional thinking indicator, the run pill, then one per pending
 * approval/question card. The page derives "am I at the bottom?" from the List's
 * visible index range, and that range counts these items — not just messages.
 */
export function conversationListItemCount(items: ConversationItem[], turnActive: boolean,
  pendingCards: number): number {
  return 1 + items.length + (shouldShowThinking(items, turnActive) ? 1 : 0) + 1 + pendingCards;
}

/**
 * One-line stand-in for the hidden tool cards: `3 个工具 · 12s`, `3 个工具 · 进行中`
 * or `3 个工具` when no timing was reported. Empty when the step used no tools.
 */
export function toolSummaryText(item: ConversationItem): string {
  const total = item.toolCalls.length;
  if (total === 0) {
    return '';
  }
  let durationMs = 0;
  let running = false;
  for (const call of item.toolCalls) {
    if (!call.done) {
      running = true;
    } else if (call.startedAt > 0 && call.endedAt > call.startedAt) {
      durationMs += call.endedAt - call.startedAt;
    }
  }
  const label = durationLabel(durationMs);
  if (running) {
    return `${total} 个工具 · 进行中`;
  }
  if (label.length === 0) {
    return `${total} 个工具`;
  }
  return `${total} 个工具 · ${label}`;
}
