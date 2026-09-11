/**
 * Projection maths for the run-stats bar (pure, unit tested).
 *
 * Real frames (measured 2026-09-10) do NOT wrap token totals:
 *   tokenUsage     = { uncachedInputTokens, outputTokens, cacheReadTokens, cacheWriteTokens }
 *   contextPressure = { pressureTokens, projectedTokens, contextWindow }
 * The documented `totals` wrapper is still accepted because PROTOCOL.md shows it.
 */
import { WireContextPressure, WireTokenTotals, WireTokenUsage } from '../protocol/Types';

export interface TokenTotalsView {
  inputTokens: number;
  outputTokens: number;
  cacheReadTokens: number;
  cacheWriteTokens: number;
}

export function readTokenTotals(usage: WireTokenUsage | undefined): TokenTotalsView {
  if (usage === undefined) {
    return { inputTokens: 0, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0 };
  }
  const totals: WireTokenTotals | undefined = usage.totals;
  const input = totals !== undefined ? (totals.inputTokens ?? 0) : (usage.uncachedInputTokens ?? 0);
  const output = totals !== undefined ? (totals.outputTokens ?? 0) : (usage.outputTokens ?? 0);
  const cacheRead = totals !== undefined ? (totals.cacheReadTokens ?? 0) : (usage.cacheReadTokens ?? 0);
  const cacheWrite = totals !== undefined ? (totals.cacheWriteTokens ?? 0) : (usage.cacheWriteTokens ?? 0);
  return { inputTokens: input, outputTokens: output, cacheReadTokens: cacheRead, cacheWriteTokens: cacheWrite };
}

/**
 * Cache hit share in percent, or `-1` when the host reported no usage yet.
 * Same denominator as upstream `SessionStatsFormatter.cacheHitRate`:
 * cacheRead / (input + output + cacheRead + cacheWrite), clamped to 0..100.
 */
export function cacheHitPercent(totals: TokenTotalsView): number {
  const total = totals.inputTokens + totals.outputTokens + totals.cacheReadTokens + totals.cacheWriteTokens;
  if (total <= 0) {
    return -1;
  }
  const rate = totals.cacheReadTokens / total;
  if (rate <= 0) {
    return 0;
  }
  return rate >= 1 ? 100 : Math.round(rate * 100);
}

/** Context pressure in percent; prefers the projected surface over pressure. */
export function contextUsedPercent(pressure: WireContextPressure | undefined): number {
  if (pressure === undefined) {
    return 0;
  }
  const window = pressure.contextWindow ?? 0;
  if (window <= 0) {
    return 0;
  }
  const used = pressure.projectedTokens ?? (pressure.surfaceTokens ?? (pressure.pressureTokens ?? 0));
  if (used <= 0) {
    return 0;
  }
  return Math.min(100, Math.round((used / window) * 100));
}

/** Average time to first token, in milliseconds. */
export function averageTtftMs(ttftMs: number, ttftSteps: number): number {
  if (ttftSteps <= 0) {
    return 0;
  }
  return ttftMs / ttftSteps;
}

/**
 * Wait before the next throttled `session-stats` refresh while a turn runs
 * (0 = refresh now). PROTOCOL.md 6 only pushes `todos`/`goal`, so a live bar
 * needs polling - but one host fold per streamed event would be far too much.
 */
export function statsRefreshDelay(elapsedMs: number, minIntervalMs: number): number {
  if (elapsedMs >= minIntervalMs) {
    return 0;
  }
  return minIntervalMs - elapsedMs;
}

/** Decode throughput in tokens per second. */
export function decodeTokensPerSecond(decodeTokens: number, decodeMs: number): number {
  if (decodeMs <= 0) {
    return 0;
  }
  return decodeTokens / (decodeMs / 1000);
}
