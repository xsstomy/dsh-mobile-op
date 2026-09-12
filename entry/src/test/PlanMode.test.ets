import { describe, expect, it } from '@ohos/hypium';
import { CommandGroupRow, CommandItemRow } from '../main/ets/protocol/Settings';
import { PlanModeRow, hasHostCommand, planCommandNotice, planIntentRow, planModeOf, planTarget, planToggleCommand } from '../main/ets/sync/PlanMode';

function projected(plan: Object): Object {
  return { asOfSeq: 4, values: { plan } };
}

function groupsOf(names: string[], source: string): CommandGroupRow[] {
  const items: CommandItemRow[] = [];
  for (const name of names) {
    items.push({
      id: 'command:' + name,
      name,
      description: '',
      source,
      kind: 'immediate',
      submitRequest: 'command-execute',
      submitText: '/' + name,
      insertText: '',
      displayHint: '',
      images: false,
      modelInvocable: true
    });
  }
  return [{ id: 'commands', title: '命令', items }];
}

export default function planModeTest(): void {
  describe('planMode', () => {
    it('reads the plan projection cell', 0, () => {
      const row = planModeOf(projected({ active: true, pending: false }));
      expect(row !== null).assertTrue();
      expect(row?.active).assertTrue();
      expect(row?.pending).assertFalse();
    });

    it('returns null when the cell is missing or malformed', 0, () => {
      expect(planModeOf(undefined) === null).assertTrue();
      expect(planModeOf({ asOfSeq: 1, values: {} }) === null).assertTrue();
      expect(planModeOf(projected({ active: true })) === null).assertTrue();
      expect(planModeOf(projected({ active: 'yes', pending: false })) === null).assertTrue();
      expect(planModeOf(projected(null)) === null).assertTrue();
    });

    it('folds pending over active like the official chip', 0, () => {
      expect(planTarget({ active: true, pending: false })).assertTrue();
      expect(planTarget({ active: false, pending: false })).assertFalse();
      expect(planTarget({ active: false, pending: true })).assertTrue();
      expect(planTarget({ active: true, pending: true })).assertFalse();
      expect(planTarget(null)).assertFalse();
    });

    it('derives the tap-time intent from the projection', 0, () => {
      // `planTarget` flips: a settled closed session targets closed again until
      // the host publishes, so the intent keeps `active` equal to the fold.
      const settledClosed = planIntentRow({ active: false, pending: false });
      expect(settledClosed !== null).assertTrue();
      if (settledClosed !== null) {
        expect(settledClosed.active).assertFalse();
        expect(settledClosed.pending).assertTrue();
      }
      const settledOpen = planIntentRow({ active: true, pending: false });
      expect(settledOpen !== null).assertTrue();
      if (settledOpen !== null) {
        expect(settledOpen.active).assertTrue();
        expect(settledOpen.pending).assertTrue();
      }
      // A projection that is already in flight folds the same way.
      const inFlightOpen = planIntentRow({ active: false, pending: true });
      if (inFlightOpen !== null) {
        expect(inFlightOpen.active).assertTrue();
        expect(inFlightOpen.pending).assertTrue();
      }
      const inFlightClosed = planIntentRow({ active: true, pending: true });
      if (inFlightClosed !== null) {
        expect(inFlightClosed.active).assertFalse();
        expect(inFlightClosed.pending).assertTrue();
      }
      // No projection published: never guess a state the chip cannot render.
      expect(planIntentRow(null) === null).assertTrue();
    });

    it('shows the Plan control only when the plugin is installed', 0, () => {
      expect(planToggleCommand(groupsOf(['plan-toggle', 'plan-review'], 'host'))).assertEqual('plan-toggle');
      expect(planToggleCommand(groupsOf(['plan'], 'host'))).assertEqual('');
      expect(planToggleCommand(groupsOf(['plan-toggle'], 'client'))).assertEqual('');
      expect(planToggleCommand([])).assertEqual('');
    });

    it('gates on host-sourced commands only', 0, () => {
      expect(hasHostCommand(groupsOf(['plan-review'], 'host'), 'plan-review')).assertTrue();
      expect(hasHostCommand(groupsOf(['plan-review'], 'client'), 'plan-review')).assertFalse();
      expect(hasHostCommand(groupsOf(['plan'], 'host'), 'plan-review')).assertFalse();
    });

    it('rewrites the plan result for the phone', 0, () => {
      const open = planCommandNotice('plan-toggle', 'success',
        'plan 模式已开启（committed）；沙箱已切只读（预设 read-only）。先聊清楚需求，然后按 Alt+2 复核并执行；再按 Alt+1 退出。');
      expect(open.indexOf('Alt+')).assertEqual(-1);
      expect(open.indexOf('Plan 关闭') >= 0).assertTrue();
      const close = planCommandNotice('plan-toggle', 'success', 'plan 模式已关闭（committed），流水线状态已清空。');
      expect(close.indexOf('写权限已还原') >= 0).assertTrue();
      const review = planCommandNotice('plan-review', 'success', '复核完成：2 条发现 → 已归档 docs/plans/x.md → 执行轮已启动。');
      expect(review.indexOf('复核完成') >= 0).assertTrue();
      expect(planCommandNotice('compact', 'success', '压缩完成')).assertEqual('压缩完成');
      // The official /plan can run with no Plan chip on screen, so it never
      // points at the hidden controls.
      const official = planCommandNotice('plan', 'success', 'Plan mode on. Use /plan off to leave.');
      expect(official.indexOf('用下方的 Plan')).assertEqual(-1);
    });
  });
}
