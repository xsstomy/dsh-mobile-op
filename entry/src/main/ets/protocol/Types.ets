/**
 * Wire DTOs for the `dsh-mobile-v1` protocol (see docs/PROTOCOL.md).
 * All fields are optional: unknown/new server fields must never break decoding.
 */

export interface WireDevice {
  id?: string;
  name?: string;
  createdAt?: number;
}

export interface WireWorkspace {
  workspaceId?: string;
  path?: string;
  title?: string;
  sessionIds?: string[];
  createdAt?: number;
  updatedAt?: number;
}

export interface WireSessionSummary {
  sessionId?: string;
  updatedAt?: number;
  running?: boolean;
  blank?: boolean;
  cwd?: string;
  agentPreset?: string;
  /** Projection snapshot (`asOfSeq` + `values`), present on `sessions` rows. */
  projections?: Object;
}

export interface WireCommandOption {
  id?: string;
  label?: string;
  detail?: string;
  description?: string;
  selected?: boolean;
}

export interface WireModelSelection {
  provider?: string;
  model?: string;
  reasoningEffort?: string;
}

export interface WireReasoningEffort {
  id?: string;
  name?: string;
  description?: string;
}

export interface WireReasoning {
  efforts?: WireReasoningEffort[];
  defaultEffort?: string;
}

export interface WireModelEntry {
  id?: string;
  name?: string;
  description?: string;
  reasoning?: WireReasoning;
}

export interface WireModelGroup {
  id?: string;
  name?: string;
  models?: WireModelEntry[];
}

export interface WireProvider {
  provider?: string;
  displayName?: string;
  declared?: boolean;
}

export interface WireAgentPreset {
  id?: string;
  name?: string;
  description?: string;
  trust?: string;
  isDefault?: boolean;
}

export interface WirePermissionEntry {
  value?: string;
  name?: string;
  /** Documented shape fallbacks. */
  id?: string;
  label?: string;
}

export interface WireSessionPermissions {
  options?: WirePermissionEntry[];
  currentValue?: string;
}

export interface WireCommandUi {
  kind?: string;
  submitRequest?: string;
  submitText?: string;
  insertText?: string;
  displayHint?: string;
  hint?: string;
  images?: boolean;
  optionsRequest?: string;
  selectionRequest?: string;
}

export interface WireCommandInput {
  hint?: string;
}

export interface WireCommandItem {
  id?: string;
  name?: string;
  description?: string;
  source?: string;
  action?: string;
  modelInvocable?: boolean;
  ui?: WireCommandUi;
  input?: WireCommandInput;
}

export interface WireCommandResult {
  kind?: string;
  text?: string;
  message?: string;
}

export interface WireCommandGroup {
  id?: string;
  title?: string;
  items?: WireCommandItem[];
}

export interface WirePermissionNamespace {
  name?: string;
  presets?: WireCommandOption[];
}

export interface WireGoalDefinition {
  id?: string;
  revision?: number;
  objective?: string;
  phase?: string;
  maxGoalRounds?: number;
}

export interface WireGoal {
  goal?: WireGoalDefinition;
  roundsStarted?: number;
  createdAt?: number;
  updatedAt?: number;
}

export interface WireTodo {
  content?: string;
  status?: string;
}

export interface WireImageAttachment {
  attachmentId?: string;
  mediaType?: string;
  bytes?: number;
  width?: number;
  height?: number;
  name?: string;
}

export interface WireSessionStats {
  turns?: number;
  steps?: number;
  llmMs?: number;
  toolMs?: number;
  ttftMs?: number;
  ttftSteps?: number;
  decodeMs?: number;
  decodeTokens?: number;
  lastTurn?: number;
}

export interface WireTokenTotals {
  inputTokens?: number;
  outputTokens?: number;
  cacheReadTokens?: number;
  cacheWriteTokens?: number;
  reasoningTokens?: number;
}

export interface WireTokenUsage {
  /** Documented wrapper (PROTOCOL.md §5). */
  totals?: WireTokenTotals;
  /** Flat fields actually sent by `session-stats` (measured 2026-09-10). */
  uncachedInputTokens?: number;
  outputTokens?: number;
  cacheReadTokens?: number;
  cacheWriteTokens?: number;
}

export interface WireContextPressure {
  contextWindow?: number;
  pressureTokens?: number;
  projectedTokens?: number;
  surfaceTokens?: number;
}

export interface WireSessionEvent {
  type?: string;
  seq?: number;
  time?: number;
  data?: Object;
}

export interface WireEventPayload {
  type?: string;
  turn?: number;
  step?: number;
  chunkType?: string;
  text?: string;
  reasoning?: string;
  tool?: Object;
  usage?: Object;
  finish?: Object;
  callId?: string;
  name?: string;
  /** `command/run` / `command/done`: the host command correlation id. */
  commandId?: string;
  /** `command/done`: `success` | `error`. */
  outcome?: string;
  arguments?: Object;
  isError?: boolean;
  preview?: string;
  reason?: string;
  title?: string;
  source?: Object;
  toolCalls?: Object[];
  todos?: Object[] | null;
  goal?: WireGoal | null;
  images?: WireImageAttachment[];
  preset?: string;
  mode?: string;
  policy?: string;
  /** Raw history shape: `content[]` text parts (user/message). */
  content?: Object[];
  /** Raw history shape: `message.content[]` (assistant/message). */
  message?: Object;
  /** Raw history shape: stream replay used only for diagnostics. */
  stream?: Object[];
}

export interface WireQueueItem {
  id?: string;
  placement?: string;
  rpcId?: string;
  message?: Object;
}

export interface WireQuestionOption {
  label?: string;
  description?: string;
}

export interface WireQuestion {
  id?: string;
  header?: string;
  question?: string;
  detail?: string;
  options?: WireQuestionOption[];
  multiSelect?: boolean;
  intent?: Object;
}

export interface WireDirectoryEntry {
  name?: string;
  path?: string;
  kind?: string;
  bytes?: number;
  modifiedAt?: number;
  mediaType?: string;
}

/** One server frame. `kind` is the discriminator; everything else is optional. */
export interface WireFrame {
  kind?: string;
  sessionId?: string;
  requestId?: string;
  transferId?: string;
  rpcId?: string;
  approvalId?: string;
  requestType?: string;
  code?: string;
  message?: string;
  reason?: string;
  action?: string;
  accepted?: boolean;
  outcome?: string;
  // handshake
  protocol?: number;
  capabilities?: string[];
  authenticated?: boolean;
  token?: string;
  device?: WireDevice;
  port?: number;
  clients?: number;
  // query results
  workspaces?: WireWorkspace[];
  items?: Object[];
  events?: WireSessionEvent[];
  hasMore?: boolean;
  nextBeforeSeq?: number;
  bytes?: number;
  view?: string;
  projections?: Object;
  workspace?: WireWorkspace;
  created?: boolean;
  path?: string;
  name?: string;
  home?: string;
  crumbs?: WireDirectoryEntry[];
  entries?: WireDirectoryEntry[];
  truncated?: boolean;
  workspaceId?: string;
  // session metadata
  title?: string;
  seq?: number;
  time?: number;
  archivedSessionIds?: string[];
  queues?: Object;
  todos?: WireTodo[] | null;
  goal?: WireGoal | null;
  ref?: WireGoalDefinition;
  cleared?: boolean;
  // models / permissions / presets
  current?: WireModelSelection;
  selected?: WireModelSelection;
  selection?: WireModelSelection;
  saved?: WireModelSelection;
  providers?: WireProvider[];
  locale?: string;
  presetsAuthorable?: boolean;
  routable?: boolean;
  failures?: Object[];
  namespace?: WirePermissionNamespace;
  sessionPermissions?: WireSessionPermissions;
  set?: string;
  presets?: WireAgentPreset[];
  authorable?: boolean;
  hasDocument?: boolean;
  agentPresetDefault?: string;
  permissionDefault?: string;
  agentPreset?: string;
  value?: Object;
  applied?: boolean;
  target?: string;
  // commands
  line?: string;
  commandId?: string;
  command?: Object;
  result?: WireCommandResult;
  commands?: Object[];
  skills?: Object[];
  options?: WireCommandOption[];
  groups?: Object[];
  // questions / approvals
  questions?: WireQuestion[];
  replay?: boolean;
  toolName?: string;
  callId?: string;
  // attachments / downloads
  attachment?: WireImageAttachment;
  data?: string;
  mediaType?: string;
  size?: number;
  chunkBytes?: number;
  offset?: number;
  eof?: boolean;
  sha256?: string;
  // stats / usage projections
  sessionStats?: WireSessionStats;
  tokenUsage?: WireTokenUsage;
  contextPressure?: WireContextPressure;
  asOfSeq?: number;
  // live event
  event?: WireEventPayload;
}
