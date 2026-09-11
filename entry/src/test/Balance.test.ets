import { describe, expect, it } from '@ohos/hypium';
import { formatBalance, isOfficialDeepSeekRoute, parseBalanceSnapshot } from '../main/ets/protocol/Balance';
import { ModelGroupRow } from '../main/ets/protocol/Settings';

const GROUPS: ModelGroupRow[] = [
  { id: 'deepseek-official', name: 'DeepSeek', models: [] },
  { id: 'opencode-go-live', name: 'opencode-go-live', models: [] }
];

export default function balanceTest(): void {
  describe('deepseek balance', () => {
    it('parses the official balance body', 0, () => {
      const body = '{"is_available":true,"balance_infos":[{"currency":"CNY",' +
        '"total_balance":"110.00","granted_balance":"10.00","topped_up_balance":"100.00"}]}';
      const snapshot = parseBalanceSnapshot(body);
      expect(snapshot === null).assertFalse();
      if (snapshot !== null) {
        expect(snapshot.isAvailable).assertTrue();
        expect(snapshot.infos.length).assertEqual(1);
        expect(snapshot.infos[0].totalBalance).assertEqual('110.00');
        expect(formatBalance(snapshot)).assertEqual('¥110.00');
      }
    });

    it('formats the USD entry too', 0, () => {
      const body = '{"is_available":true,"balance_infos":[{"currency":"USD","total_balance":"4.20"}]}';
      expect(formatBalance(parseBalanceSnapshot(body))).assertEqual('$4.20');
    });

    it('rejects a non-JSON / non-object body', 0, () => {
      expect(parseBalanceSnapshot('<html>401</html>')).assertNull();
      expect(parseBalanceSnapshot('[1,2,3]')).assertNull();
      expect(formatBalance(null)).assertEqual('');
    });

    it('ignores an unavailable or empty balance', 0, () => {
      expect(formatBalance(parseBalanceSnapshot('{"is_available":false,"balance_infos":[]}'))).assertEqual('');
      expect(formatBalance(parseBalanceSnapshot('{"is_available":true,"balance_infos":[]}'))).assertEqual('');
    });

    it('gates on the official DeepSeek route only', 0, () => {
      expect(isOfficialDeepSeekRoute('deepseek-official', GROUPS)).assertTrue();
      expect(isOfficialDeepSeekRoute('deepseek', GROUPS)).assertTrue();
      expect(isOfficialDeepSeekRoute('opencode-go-live', GROUPS)).assertFalse();
      expect(isOfficialDeepSeekRoute('opencode-go', GROUPS)).assertFalse();
    });
  });
}
