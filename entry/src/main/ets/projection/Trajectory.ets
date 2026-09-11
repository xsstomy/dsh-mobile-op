/**
 * Trajectory projection (pure logic, unit tested): raw session events into a
 * timeline of inspectable rows (upstream: TrajectoryUi / TrajectoryDetailUi).
 */
import { WireSessionEvent } from '../protocol/Types';
import { previewOf } from '../common/Format';

export enum TrajectoryKind {
  TURN = 'turn',
  STEP = 'step',
  USER = 'user',
  ASSISTANT = 'assistant',
  REASONING = 'reasoning',
  TOOL = 'tool',
  TOOL_RESULT = 'tool-result',
  CONTEXT = 'context',
  META = 'meta',
  ERROR = 'error'
}

export interface TrajectoryRow {
  seq: number;
  time: number;
  kind: TrajectoryKind;
  /** Event type as sent on the wire. */
  type: string;
  turn: number;
  step: number;
  title: string;
  subtitle: string;
  /** Raw event payload for the detail sheet. */
  detail: string;
  isError: boolean;
}

function fieldOf(data: Object | undefined, key: string): string {
  if (data === undefined || data === null) {
    return '';
  }
  const value = (data as Record<string, Object>)[key];
  return typeof value === 'string' ? value : '';
}

/** `source` is a bare string on live frames and `{kind}` on raw history events. */
function sourceKindOf(data: Object | undefined): string {
  if (data === undefined || data === null) {
    return '';
  }
  const source = (data as Record<string, Object>)['source'];
  if (typeof source === 'string') {
    return source;
  }
  if (source !== undefined && source !== null) {
    const kind = (source as Record<string, Object>)['kind'];
    return typeof kind === 'string' ? kind : '';
  }
  return '';
}

function numberOf(data: Object | undefined, key: string): number {
  if (data === undefined || data === null) {
    return 0;
  }
  const value = (data as Record<string, Object>)[key];
  return typeof value === 'number' ? value : 0;
}

function joinContentText(content: Object | undefined): string {
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
      text += joinContentText(nested);
      continue;
    }
    const value = record['text'];
    if (typeof value === 'string') {
      text += value;
    }
  }
  return text;
}

/** Text shown for a message-ish event, tolerating both wire shapes. */
function bodyTextOf(data: Object | undefined): string {
  const flat = fieldOf(data, 'text');
  if (flat.length > 0) {
    return flat;
  }
  const content = data === undefined ? undefined : (data as Record<string, Object>)['content'];
  const fromContent = joinContentText(content);
  if (fromContent.length > 0) {
    return fromContent;
  }
  const message = data === undefined ? undefined : (data as Record<string, Object>)['message'];
  if (message !== undefined && message !== null) {
    return joinContentText((message as Record<string, Object>)['content']);
  }
  return '';
}

/** Build the timeline rows for one session event batch (already ordered by seq). */
export function buildTrajectory(events: WireSessionEvent[]): TrajectoryRow[] {
  const rows: TrajectoryRow[] = [];
  for (const event of events) {
    const type = event.type ?? '';
    const data = event.data;
    const seq = typeof event.seq === 'number' ? event.seq : 0;
    const time = typeof event.time === 'number' ? event.time : 0;
    const turn = numberOf(data, 'turn');
    const step = numberOf(data, 'step');
    let kind = TrajectoryKind.META;
    let title = type;
    let subtitle = '';
    let isError = false;
    if (type === 'turn/start') {
      kind = TrajectoryKind.TURN;
      title = `第 ${turn} 轮`;
      subtitle = '开始';
    } else if (type === 'turn/end') {
      kind = TrajectoryKind.TURN;
      title = `第 ${turn} 轮`;
      subtitle = '结束';
    } else if (type === 'step/start') {
      kind = TrajectoryKind.STEP;
      title = `步骤 ${step}`;
      subtitle = '开始';
    } else if (type === 'step/end') {
      kind = TrajectoryKind.STEP;
      title = `步骤 ${step}`;
      subtitle = '结束';
    } else if (type === 'user/message') {
      const source = sourceKindOf(data);
      kind = TrajectoryKind.USER;
      title = '用户消息';
      subtitle = previewOf(bodyTextOf(data), 80);
      if (source.length > 0 && source !== 'user') {
        title = `上下文注入 · ${source}`;
        kind = TrajectoryKind.CONTEXT;
      }
    } else if (type === 'assistant/message') {
      kind = TrajectoryKind.ASSISTANT;
      title = 'Agent 回复';
      subtitle = previewOf(bodyTextOf(data), 80);
    } else if (type === 'assistant/chunk') {
      kind = TrajectoryKind.REASONING;
      title = `流式分片 · ${fieldOf(data, 'chunkType')}`;
      subtitle = previewOf(fieldOf(data, 'text'), 60);
    } else if (type === 'tool/call') {
      kind = TrajectoryKind.TOOL;
      title = `工具调用 · ${fieldOf(data, 'name')}`;
      subtitle = previewOf(fieldOf(data, 'arguments'), 80);
    } else if (type === 'tool/result') {
      kind = TrajectoryKind.TOOL_RESULT;
      title = '工具结果';
      subtitle = previewOf(bodyTextOf(data).length > 0 ? bodyTextOf(data) : fieldOf(data, 'preview'), 80);
      isError = (data === undefined ? false : (data as Record<string, Object>)['isError'] === true);
    } else if (type === 'request/header' || type === 'request/context') {
      kind = TrajectoryKind.CONTEXT;
      title = type === 'request/header' ? '请求配置' : '请求上下文';
    } else if (type === 'session/title') {
      title = '会话标题';
      subtitle = fieldOf(data, 'title');
    } else if (type === 'agent/error' || type === 'session/error') {
      kind = TrajectoryKind.ERROR;
      title = '错误';
      subtitle = previewOf(fieldOf(data, 'message'), 80);
      isError = true;
    }
    rows.push({
      seq: seq,
      time: time,
      kind: kind,
      type: type,
      turn: turn,
      step: step,
      title: title,
      subtitle: subtitle,
      detail: JSON.stringify(data ?? {}),
      isError: isError
    });
  }
  return rows;
}

/** Duration of one turn, derived from turn/start and turn/end timestamps. */
export function turnDurations(rows: TrajectoryRow[]): Map<number, number> {
  const starts: Map<number, number> = new Map<number, number>();
  const durations: Map<number, number> = new Map<number, number>();
  for (const row of rows) {
    if (row.type === 'turn/start') {
      starts.set(row.turn, row.time);
    } else if (row.type === 'turn/end') {
      const start = starts.get(row.turn);
      if (start !== undefined && row.time >= start) {
        durations.set(row.turn, row.time - start);
      }
    }
  }
  return durations;
}

export function countByKind(rows: TrajectoryRow[], kind: TrajectoryKind): number {
  let total = 0;
  for (const row of rows) {
    if (row.kind === kind) {
      total += 1;
    }
  }
  return total;
}
