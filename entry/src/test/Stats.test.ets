import { describe, expect, it } from '@ohos/hypium';
import {
  averageTtftMs, cacheHitPercent, contextUsedPercent, decodeTokensPerSecond, readTokenTotals, statsRefreshDelay
} from '../main/ets/sync/Stats';
import { WireContextPressure, WireTokenUsage } from '../main/ets/protocol/Types';

export default function statsTest(): void {
  describe('stats', () => {
    it('reads the flat token fields sent by session-stats', 0, () => {
      const usage: WireTokenUsage = {
        uncachedInputTokens: 138312, outputTokens: 40551, cacheReadTokens: 2704512, cacheWriteTokens: 0
      };
      const totals = readTokenTotals(usage);
      expect(totals.inputTokens).assertEqual(138312);
      expect(totals.outputTokens).assertEqual(40551);
      expect(totals.cacheReadTokens).assertEqual(2704512);
    });

    it('still accepts the documented totals wrapper', 0, () => {
      const usage: WireTokenUsage = {
        totals: { inputTokens: 10, outputTokens: 5, cacheReadTokens: 1 }
      };
      const totals = readTokenTotals(usage);
      expect(totals.inputTokens).assertEqual(10);
      expect(totals.outputTokens).assertEqual(5);
      expect(totals.cacheReadTokens).assertEqual(1);
    });

    it('returns zeros for a missing usage block', 0, () => {
      const totals = readTokenTotals(undefined);
      expect(totals.inputTokens).assertEqual(0);
      expect(totals.outputTokens).assertEqual(0);
      expect(totals.cacheReadTokens).assertEqual(0);
    });

    it('computes context usage from projectedTokens', 0, () => {
      const pressure: WireContextPressure = { pressureTokens: 92060, projectedTokens: 92069, contextWindow: 262144 };
      expect(contextUsedPercent(pressure)).assertEqual(35);
    });

    it('falls back to pressureTokens and clamps to 100', 0, () => {
      const pressure: WireContextPressure = { pressureTokens: 200, contextWindow: 100 };
      expect(contextUsedPercent(pressure)).assertEqual(100);
      expect(contextUsedPercent(undefined)).assertEqual(0);
      expect(contextUsedPercent({ contextWindow: 0 })).assertEqual(0);
    });

    it('computes ttft and decode rate safely', 0, () => {
      expect(Math.round(averageTtftMs(102970, 50))).assertEqual(2059);
      expect(averageTtftMs(102970, 0)).assertEqual(0);
      expect(Math.round(decodeTokensPerSecond(40551, 166750))).assertEqual(243);
      expect(decodeTokensPerSecond(10, 0)).assertEqual(0);
    });

    it('reads cache writes and computes the cache hit share', 0, () => {
      const usage: WireTokenUsage = {
        uncachedInputTokens: 100, outputTokens: 50, cacheReadTokens: 850, cacheWriteTokens: 0
      };
      const totals = readTokenTotals(usage);
      expect(totals.cacheWriteTokens).assertEqual(0);
      expect(cacheHitPercent(totals)).assertEqual(85);
    });

    it('throttles live stats refreshes to one per window', 0, () => {
      expect(statsRefreshDelay(0, 3000)).assertEqual(3000);
      expect(statsRefreshDelay(1200, 3000)).assertEqual(1800);
      expect(statsRefreshDelay(3000, 3000)).assertEqual(0);
      expect(statsRefreshDelay(9000, 3000)).assertEqual(0);
    });

    it('reports no cache hit share until the host sends usage', 0, () => {
      expect(cacheHitPercent(readTokenTotals(undefined))).assertEqual(-1);
      const cold: WireTokenUsage = { uncachedInputTokens: 10, outputTokens: 5, cacheReadTokens: 0 };
      expect(cacheHitPercent(readTokenTotals(cold))).assertEqual(0);
      const cached: WireTokenUsage = { cacheReadTokens: 7, cacheWriteTokens: 3 };
      expect(cacheHitPercent(readTokenTotals(cached))).assertEqual(70);
    });
  });
}
