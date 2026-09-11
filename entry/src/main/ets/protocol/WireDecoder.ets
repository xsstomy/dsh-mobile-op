/**
 * Wire decoding helpers. Decoding is intentionally permissive: an unknown `kind`
 * or an extra field must never crash the client, it only loses feature
 * affordances (gated by `hello.capabilities`).
 */
import { WireFrame, WireSessionEvent, WireWorkspace, WireSessionSummary, WireQueueItem } from './Types';

export function decodeFrame(text: string): WireFrame | null {
  let value: Object;
  try {
    value = JSON.parse(text) as Object;
  } catch (error) {
    void error;
    return null;
  }
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    return null;
  }
  const frame = value as WireFrame;
  if (typeof frame.kind !== 'string' || frame.kind.length === 0) {
    return null;
  }
  return frame;
}

export function decodeFrameArray(text: string): WireFrame[] {
  let value: Object;
  try {
    value = JSON.parse(text) as Object;
  } catch (error) {
    void error;
    return [];
  }
  if (!Array.isArray(value)) {
    return [];
  }
  const result: WireFrame[] = [];
  const list = value as Object[];
  for (let index = 0; index < list.length; index += 1) {
    const item = list[index];
    if (item !== null && typeof item === 'object' && !Array.isArray(item)) {
      const frame = item as WireFrame;
      if (typeof frame.kind === 'string' && frame.kind.length > 0) {
        result.push(frame);
      }
    }
  }
  return result;
}

export function asWorkspaces(frame: WireFrame): WireWorkspace[] {
  // The host `workspace/list` payload arrives as `items`; keep `workspaces`
  // accepted for forward compatibility.
  const value = Array.isArray(frame.items) ? frame.items : frame.workspaces;
  if (!Array.isArray(value)) {
    return [];
  }
  const result: WireWorkspace[] = [];
  for (const item of value) {
    if (item !== null && typeof item === 'object' && !Array.isArray(item)) {
      result.push(item as WireWorkspace);
    }
  }
  return result;
}

export function asSessionSummaries(frame: WireFrame): WireSessionSummary[] {
  const value = frame.items;
  if (!Array.isArray(value)) {
    return [];
  }
  const result: WireSessionSummary[] = [];
  for (let index = 0; index < value.length; index += 1) {
    const item = value[index];
    if (item !== null && typeof item === 'object' && !Array.isArray(item)) {
      result.push(item as WireSessionSummary);
    }
  }
  return result;
}

export function asSessionEvents(frame: WireFrame): WireSessionEvent[] {
  return Array.isArray(frame.events) ? frame.events : [];
}

export function asQueueItems(frame: WireFrame): WireQueueItem[] {
  if (!Array.isArray(frame.items)) {
    return [];
  }
  const result: WireQueueItem[] = [];
  for (const item of frame.items) {
    if (item !== null && typeof item === 'object' && !Array.isArray(item)) {
      result.push(item as WireQueueItem);
    }
  }
  return result;
}

/** Capability gate: only use a request when the connected gateway advertised it. */
export function supportsCapability(capabilities: string[], capability: string): boolean {
  return capabilities.indexOf(capability) >= 0;
}
