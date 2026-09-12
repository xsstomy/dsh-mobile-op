/**
 * Plan-mode projection + command gating (pure logic, unit tested).
 *
 * The host registers a `plan` session projection whose wire view is
 * `{ active, pending }`. The client never keeps its own plan state: it renders
 * exactly this projection, and the effective target uses the same fold as the
 * official Web chip (`pending ? !active : active`).
 *
 * The toggle itself runs the plugin's `/plan-toggle` command, not the official
 * `/plan`: the plugin's review pipeline gates on its own in-memory mode, which
 * only `/plan-toggle` writes. When the plugin is absent the caller falls back to
 * the official `/plan` / `/plan off`.
 */
import { CommandGroupRow } from '../protocol/Settings';

export interface PlanModeRow {
  active: boolean;
  pending: boolean;
}

/** `projections.values` of a `sessions` / `history` frame, when present. */
function projectionValues(projections: Object | undefined): Record<string, Object> | undefined {
  if (projections === undefined || projections === null) {
    return undefined;
  }
  const values = (projections as Record<string, Object>)['values'];
  if (values === undefined || values === null || typeof values !== 'object' || Array.isArray(values)) {
    return undefined;
  }
  return values as Record<string, Object>;
}

/**
 * The `plan` projection cell. Returns null when the host does not publish it
 * (the list projection hints can omit a cell), so the UI hides the control
 * instead of guessing a state.
 */
export function planModeOf(projections: Object | undefined): PlanModeRow | null {
  const values = projectionValues(projections);
  if (values === undefined) {
    return null;
  }
  const plan = values['plan'];
  if (plan === undefined || plan === null || typeof plan !== 'object' || Array.isArray(plan)) {
    return null;
  }
  const record = plan as Record<string, Object>;
  const active = record['active'];
  const pending = record['pending'];
  if (typeof active !== 'boolean' || typeof pending !== 'boolean') {
    return null;
  }
  return { active, pending };
}

/** Effective target, mirroring the official chip: `pending ? !active : active`. */
export function planTarget(plan: PlanModeRow | null): boolean {
  if (plan === null) {
    return false;
  }
  return plan.pending ? !plan.active : plan.active;
}

/** True when the session's host command catalog contains `name`. */
export function hasHostCommand(groups: CommandGroupRow[], name: string): boolean {
  for (const group of groups) {
    for (const item of group.items) {
      if (item.name === name && item.source === 'host') {
        return true;
      }
    }
  }
  return false;
}

/**
 * Which command the Plan control should run: the plugin's `plan-toggle` when
 * installed, else the official `plan`. '' means the host offers neither.
 */
export function planToggleCommand(groups: CommandGroupRow[]): string {
  if (hasHostCommand(groups, 'plan-toggle')) {
    return 'plan-toggle';
  }
  return hasHostCommand(groups, 'plan') ? 'plan' : '';
}
