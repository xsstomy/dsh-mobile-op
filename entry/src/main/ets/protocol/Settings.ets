/**
 * Settings projections (pure logic, unit tested): model catalogue, reasoning
 * efforts, permission presets, agent presets and the slash command/skill menu.
 *
 * Two shapes are accepted on purpose — the documented one and the one the
 * gateway actually sends (measured 2026-09-10):
 *   permission-options.sessionPermissions.options = [{value, name}] + currentValue
 *   (docs: {id, label, selected})
 */
import {
  WireAgentPreset, WireCommandGroup, WireCommandItem, WireFrame, WireModelEntry, WireModelGroup,
  WireProvider, WireReasoningEffort
} from './Types';

export interface ReasoningEffortRow {
  id: string;
  name: string;
  description: string;
}

export interface ModelRow {
  id: string;
  name: string;
  description: string;
  efforts: ReasoningEffortRow[];
  defaultEffort: string;
  selected: boolean;
}

export interface ModelGroupRow {
  id: string;
  name: string;
  models: ModelRow[];
}

export interface ModelSelectionRow {
  provider: string;
  model: string;
  reasoningEffort: string;
}

export interface PermissionOptionRow {
  value: string;
  name: string;
  selected: boolean;
}

export interface AgentPresetRow {
  id: string;
  name: string;
  description: string;
  isDefault: boolean;
  defaultSelected: boolean;
}

export interface CommandItemRow {
  id: string;
  name: string;
  description: string;
  source: string;
  kind: string;
  submitRequest: string;
  submitText: string;
  insertText: string;
  displayHint: string;
  images: boolean;
  modelInvocable: boolean;
}

export interface CommandGroupRow {
  id: string;
  title: string;
  items: CommandItemRow[];
}

function currentSelection(frame: WireFrame): ModelSelectionRow {
  const current = frame.current ?? frame.selection ?? frame.saved;
  if (current === undefined) {
    return { provider: '', model: '', reasoningEffort: '' };
  }
  return {
    provider: current.provider ?? '',
    model: current.model ?? '',
    reasoningEffort: current.reasoningEffort ?? ''
  };
}

function effortRows(efforts: WireReasoningEffort[] | undefined): ReasoningEffortRow[] {
  const rows: ReasoningEffortRow[] = [];
  if (!Array.isArray(efforts)) {
    return rows;
  }
  for (const effort of efforts) {
    rows.push({
      id: effort.id ?? '',
      name: effort.name ?? (effort.id ?? ''),
      description: effort.description ?? ''
    });
  }
  return rows;
}

/** Flatten `models` groups; the session's current model is flagged as selected. */
export function modelGroupsFrom(frame: WireFrame): ModelGroupRow[] {
  const current = currentSelection(frame);
  const groups: ModelGroupRow[] = [];
  const rawGroups = frame.groups;
  if (!Array.isArray(rawGroups)) {
    return groups;
  }
  for (const raw of rawGroups) {
    const group = raw as WireModelGroup;
    const models: ModelRow[] = [];
    const rawModels = group.models;
    if (Array.isArray(rawModels)) {
      for (const entry of rawModels) {
        const model = entry as WireModelEntry;
        const reasoning = model.reasoning;
        models.push({
          id: model.id ?? '',
          name: model.name ?? (model.id ?? ''),
          description: model.description ?? '',
          efforts: effortRows(reasoning === undefined ? undefined : reasoning.efforts),
          defaultEffort: reasoning === undefined ? '' : (reasoning.defaultEffort ?? ''),
          selected: current.provider === (group.id ?? '') && current.model === (model.id ?? '')
        });
      }
    }
    groups.push({
      id: group.id ?? '',
      name: group.name ?? (group.id ?? ''),
      models: models
    });
  }
  return groups;
}

export function currentModelFrom(frame: WireFrame): ModelSelectionRow {
  return currentSelection(frame);
}

/**
 * The catalogue entry for one session route, matched on provider AND model id.
 * A live/routing provider can carry a model id that also exists under its
 * declared provider; only the (provider, model) pair identifies the entry whose
 * reasoning levels the host accepts, so callers must not fall back to an
 * id-only match.
 */
export function modelRowFor(groups: ModelGroupRow[], provider: string, model: string): ModelRow | undefined {
  for (const group of groups) {
    if (group.id !== provider) {
      continue;
    }
    for (const entry of group.models) {
      if (entry.id === model) {
        return entry;
      }
    }
  }
  return undefined;
}

/** Efforts available for one model, plus the effort that should be marked active. */
export function effortsFor(groups: ModelGroupRow[], provider: string, model: string,
  currentEffort: string): ReasoningEffortRow[] {
  for (const group of groups) {
    if (group.id !== provider) {
      continue;
    }
    for (const entry of group.models) {
      if (entry.id === model) {
        if (currentEffort.length > 0) {
          for (const effort of entry.efforts) {
            if (effort.id === currentEffort) {
              return orderEfforts(entry.efforts, currentEffort);
            }
          }
        }
        return orderEfforts(entry.efforts, entry.defaultEffort);
      }
    }
  }
  return [];
}

function orderEfforts(efforts: ReasoningEffortRow[], selectedId: string): ReasoningEffortRow[] {
  const selected: ReasoningEffortRow[] = [];
  const others: ReasoningEffortRow[] = [];
  for (const effort of efforts) {
    if (effort.id === selectedId) {
      selected.push(effort);
    } else {
      others.push(effort);
    }
  }
  const result: ReasoningEffortRow[] = [];
  for (const effort of others) {
    result.push(effort);
  }
  for (const effort of selected) {
    result.push(effort);
  }
  return result;
}

/** Permission presets from either wire shape. */
export function permissionOptionsFrom(frame: WireFrame): PermissionOptionRow[] {
  const rows: PermissionOptionRow[] = [];
  const permissions = frame.sessionPermissions;
  if (permissions !== undefined) {
    const options = permissions.options;
    if (Array.isArray(options)) {
      for (const option of options) {
        const value = option.value ?? (option.id ?? '');
        rows.push({
          value: value,
          name: option.name ?? (option.label ?? value),
          selected: value === permissions.currentValue
        });
      }
    }
    if (rows.length > 0) {
      return rows;
    }
  }
  const fallback = frame.options;
  if (Array.isArray(fallback)) {
    for (const option of fallback) {
      const value = option.id ?? '';
      rows.push({
        value: value,
        name: option.label ?? value,
        selected: option.selected === true
      });
    }
  }
  return rows;
}

export function currentPermissionFrom(frame: WireFrame): string {
  const permissions = frame.sessionPermissions;
  if (permissions === undefined) {
    return '';
  }
  return permissions.currentValue ?? '';
}

/**
 * DeepSeek Harness' own Simplified-Chinese labels for the built-in permission
 * presets (`packages/client/ui-permission-presets/src/client/locales.ts` and
 * `ui-conversation/.../locales.ts`): 仅可查看 / 工作区内修改 / 完全权限.
 * Unknown values fall through unchanged so host-defined presets stay readable.
 */
export function permissionLabel(value: string): string {
  switch (value) {
    case 'read-only':
      return '仅可查看';
    case 'workspace-write':
      return '工作区内修改';
    case 'danger-full-access':
      return '完全权限';
    default:
      return value;
  }
}

export function agentPresetsFrom(frame: WireFrame): AgentPresetRow[] {
  const rows: AgentPresetRow[] = [];
  const presets = frame.presets;
  if (!Array.isArray(presets)) {
    return rows;
  }
  for (const raw of presets) {
    const preset = raw as WireAgentPreset;
    rows.push({
      id: preset.id ?? '',
      name: preset.name ?? (preset.id ?? ''),
      description: preset.description ?? '',
      isDefault: preset.isDefault === true,
      defaultSelected: preset.isDefault === true
    });
  }
  return rows;
}

export function providersFrom(frame: WireFrame): WireProvider[] {
  const providers = frame.providers;
  return Array.isArray(providers) ? providers : [];
}

function commandItemRows(items: WireCommandItem[] | undefined): CommandItemRow[] {
  const rows: CommandItemRow[] = [];
  if (!Array.isArray(items)) {
    return rows;
  }
  for (const item of items) {
    const ui = item.ui;
    rows.push({
      id: item.id ?? '',
      name: item.name ?? '',
      description: item.description ?? '',
      source: item.source ?? '',
      kind: ui === undefined ? '' : (ui.kind ?? ''),
      submitRequest: ui === undefined ? '' : (ui.submitRequest ?? ''),
      submitText: ui === undefined ? '' : (ui.submitText ?? ''),
      insertText: ui === undefined ? '' : (ui.insertText ?? ''),
      displayHint: ui === undefined ? (item.input?.hint ?? '') : (ui.displayHint ?? (item.input?.hint ?? '')),
      images: ui === undefined ? false : ui.images === true,
      modelInvocable: item.modelInvocable !== false
    });
  }
  return rows;
}

export function commandGroupsFrom(frame: WireFrame): CommandGroupRow[] {
  const groups: CommandGroupRow[] = [];
  const rawGroups = frame.groups;
  if (!Array.isArray(rawGroups)) {
    return groups;
  }
  for (const raw of rawGroups) {
    const group = raw as WireCommandGroup;
    groups.push({
      id: group.id ?? '',
      title: group.title ?? (group.id ?? ''),
      items: commandItemRows(group.items)
    });
  }
  return groups;
}

/** Slash-menu filtering: only commands whose token starts with the typed query. */
export function filterCommands(groups: CommandGroupRow[], query: string): CommandGroupRow[] {
  const needle = query.replace(/^\//, '').replace(/^\s+|\s+$/g, '').toLowerCase();
  const result: CommandGroupRow[] = [];
  for (const group of groups) {
    const items: CommandItemRow[] = [];
    for (const item of group.items) {
      if (needle.length === 0 || item.name.toLowerCase().startsWith(needle)) {
        items.push(item);
      }
    }
    if (items.length > 0) {
      result.push({ id: group.id, title: group.title, items: items });
    }
  }
  return result;
}

/** The composer shows the menu only while the draft is a single `/token`. */
export function slashQueryOf(draft: string): string | null {
  if (!draft.startsWith('/')) {
    return null;
  }
  const body = draft.substring(1);
  if (body.indexOf(' ') >= 0 || body.indexOf('\n') >= 0) {
    return null;
  }
  return body;
}
