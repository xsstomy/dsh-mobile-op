/**
 * Immutable UI snapshot.
 *
 * Pages link to ONE AppStorage entry (`UI_KEY`) whose identity changes on every
 * mutation, so ArkUI re-renders already-built pages. Reading plain store getters
 * is not enough: ArkUI only registers a dependency for state that build() reads.
 */
import { ConversationItem } from '../projection/Conversation';
import { GatewayConnectionState, GatewayFailureKind } from '../gateway/GatewayClient';
import { QuestionView } from '../protocol/Questions';
import { TrajectoryRow } from '../projection/Trajectory';
import { CrumbRow, FileEntryRow, PreviewKind } from '../protocol/Files';
import { PreparedImageRow } from '../protocol/Images';
import { QueueRow } from '../protocol/Queue';
import { TodoRow } from '../sync/Todos';
import {
  AgentPresetRow, CommandGroupRow, ModelGroupRow, ModelSelectionRow, PermissionOptionRow
} from '../protocol/Settings';

export const UI_KEY = 'gwUi';

export interface SessionRow {
  sessionId: string;
  title: string;
  cwd: string;
  running: boolean;
  blank: boolean;
  agentPreset: string;
  /** Epoch milliseconds from the host session summary (0 when unknown). */
  updatedAt: number;
}

export interface WorkspaceRow {
  workspaceId: string;
  title: string;
  path: string;
  sessionCount: number;
  active: boolean;
}

/** A pending Human-in-the-loop question batch (`question-requested`). */
export interface QuestionCardRow {
  rpcId: string;
  sessionId: string;
  questions: QuestionView[];
  replay: boolean;
}

/** A pending tool approval (`approval-requested`). */
export interface ApprovalCardRow {
  rpcId: string;
  sessionId: string;
  approvalId: string;
  toolName: string;
  reason: string;
  callId: string;
  replay: boolean;
}

export interface GoalRow {
  id: string;
  revision: number;
  objective: string;
  phase: string;
  roundsStarted: number;
  maxGoalRounds: number;
}

export interface StatsRow {
  turns: number;
  steps: number;
  llmMs: number;
  toolMs: number;
  ttftMs: number;
  ttftSteps: number;
  decodeTokens: number;
  decodeMs: number;
  inputTokens: number;
  outputTokens: number;
  cacheReadTokens: number;
  cacheWriteTokens: number;
  /** Cache hit share in percent, or -1 when no usage was reported yet. */
  cacheHitPercent: number;
  contextUsedPercent: number;
}

export interface DefaultsRow {
  agentPresetDefault: string;
  permissionDefault: string;
}

export interface CommandOutcome {
  line: string;
  kind: string;
  text: string;
}

export interface FilePreviewRow {
  path: string;
  name: string;
  kind: PreviewKind;
  text: string;
  truncated: boolean;
  bytes: number;
  localPath: string;
  sha256: string;
  verified: boolean;
}

export interface DownloadProgress {
  name: string;
  received: number;
  total: number;
  done: boolean;
  error: string;
}

export interface AttachmentRow {
  attachmentId: string;
  sessionId: string;
  localPath: string;
}

export interface SearchRow {
  sessionId: string;
  snippet: string;
}

export interface UiSnapshot {
  version: number;
  connection: GatewayConnectionState;
  connectionDetail: string;
  endpoint: string;
  capabilities: string[];
  notice: string;
  noticeIsError: boolean;
  failureKind: GatewayFailureKind;
  failureDetail: string;
  busy: boolean;
  workspaces: WorkspaceRow[];
  sessions: SessionRow[];
  activeWorkspaceId: string;
  activeSessionId: string;
  activeSessionTitle: string;
  conversation: ConversationItem[];
  /** True while the selected session's first history page is still loading. */
  conversationLoading: boolean;
  queueCount: number;
  questions: QuestionCardRow[];
  approvals: ApprovalCardRow[];
  todos: TodoRow[] | null;
  goal: GoalRow | null;
  stats: StatsRow | null;
  modelGroups: ModelGroupRow[];
  currentModel: ModelSelectionRow;
  permissionOptions: PermissionOptionRow[];
  currentPermission: string;
  agentPresets: AgentPresetRow[];
  defaults: DefaultsRow | null;
  defaultModel: ModelSelectionRow | null;
  commandGroups: CommandGroupRow[];
  commandOutcome: CommandOutcome | null;
  trajectory: TrajectoryRow[];
  trajectoryLoading: boolean;
  directoryPath: string;
  directoryHome: string;
  directoryCrumbs: CrumbRow[];
  directoryEntries: FileEntryRow[];
  directoryLoading: boolean;
  workspaceFiles: FileEntryRow[];
  workspaceFilePath: string;
  workspaceFilesLoading: boolean;
  filePreview: FilePreviewRow | null;
  download: DownloadProgress | null;
  preparedImages: PreparedImageRow[];
  imageBudgetOk: boolean;
  attachments: AttachmentRow[];
  queue: QueueRow[];
  searchResults: SearchRow[];
  searchError: string;
  themeMode: string;
  /** Render the agent's reasoning inside the conversation (device-local, default off). */
  showReasoning: boolean;
  /** True while the selected session has a turn in flight (drives the thinking indicator). */
  turnActive: boolean;
  /** Epoch ms the active turn started; 0 = running but start unknown. */
  turnStartedAt: number;
  backgroundTaskActive: boolean;
}

export function emptyQuestionCard(): QuestionCardRow {
  return { rpcId: '', sessionId: '', questions: [], replay: false };
}

export function emptyApprovalCard(): ApprovalCardRow {
  return { rpcId: '', sessionId: '', approvalId: '', toolName: '', reason: '', callId: '', replay: false };
}

export function emptyUiSnapshot(): UiSnapshot {
  return {
    version: 0,
    connection: GatewayConnectionState.DISCONNECTED,
    connectionDetail: '',
    endpoint: '',
    capabilities: [],
    notice: '',
    noticeIsError: false,
    failureKind: GatewayFailureKind.NETWORK,
    failureDetail: '',
    busy: false,
    workspaces: [],
    sessions: [],
    activeWorkspaceId: '',
    activeSessionId: '',
    activeSessionTitle: '',
    conversation: [],
    conversationLoading: false,
    queueCount: 0,
    questions: [],
    approvals: [],
    todos: null,
    goal: null,
    stats: null,
    modelGroups: [],
    currentModel: { provider: '', model: '', reasoningEffort: '' },
    permissionOptions: [],
    currentPermission: '',
    agentPresets: [],
    defaults: null,
    defaultModel: null,
    commandGroups: [],
    commandOutcome: null,
    trajectory: [],
    trajectoryLoading: false,
    directoryPath: '',
    directoryHome: '',
    directoryCrumbs: [],
    directoryEntries: [],
    directoryLoading: false,
    workspaceFiles: [],
    workspaceFilePath: '.',
    workspaceFilesLoading: false,
    filePreview: null,
    download: null,
    preparedImages: [],
    imageBudgetOk: true,
    attachments: [],
    queue: [],
    searchResults: [],
    searchError: '',
    themeMode: 'system',
    showReasoning: false,
    turnActive: false,
    turnStartedAt: 0,
    backgroundTaskActive: false
  };
}

// ---------------------------------------------------------------------------
// Snapshot selectors (pure; shared by the pages so they cannot drift apart)
// ---------------------------------------------------------------------------

/** The workspace currently driving the session list. */
export function activeWorkspace(ui: UiSnapshot): WorkspaceRow | undefined {
  if (ui.activeWorkspaceId.length > 0) {
    for (const workspace of ui.workspaces) {
      if (workspace.workspaceId === ui.activeWorkspaceId) {
        return workspace;
      }
    }
  }
  for (const workspace of ui.workspaces) {
    if (workspace.active) {
      return workspace;
    }
  }
  return ui.workspaces.length > 0 ? ui.workspaces[0] : undefined;
}

/**
 * Agent preset id of the open session. The host reports it inside
 * `sessions[].projections.values.agentPreset`, which the store copies into
 * `SessionRow.agentPreset`.
 */
export function sessionPresetId(ui: UiSnapshot): string {
  if (ui.activeSessionId.length === 0) {
    return '';
  }
  for (const session of ui.sessions) {
    if (session.sessionId === ui.activeSessionId) {
      return session.agentPreset;
    }
  }
  return '';
}

/** Preset display name (`ptc` → `PTC 模式`); falls back to the raw id. */
export function agentPresetLabel(ui: UiSnapshot, id: string): string {
  if (id.length === 0) {
    return '';
  }
  for (const preset of ui.agentPresets) {
    if (preset.id === id) {
      return preset.name;
    }
  }
  return id;
}
