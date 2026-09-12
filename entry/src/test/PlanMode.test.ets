import { describe, expect, it } from '@ohos/hypium';
import { CommandGroupRow, CommandItemRow } from '../main/ets/protocol/Settings';
import { PlanModeRow, hasHostCommand, planModeOf, planTarget, planToggleCommand } from '../main/ets/sync/PlanMode';

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

    it('prefers the plugin toggle, else the official plan command', 0, () => {
      expect(planToggleCommand(groupsOf(['plan-toggle', 'plan-review'], 'host'))).assertEqual('plan-toggle');
      expect(planToggleCommand(groupsOf(['plan'], 'host'))).assertEqual('plan');
      expect(planToggleCommand(groupsOf(['plan-toggle'], 'client'))).assertEqual('');
      expect(planToggleCommand([])).assertEqual('');
    });

    it('gates on host-sourced commands only', 0, () => {
      expect(hasHostCommand(groupsOf(['plan-review'], 'host'), 'plan-review')).assertTrue();
      expect(hasHostCommand(groupsOf(['plan-review'], 'client'), 'plan-review')).assertFalse();
      expect(hasHostCommand(groupsOf(['plan'], 'host'), 'plan-review')).assertFalse();
    });
  });
}
