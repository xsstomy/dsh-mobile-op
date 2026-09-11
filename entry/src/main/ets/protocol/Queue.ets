/**
 * Queued-message helpers (pure logic, unit tested).
 *
 * `session-queues` / `session-queue` items carry the host message shape:
 *   {id, placement: 'queued'|'steering'|'context', rpcId?, message:{id, content:[{type,text}]}}
 * Editing/removing/steering uses `queue-update` with the item id.
 */
import { WireQueueItem } from './Types';

export interface QueueRow {
  itemId: string;
  placement: string;
  text: string;
  images: number;
}

export function queueTextOf(item: WireQueueItem): string {
  const message = item.message;
  if (message === undefined || message === null) {
    return '';
  }
  const content = (message as Record<string, Object>)['content'];
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

export function queueImageCount(item: WireQueueItem): number {
  const message = item.message;
  if (message === undefined || message === null) {
    return 0;
  }
  const content = (message as Record<string, Object>)['content'];
  if (!Array.isArray(content)) {
    return 0;
  }
  let images = 0;
  for (const part of content as Object[]) {
    if (part === null || typeof part !== 'object') {
      continue;
    }
    if ((part as Record<string, Object>)['type'] === 'image') {
      images += 1;
    }
  }
  return images;
}

export function toQueueRows(items: WireQueueItem[]): QueueRow[] {
  const rows: QueueRow[] = [];
  for (const item of items) {
    rows.push({
      itemId: item.id ?? '',
      placement: item.placement !== undefined && item.placement.length > 0 ? item.placement : 'queued',
      text: queueTextOf(item),
      images: queueImageCount(item)
    });
  }
  return rows;
}

export function placementLabel(placement: string): string {
  switch (placement) {
    case 'queued':
      return '下一回合';
    case 'steering':
      return '插入当前回合';
    case 'context':
      return '系统上下文';
    default:
      return placement;
  }
}

/** `steer` only applies to a queued item while the session is running. */
export function canSteer(row: QueueRow, sessionRunning: boolean): boolean {
  return row.placement === 'queued' && sessionRunning;
}
