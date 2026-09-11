/**
 * Test helpers. ArkTS forbids anonymous object literals, so shared test data is
 * built from declared classes or from the real wire decoder.
 */
import { WireFrame, WireSessionEvent } from '../main/ets/protocol/Types';
import { decodeFrame } from '../main/ets/protocol/WireDecoder';

export class TestEvent implements WireSessionEvent {
  type: string;
  seq: number;
  time: number;
  data: Object;

  constructor(seq: number, type: string, data: Object) {
    this.seq = seq;
    this.type = type;
    this.time = seq;
    this.data = data;
  }
}

class TextData {
  text: string;

  constructor(text: string) {
    this.text = text;
  }
}

class SourceData {
  kind: string;

  constructor(kind: string) {
    this.kind = kind;
  }
}

class UserMessageData {
  text: string;
  source: SourceData;

  constructor(text: string, sourceKind: string) {
    this.text = text;
    this.source = new SourceData(sourceKind);
  }
}

class TitleData {
  title: string;

  constructor(title: string) {
    this.title = title;
  }
}

export function emptyEvent(seq: number, type: string): WireSessionEvent {
  return new TestEvent(seq, type, new TextData(''));
}

export function userEvent(seq: number, text: string, source: string): WireSessionEvent {
  return new TestEvent(seq, 'user/message', new UserMessageData(text, source));
}

export function titleEvent(seq: number, title: string): WireSessionEvent {
  return new TestEvent(seq, 'session/title', new TitleData(title));
}

/**
 * A session event with an explicit `time` (the real gateway times events with the
 * epoch ms when they happened, not with their `seq`).
 */
export class TimedEvent implements WireSessionEvent {
  type: string;
  seq: number;
  time: number;
  data: Object;

  constructor(seq: number, type: string, data: Object, time: number) {
    this.seq = seq;
    this.type = type;
    this.time = time;
    this.data = data;
  }
}

class AssistantUsage {
  inputTokens: number;
  outputTokens: number;

  constructor(inputTokens: number, outputTokens: number) {
    this.inputTokens = inputTokens;
    this.outputTokens = outputTokens;
  }
}

class RequestedToolCall {
  callId: string;
  name: string;

  constructor(callId: string, name: string) {
    this.callId = callId;
    this.name = name;
  }
}

class AssistantMessageData {
  turn: number;
  step: number;
  text: string;
  usage: AssistantUsage;
  toolCalls: RequestedToolCall[];

  constructor(turn: number, step: number, text: string, inputTokens: number, outputTokens: number,
    withToolCall: boolean) {
    this.turn = turn;
    this.step = step;
    this.text = text;
    this.usage = new AssistantUsage(inputTokens, outputTokens);
    // `call-1` matches `EVENT_TOOL_CALL` in the fixtures.
    this.toolCalls = withToolCall ? [new RequestedToolCall('call-1', 'bash')] : [];
  }
}

class TurnData {
  turn: number;

  constructor(turn: number) {
    this.turn = turn;
  }
}

class ToolResultData {
  callId: string;
  isError: boolean;
  preview: string;

  constructor(callId: string, preview: string) {
    this.callId = callId;
    this.isError = false;
    this.preview = preview;
  }
}

/** A `tool/result` event carrying the given clock (see `EVENT_TOOL_RESULT`). */
export function toolResultAt(seq: number, callId: string, time: number): WireSessionEvent {
  return new TimedEvent(seq, 'tool/result', new ToolResultData(callId, 'ok'), time);
}

export function userEventAt(seq: number, text: string, time: number): WireSessionEvent {
  return new TimedEvent(seq, 'user/message', new UserMessageData(text, 'user'), time);
}

export function assistantEventAt(seq: number, turn: number, step: number, time: number, inputTokens: number,
  outputTokens: number, withToolCall: boolean = false): WireSessionEvent {
  return new TimedEvent(seq, 'assistant/message',
    new AssistantMessageData(turn, step, `answer ${step}`, inputTokens, outputTokens, withToolCall), time);
}

export function turnEndEventAt(seq: number, turn: number, time: number): WireSessionEvent {
  return new TimedEvent(seq, 'turn/end', new TurnData(turn), time);
}

/**
 * Decode a captured/synthetic event frame and force its seq, so a replay test is
 * independent of the seq numbers baked into the fixtures.
 */
export function eventAtSeq(raw: string, seq: number): WireSessionEvent {
  const frame = decodeFrame(raw);
  if (frame === null || frame.event === undefined) {
    throw new Error('fixture is not an event frame');
  }
  return new TestEvent(seq, frame.event.type ?? '', frame.event);
}

/**
 * Convert a live `{kind:'event', seq, time, event}` frame into the session-event
 * shape the trajectory/projection layers consume.
 */
export function liveEvent(raw: string): WireSessionEvent {
  const frame = decodeFrame(raw);
  if (frame === null || frame.event === undefined) {
    throw new Error('fixture is not an event frame');
  }
  return new TestEvent(typeof frame.seq === 'number' ? frame.seq : 0,
    frame.event.type ?? '', frame.event);
}

/** Parse a raw history payload (`{type, seq, time, data}`) into a session event. */
export function rawEvent(raw: string): WireSessionEvent {
  return JSON.parse(raw) as WireSessionEvent;
}

/** Build a WireFrame through the real decoder so the wire contract stays honest. */
export function frameOf(kind: string): WireFrame {
  const decoded = decodeFrame(`{"kind":"${kind}"}`);
  if (decoded === null) {
    throw new Error(`cannot build frame for kind ${kind}`);
  }
  return decoded;
}
