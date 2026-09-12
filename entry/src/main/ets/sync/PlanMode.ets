/**
 * Plan-mode projection + command gating (pure logic, unit tested).
 *
 * The host registers a `plan` session projection whose wire view is
 * `{ active, pending }`. The client never keeps its own plan state: it renders
 * exactly this projection, and the effective target uses the same fold as the
 * official Web chip (`pending ? !active : active`).
 *
 * The Plan control exists only when the dsh-plan-toggle plugin is installed:
 * the toggle runs its `/plan-toggle` command, and the plugin's review pipeline
 * gates on its own in-memory mode, which only that command writes. A host that
 * merely offers the official `/plan` (core plan-mode) gets no Plan control.
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

/**
 * The locally intended row while a `/plan-toggle` waits for the host: the target
 * state applied as an in-flight one, so the chip flips on the same frame as the
 * tap instead of after a round trip. `pending` reuses the host's own in-flight
 * meaning, which is what drives the `Plan…` label. `null` when the host
 * publishes no projection: the caller must not guess a state it cannot render.
 */
export function planIntentRow(plan: PlanModeRow | null): PlanModeRow | null {
  if (plan === null) {
    return null;
  }
  return { active: planTarget(plan), pending: true };
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
 * The command behind the Plan control, or '' to hide it. Only the plugin's
 * `plan-toggle` qualifies: a host that just offers the official `plan` command
 * still gets no control, because the hard sandbox gate and the review pipeline
 * only exist when the plugin is installed.
 */
export function planToggleCommand(groups: CommandGroupRow[]): string {
  return hasHostCommand(groups, 'plan-toggle') ? 'plan-toggle' : '';
}
/** The plugin writes its result for a keyboard; those sentences are useless on a phone. */
function withoutKeyboardHints(text: string): string {
  const kept: string[] = [];
  for (const sentence of text.split('。')) {
    const trimmed = sentence.trim();
    if (trimmed.length === 0 || trimmed.indexOf('Alt+') >= 0) {
      continue;
    }
    kept.push(trimmed);
  }
  return kept.join('。');
}

/**
 * Rewrite a plan command result for the phone. The host names Alt+1/Alt+2, but
 * the phone has the Plan chip and the review button instead, so drop those
 * sentences and append the on-screen guidance the user can actually act on.
 * Any other command's text is returned untouched.
 */
export function planCommandNotice(commandName: string, kind: string, text: string): string {
  if (commandName !== 'plan' && commandName !== 'plan-toggle' && commandName !== 'plan-review') {
    return text;
  }
  const base = withoutKeyboardHints(text);
  if (kind === 'error') {
    return base.length > 0 ? base : text;
  }
  if (commandName === 'plan-review') {
    return base;
  }
  // Only the plugin's toggle owns the on-screen controls; the official /plan
  // can run while no Plan chip is on screen, so it never points at one.
  if (commandName === 'plan') {
    return base;
  }
  const opened = text.indexOf('已开启') >= 0;
  const hint = opened
    ? '用下方的 Plan 关闭；plan 模式下点 Plan 旁边的「复核」跑流水线'
    : '写权限已还原';
  return base.length > 0 ? base + '。' + hint : hint;
}
