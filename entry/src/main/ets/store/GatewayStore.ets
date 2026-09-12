/**
 * UI-facing store: the single owner of gateway state.
 *
 * Pages read immutable snapshots and call intent methods; they never speak the
 * protocol. Every mutation bumps an AppStorage version counter so shallow
 * @StorageLink consumers re-render.
 */
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { buffer } from '@kit.ArkTS';
import fs from '@ohos.file.fs';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { TurnBackgroundTask } from '../common/BackgroundTask';
import { applyThemeRuntime } from '../common/Constants';
import { WindowChrome } from '../common/WindowChrome';
import { image } from '@kit.ImageKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { GatewayClient, GatewayConnectionState, GatewayCredentials, GatewayFailureKind, GatewayListener } from '../gateway/GatewayClient';
import { GatewayPreferences } from '../auth/GatewayPreferences';
import { TokenStore } from '../auth/TokenStore';
import { DeepSeekKeyStore } from '../auth/DeepSeekKeyStore';
import { fetchDeepSeekBalance } from '../auth/DeepSeekBalance';
import { formatBalance, parseBalanceSnapshot } from '../protocol/Balance';
import { WireFrame, WireQueueItem, WireSessionEvent, WireSessionSummary, WireWorkspace } from '../protocol/Types';
import { asQueueItems, asSessionEvents, asSessionSummaries, asWorkspaces } from '../protocol/WireDecoder';
import { frameTargetsSession, mergeHistoryPage, mergeLiveEvent, titleOf } from '../sync/History';
import { ConversationItem, applyEvent, projectFromEvents } from '../projection/Conversation';
import { TurnActivityState, applyTurnActivity, turnIdle, turnRunning } from '../projection/TurnActivity';
import { GatewayPairingPayload, parsePairingPayload } from '../protocol/PairingPayload';
import {
  ApprovalCardRow, CommandOutcome, DefaultsRow, GoalRow, QuestionCardRow, SessionRow, StatsRow,
  UiSnapshot, WorkspaceRow, emptyUiSnapshot
} from './UiState';
import { TodoRow, shouldApplyTodos, todoRowsOf } from '../sync/Todos';
import {
  applyEventToRoster, applySessionTitle, applySummaryTitles, displayTitleOf, mergeSessionRows,
  nextTitleSeq, projectedTitleOf, projectionsSeqOf, rosterIncludesSession, SessionTitle
} from '../sync/Sessions';
import { TrajectoryRow, buildTrajectory } from '../projection/Trajectory';
import { CrumbRow, FileEntryRow, PreviewKind, fileRowsFrom, isTextPreview, previewKindOf, sha256Matches, sortEntries } from '../protocol/Files';
import { AttachmentRow, DownloadProgress, FilePreviewRow, SearchRow } from './UiState';
import { QueueRow, toQueueRows } from '../protocol/Queue';
import {
  DEFAULT_IMAGE_LIMITS, ImageLimits, OutgoingImagePayload, PreparedImageRow, base64ByteLength, compressTarget,
  fitsImageBudget, mediaTypeOfName, outgoingFrameBytes
} from '../protocol/Images';
import {
  AgentPresetRow, CommandGroupRow, CommandItemRow, ModelGroupRow, ModelSelectionRow, PermissionOptionRow,
  agentPresetsFrom, commandGroupsFrom, currentModelFrom, currentPermissionFrom, modelGroupsFrom,
  permissionOptionsFrom
} from '../protocol/Settings';
import { DraftAnswer, QuestionView, toQuestionViews } from '../protocol/Questions';
import { cacheHitPercent, contextUsedPercent, readTokenTotals, statsRefreshDelay } from '../sync/Stats';
import { isTransportUnavailable } from '../gateway/RequestTracker';
import { NetworkMonitor } from '../gateway/NetworkMonitor';
import {
  DEFAULT_LAN_PORT, SavedEndpoint, lanUrlFor, normalizeEndpointInput, parseSavedEndpoints, preferredEndpoint,
  removeSavedEndpoint, serializeSavedEndpoints, subnetProbeHosts, upsertSavedEndpoint
} from '../sync/Endpoints';
import { LanScanner } from '../gateway/LanScanner';
import { PlanModeRow, hasHostCommand, planCommandNotice, planModeOf, planToggleCommand } from '../sync/PlanMode';
import {
  ApprovalResponsePayload, CommandExecutePayload, DirectoryCreatePayload, DirectoryListPayload, CommandQueryPayload, CommandSelectPayload, CommandsQueryPayload,
  GoalMutationPayload, GoalRef, HistoryPayload, MessagePayload, PermissionPayload, QuestionAnswerItem,
  QuestionAnswerPayload, QuestionCancelPayload, RenamePayload, SaveDefaultModelPayload, SelectModelPayload,
  AttachmentPayload, FileDownloadOpenPayload, FileDownloadReadPayload, FileListPayload, OutgoingImage,
  QueueUpdatePayload, SearchPayload, SessionCreatePayload, SessionPayload, SetDefaultPayload, TrajectoryPayload,
  TypePayload, WorkspaceCreatePayload
} from '../protocol/Payloads';

export const UI_KEY = 'gwUi';

/** Kept for pages that only need a re-render nudge (see UiState for the real state). */
export const VERSION_KEY = 'gwUiVersion';

/** How many addresses one gateway may keep; oldest are dropped past this. */
const SAVED_ENDPOINT_LIMIT = 8;

/** Upper bound on hosts probed by the LAN discovery scan (one /24). */
const LAN_SCAN_HOST_LIMIT = 254;

/** Per-host TCP timeout for the LAN scan: long enough for Wi-Fi, short enough to sweep. */
const LAN_SCAN_TIMEOUT_MS = 400;

/**
 * The agent preset a session was started with. The host reports it inside
 * `projections.values.agentPreset` (measured on `sessions`), with the legacy
 * top-level `agentPreset` accepted as a fallback.
 */
function sessionPresetOf(session: WireSessionSummary): string {
  if (typeof session.agentPreset === 'string' && session.agentPreset.length > 0) {
    return session.agentPreset;
  }
  const projections = session.projections;
  if (projections === undefined || projections === null) {
    return '';
  }
  const values = (projections as Record<string, Object>)['values'];
  if (values === undefined || values === null) {
    return '';
  }
  const preset = (values as Record<string, Object>)['agentPreset'];
  return typeof preset === 'string' ? preset : '';
}

/** Command name of a slash line ('' when it is not slash-prefixed). */
function commandNameOf(line: string): string {
  const trimmed = line.trim();
  if (!trimmed.startsWith('/')) {
    return '';
  }
  const rest = trimmed.substring(1);
  const space = rest.indexOf(' ');
  return space < 0 ? rest : rest.substring(0, space);
}

/** Commands whose result can change the host plan projection. */
function isPlanFamilyCommand(name: string): boolean {
  return name === 'plan' || name === 'plan-toggle' || name === 'plan-review';
}

export interface StatusLine {
  state: GatewayConnectionState;
  detail: string;
  endpoint: string;
  capabilities: string[];
}

export interface ConnectionFailure {
  kind: GatewayFailureKind;
  detail: string;
}

class StoreListener implements GatewayListener {
  private readonly owner: GatewayStore;

  constructor(owner: GatewayStore) {
    this.owner = owner;
  }

  onFrame(frame: WireFrame, raw: string): void {
    this.owner.handleFrame(frame, raw);
  }

  onState(state: GatewayConnectionState, detail: string): void {
    this.owner.handleState(state, detail);
  }

  onFailure(kind: GatewayFailureKind, detail: string): void {
    this.owner.handleFailure(kind, detail);
  }

  onPaired(token: string): void {
    this.owner.handlePaired(token);
  }
}

/**
 * Delays between retries of a roster request that lost the race with the
 * socket. The gateway may report `connected` a few milliseconds before a lane
 * accepts writes, so a single attempt is not trustworthy (B16).
 */
const CONNECT_RETRY_DELAYS: number[] = [0, 400, 1200, 2500];

/**
 * Floor between two live `session-stats` queries while a turn is running. The
 * gateway only pushes `todos`/`goal` projections, so a live run-time bar has to
 * poll; 3 s keeps 轮次/步骤/上下文/缓存命中 moving without one host fold per event.
 */
const STATS_REFRESH_MIN_MS = 3000;

/**
 * The first `onPageShow` after `selectSession` must not repeat the history fetch
 * the open just performed. A `history` page is ~1.3 MB on a long session, so
 * re-downloading it immediately doubles the wait over a WAN tunnel and competes
 * with the first render. Re-sync only once the open is older than this window
 * (returning from Settings or the background still refreshes).
 */
const CATCHUP_FRESH_MS = 2000;

/**
 * History pages are large — a 60-message page of a long live session measured
 * ~1.3 MB — so the first paint asks for fewer messages and the rest streams in
 * when the user scrolls up (`loadOlder`). 20 messages ≈ 0.5 MB ≈ 3x faster to
 * open over the tunnel.
 */
const INITIAL_HISTORY_MESSAGES = 20;
const HISTORY_PAGE_MESSAGES = 60;

/**
 * Re-entering a session should paint its transcript immediately instead of
 * re-fetching it, so keep the last few conversations in memory and show the
 * cached timeline as the first paint while `loadSessionData` still fetches the
 * latest page in the background. `mergeHistoryPage` dedupes by `seq`, so the
 * cached events are merged with (not dropped in favour of) the fresh page.
 * Bounded so a long, deeply-paged session cannot pin memory.
 */
const MAX_CACHED_SESSIONS = 3;
const MAX_CACHED_EVENTS = 3000;

/** The official balance changes slowly; do not hit it on every page show. */
const BALANCE_REFRESH_MIN_MS = 60000;

function delay(ms: number): Promise<void> {
  return new Promise<void>((resolve: (value: void) => void) => {
    setTimeout(() => {
      resolve();
    }, ms);
  });
}

export class GatewayStore {
  private static instance: GatewayStore | undefined;

  private readonly client: GatewayClient = new GatewayClient();
  private readonly network: NetworkMonitor = new NetworkMonitor();
  private readonly listener: StoreListener = new StoreListener(this);
  private preferences: GatewayPreferences | undefined;
  private tokens: TokenStore = new TokenStore();
  private deepSeekKeys: DeepSeekKeyStore = new DeepSeekKeyStore();
  /** Cached DeepSeek API key ('' = not configured). Never logged. */
  private deepSeekKey: string = '';
  private balanceDisplay: string = '';
  private balanceError: string = '';
  private balanceAt: number = 0;
  private balanceFetchedAt: number = 0;
  private balanceFetchInFlight: boolean = false;

  private status: StatusLine = {
    state: GatewayConnectionState.DISCONNECTED,
    detail: '',
    endpoint: '',
    capabilities: []
  };
  private failure: ConnectionFailure | undefined;
  private notice: string = '';
  private noticeIsError: boolean = false;
  private endpointCache: string = '';
  private workspaces: WireWorkspace[] = [];
  private sessions: WireSessionSummary[] = [];
  private archivedSessionIds: string[] = [];
  private selectedWorkspaceId: string = '';
  private selectedSessionId: string = '';
  /** Display title per session, ordered by the seq that produced it (see sync/Sessions). */
  private sessionTitles: Map<string, SessionTitle> = new Map<string, SessionTitle>();
  private history: WireSessionEvent[] = [];
  private conversation: ConversationItem[] = [];
  /** True while the selected session's first history page is in flight. */
  private conversationLoading: boolean = false;
  /** Last known timeline per session; bounded LRU used as the instant first paint. */
  private historyCache: Map<string, WireSessionEvent[]> = new Map<string, WireSessionEvent[]>();
  private historyCacheOrder: string[] = [];
  /** Session id + time of the last successful `history` load (see CATCHUP_FRESH_MS). */
  private historyLoadedSessionId: string = '';
  private historyLoadedAt: number = 0;
  private queues: Map<string, WireQueueItem[]> = new Map<string, WireQueueItem[]>();
  private questions: Map<string, QuestionCardRow> = new Map<string, QuestionCardRow>();
  private approvals: Map<string, ApprovalCardRow> = new Map<string, ApprovalCardRow>();
  private todos: TodoRow[] | null = null;
  /** `asOfSeq` of the applied `todos` projection (PROTOCOL.md 6.1). */
  private todosSeq: number = -1;
  private goal: GoalRow | null = null;
  private stats: StatsRow | null = null;
  /** Trailing-edge throttle for live `session-stats` refreshes (see below). */
  private statsRefreshTimer: number = -1;
  private statsRefreshedAt: number = 0;
  private modelGroups: ModelGroupRow[] = [];
  private currentModel: ModelSelectionRow = { provider: '', model: '', reasoningEffort: '' };
  private permissionOptions: PermissionOptionRow[] = [];
  private currentPermission: string = '';
  private agentPresets: AgentPresetRow[] = [];
  private defaults: DefaultsRow | null = null;
  private defaultModel: ModelSelectionRow | null = null;
  private commandGroups: CommandGroupRow[] = [];
  private commandOutcome: CommandOutcome | null = null;
  private trajectory: TrajectoryRow[] = [];
  private trajectoryLoading: boolean = false;
  private filesDir: string = '';
  private directoryPath: string = '';
  private directoryHome: string = '';
  private directoryCrumbs: CrumbRow[] = [];
  private directoryEntries: FileEntryRow[] = [];
  private directoryLoading: boolean = false;
  private workspaceFiles: FileEntryRow[] = [];
  private workspaceFilePath: string = '.';
  private workspaceFilesLoading: boolean = false;
  private filePreview: FilePreviewRow | null = null;
  private download: DownloadProgress | null = null;
  private preparedImages: PreparedImageRow[] = [];
  private attachments: Map<string, string> = new Map<string, string>();
  private imageLimits: ImageLimits = DEFAULT_IMAGE_LIMITS;
  private searchResults: SearchRow[] = [];
  private searchError: string = '';
  private themeMode: string = 'system';
  private showReasoning: boolean = false;
  private turnActivity: TurnActivityState = turnIdle();
  private readonly backgroundTask: TurnBackgroundTask = new TurnBackgroundTask();
  private appContext: common.Context | undefined = undefined;
  private busy: boolean = false;
  private pairingInFlight: boolean = false;
  private savedToken: string = '';
  /** Saved addresses for the current gateway, newest first (sync/Endpoints). */
  private savedEndpoints: SavedEndpoint[] = [];
  /** Auto endpoint switching: prefer the LAN at home, the public URL elsewhere. */
  private autoSwitch: boolean = true;
  /** Re-entrancy guard so a network flap cannot stack auto-selections. */
  private autoSelecting: boolean = false;
  /** LAN discovery: probes the current /24 for the gateway listener. */
  private readonly lanScanner: LanScanner = new LanScanner();
  private scanning: boolean = false;
  /** Latest default-network availability, surfaced so the UI can say 无网络. */
  private networkAvailable: boolean = true;
  /** Host plan projection for the selected session (null = unpublished). */
  private plan: PlanModeRow | null = null;
  /** asOfSeq of the applied plan projection; an older snapshot is ignored. */
  private planSeq: number = -1;
  /** /plan-review pipeline progress (driven by command/run + command/done). */
  private planReviewRunning: boolean = false;
  private planReviewCommandId: string = '';
  /** Latest issued command, used to label the result text. */
  private recentCommandName: string = '';
  private recentCommandLine: string = '';
  /** Composer quick-insert visibility (device-local, default off). */
  private showSlashShortcut: boolean = false;
  private showMentionShortcut: boolean = false;

  static get current(): GatewayStore {
    if (GatewayStore.instance === undefined) {
      GatewayStore.instance = new GatewayStore();
    }
    return GatewayStore.instance;
  }

  /** True when an endpoint + token are available for an unattended reconnect. */
  get hasSavedCredential(): boolean {
    return this.savedToken.length > 0 && this.endpointCache.length > 0;
  }

  get currentThemeMode(): string {
    return this.themeMode;
  }

  get turnActive(): boolean {
    return this.turnActivity.active;
  }

  /**
   * Show/hide the agent's reasoning inside the conversation. Device-local (no
   * server capability involved) and persisted, so the choice survives a restart.
   */
  async setShowReasoning(value: boolean): Promise<void> {
    this.showReasoning = value;
    await this.preferences?.setShowReasoning(value);
    this.publish();
  }

  /** Composer quick-insert visibility; device-local and persisted. */
  async setShowSlashShortcut(value: boolean): Promise<void> {
    this.showSlashShortcut = value;
    await this.preferences?.setShowSlashShortcut(value);
    this.publish();
  }

  async setShowMentionShortcut(value: boolean): Promise<void> {
    this.showMentionShortcut = value;
    await this.preferences?.setShowMentionShortcut(value);
    this.publish();
  }

  /**
   * Persist the choice, then hand it to the platform: the app colour mode makes
   * ArkUI re-resolve every `app.color.*` resource on the spot, so the whole UI
   * repaints without leaving the page.
   */
  async setThemeMode(mode: string): Promise<void> {
    this.themeMode = mode;
    await this.preferences?.setThemeMode(mode);
    this.applyAppColorMode(mode);
    // No notice: the repaint is the feedback, and the banner used to cover the
    // page with "已切换为…主题" long after the switch.
    this.publish();
  }

  /** Map our three modes onto the application colour mode. */
  private applyAppColorMode(mode: string): void {
    try {
      const colorMode = mode === 'light'
        ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
        : (mode === 'dark'
          ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
          : ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
      (this.appContext as common.Context).getApplicationContext().setColorMode(colorMode);
      // The ability context already reflects the effective value (verified on
      // device), which keeps the canvas/system bars in step immediately.
      const effective = (this.appContext as common.UIAbilityContext).config.colorMode;
      this.onColorModeChanged(effective === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    } catch (error) {
      hilog.error(0x0000, 'GatewayStore', 'setColorMode failed: %{public}s', JSON.stringify(error));
    }
  }

  /** Called by the ability on configuration changes and by the theme switch. */
  onColorModeChanged(dark: boolean): void {
    applyThemeRuntime(dark);
    WindowChrome.apply();
  }

  get statusLine(): StatusLine {
    return this.status;
  }

  get lastFailure(): ConnectionFailure | undefined {
    return this.failure;
  }

  get lastNotice(): string {
    return this.notice;
  }

  get workspaceList(): WireWorkspace[] {
    return this.workspaces;
  }

  get sessionList(): WireSessionSummary[] {
    const result: WireSessionSummary[] = [];
    for (const session of this.sessions) {
      const id = session.sessionId ?? '';
      if (id.length === 0 || this.archivedSessionIds.indexOf(id) >= 0) {
        continue;
      }
      if (!rosterIncludesSession(this.workspaces, this.selectedWorkspaceId, id)) {
        continue;
      }
      result.push(session);
    }
    return result;
  }

  get activeWorkspaceId(): string {
    return this.selectedWorkspaceId;
  }

  get activeSessionId(): string {
    return this.selectedSessionId;
  }

  get conversationItems(): ConversationItem[] {
    return this.conversation;
  }

  get isBusy(): boolean {
    return this.busy;
  }

  get pendingQueue(): WireQueueItem[] {
    return this.queues.get(this.selectedSessionId) ?? [];
  }

  titleOfSession(sessionId: string): string {
    return displayTitleOf(this.sessionTitles, sessionId);
  }

  /**
   * Ordered title write shared by live events, metadata pushes, local renames
   * and projection snapshots: only a newer seq may replace the stored name, so
   * the home roster and the open conversation can never disagree about it.
   */
  private setSessionTitle(sessionId: string, title: string, seq: number): void {
    applySessionTitle(this.sessionTitles, sessionId, title, seq);
  }

  private workspaceOf(workspaceId: string): WireWorkspace | undefined {
    for (const workspace of this.workspaces) {
      if (workspace.workspaceId === workspaceId) {
        return workspace;
      }
    }
    return undefined;
  }

  private snapshotVersion: number = 0;

  /** Build and publish a brand-new snapshot so ArkUI re-renders built pages. */
  private publish(): void {
    this.snapshotVersion += 1;
    const snapshot: UiSnapshot = emptyUiSnapshot();
    snapshot.version = this.snapshotVersion;
    snapshot.connection = this.status.state;
    snapshot.connectionDetail = this.status.detail;
    snapshot.endpoint = this.endpointCache.length > 0 ? this.endpointCache : this.status.endpoint;
    snapshot.savedEndpoints = this.savedEndpoints;
    snapshot.autoSwitch = this.autoSwitch;
    snapshot.endpointScanning = this.scanning;
    snapshot.networkAvailable = this.networkAvailable;
    snapshot.plan = this.plan;
    snapshot.planToggleCommand = planToggleCommand(this.commandGroups);
    snapshot.planReviewAvailable = hasHostCommand(this.commandGroups, 'plan-review');
    snapshot.planReviewRunning = this.planReviewRunning;
    snapshot.capabilities = this.status.capabilities;
    snapshot.notice = this.notice;
    snapshot.noticeIsError = this.noticeIsError;
    snapshot.failureKind = this.failure === undefined ? GatewayFailureKind.NETWORK : this.failure.kind;
    snapshot.failureDetail = this.failure === undefined ? '' : this.failure.detail;
    snapshot.busy = this.busy;
    snapshot.activeWorkspaceId = this.selectedWorkspaceId;
    snapshot.activeSessionId = this.selectedSessionId;
    snapshot.activeSessionTitle = this.titleOfSession(this.selectedSessionId);
    snapshot.queueCount = (this.queues.get(this.selectedSessionId) ?? []).length;
    snapshot.conversation = this.conversation;
    snapshot.conversationLoading = this.conversationLoading;
    snapshot.balanceConfigured = this.deepSeekKey.length > 0;
    snapshot.balanceDisplay = this.balanceDisplay;
    snapshot.balanceError = this.balanceError;
    snapshot.balanceAt = this.balanceAt;
    // Pending cards are stored for every session (a switch must still find
    // them) but only the open session may render them; otherwise a question or
    // approval raised in another conversation shows up in this one.
    const questions: QuestionCardRow[] = [];
    this.questions.forEach((question: QuestionCardRow) => {
      if (question.sessionId === this.selectedSessionId) {
        questions.push(question);
      }
    });
    snapshot.questions = questions;
    const approvals: ApprovalCardRow[] = [];
    this.approvals.forEach((approval: ApprovalCardRow) => {
      if (approval.sessionId === this.selectedSessionId) {
        approvals.push(approval);
      }
    });
    snapshot.approvals = approvals;
    snapshot.todos = this.todos;
    snapshot.goal = this.goal;
    snapshot.stats = this.stats;
    snapshot.modelGroups = this.modelGroups;
    snapshot.currentModel = this.currentModel;
    snapshot.permissionOptions = this.permissionOptions;
    snapshot.currentPermission = this.currentPermission;
    snapshot.agentPresets = this.agentPresets;
    snapshot.defaults = this.defaults;
    snapshot.defaultModel = this.defaultModel;
    snapshot.commandGroups = this.commandGroups;
    snapshot.commandOutcome = this.commandOutcome;
    snapshot.trajectory = this.trajectory;
    snapshot.trajectoryLoading = this.trajectoryLoading;
    snapshot.directoryPath = this.directoryPath;
    snapshot.directoryHome = this.directoryHome;
    snapshot.directoryCrumbs = this.directoryCrumbs;
    snapshot.directoryEntries = this.directoryEntries;
    snapshot.directoryLoading = this.directoryLoading;
    snapshot.workspaceFiles = this.workspaceFiles;
    snapshot.workspaceFilePath = this.workspaceFilePath;
    snapshot.workspaceFilesLoading = this.workspaceFilesLoading;
    snapshot.filePreview = this.filePreview;
    snapshot.download = this.download;
    snapshot.preparedImages = this.preparedImages;
    snapshot.imageBudgetOk = fitsImageBudget(this.preparedImages, '', this.imageLimits);
    const attachments: AttachmentRow[] = [];
    this.attachments.forEach((localPath: string, attachmentId: string) => {
      attachments.push({ attachmentId: attachmentId, sessionId: this.selectedSessionId, localPath: localPath });
    });
    snapshot.attachments = attachments;
    snapshot.queue = toQueueRows(this.queues.get(this.selectedSessionId) ?? []);
    snapshot.searchResults = this.searchResults;
    snapshot.searchError = this.searchError;
    snapshot.themeMode = this.themeMode;
    snapshot.showReasoning = this.showReasoning;
    snapshot.showSlashShortcut = this.showSlashShortcut;
    snapshot.showMentionShortcut = this.showMentionShortcut;
    snapshot.turnActive = this.turnActivity.active;
    snapshot.turnStartedAt = this.turnActivity.startedAt;
    snapshot.backgroundTaskActive = this.backgroundTask.isRunning;
    const workspaces: WorkspaceRow[] = [];
    for (const workspace of this.workspaces) {
      workspaces.push({
        workspaceId: workspace.workspaceId ?? '',
        title: workspace.title ?? workspace.path ?? '未命名',
        path: workspace.path ?? '',
        sessionCount: (workspace.sessionIds ?? []).length,
        active: (workspace.workspaceId ?? '') === this.selectedWorkspaceId
      });
    }
    snapshot.workspaces = workspaces;
    const sessions: SessionRow[] = [];
    for (const session of this.sessionList) {
      const sessionId = session.sessionId ?? '';
      sessions.push({
        sessionId: sessionId,
        title: this.titleOfSession(sessionId),
        cwd: session.cwd ?? '',
        running: session.running === true,
        blank: session.blank === true,
        agentPreset: sessionPresetOf(session),
        updatedAt: typeof session.updatedAt === 'number' ? session.updatedAt : 0
      });
    }
    snapshot.sessions = sessions;
    AppStorage.setOrCreate<UiSnapshot>(UI_KEY, snapshot);
    const current = AppStorage.get<number>(VERSION_KEY) ?? 0;
    AppStorage.setOrCreate<number>(VERSION_KEY, current + 1);
  }

  private initPromise: Promise<void> | undefined;

  /**
   * Idempotent initialisation. Concurrent callers (EntryAbility + first page)
   * must await the SAME promise, otherwise a caller can observe a half-initialised
   * store (missing token) and wrongly report "not paired".
   */
  init(context: common.Context): Promise<void> {
    if (this.initPromise === undefined) {
      this.initPromise = this.doInit(context);
    }
    return this.initPromise;
  }

  private async doInit(context: common.Context): Promise<void> {
    this.filesDir = context.filesDir;
    this.appContext = context;
    this.preferences = await GatewayPreferences.open(context);
    await this.tokens.attach(context);
    await this.deepSeekKeys.attach(context);
    this.deepSeekKey = await this.deepSeekKeys.load();
    this.themeMode = await this.preferences.themeMode();
    this.showReasoning = await this.preferences.showReasoning();
    this.showSlashShortcut = await this.preferences.showSlashShortcut();
    this.showMentionShortcut = await this.preferences.showMentionShortcut();
    this.applyAppColorMode(this.themeMode);
    this.selectedWorkspaceId = await this.preferences.workspaceId();
    this.selectedSessionId = await this.preferences.lastSessionId();
    this.client.subscribe(this.listener);
    // Network recovery: skip the rest of the reconnect backoff once the default
    // network is usable again (wifi/radio came back).
    this.network.start(() => {
      // An interface came back: pick the right address BEFORE retrying, so the
      // client does not reconnect to the listener we can no longer reach.
      this.networkAvailable = this.network.hint().available;
      this.maybeAutoSelect().then(() => {
        this.client.retryNow();
      }).catch((error: Error) => {
        void error;
        this.client.retryNow();
      });
    }, () => {
      // Wi-Fi/cellular changed: re-evaluate the preferred address. A live
      // connection is never torn down here (see maybeAutoSelect), but the UI
      // must know at once when there is no network left at all.
      this.networkAvailable = this.network.hint().available;
      this.publish();
      void this.maybeAutoSelect();
    });
    this.autoSwitch = await this.preferences.autoSwitch();
    this.networkAvailable = this.network.hint().available;
    this.savedEndpoints = parseSavedEndpoints(await this.preferences.endpointRecordsRaw());
    let endpoint = await this.preferences.endpoint();
    this.endpointCache = endpoint;
    const token = endpoint.length > 0 ? await this.tokens.load(endpoint) : '';
    this.savedToken = token;
    if (token.length > 0 && endpoint.length > 0) {
      // Record the paired address so an install that predates this feature
      // starts with a one-row list instead of an empty one.
      this.savedEndpoints = upsertSavedEndpoint(this.savedEndpoints, endpoint, Date.now(), SAVED_ENDPOINT_LIMIT);
      await this.preferences.setEndpointRecordsRaw(serializeSavedEndpoints(this.savedEndpoints));
      await this.saveTokenToAll();
      // Prefer a better address (the LAN at home) before the first connect. The
      // token is gateway-scoped, so it is copied to the chosen alias.
      const preferred = preferredEndpoint(this.savedEndpoints, this.network.hint());
      if (this.autoSwitch && preferred.length > 0 && preferred !== endpoint) {
        endpoint = preferred;
        this.endpointCache = preferred;
        await this.preferences.setEndpoint(preferred);
        await this.tokens.save(preferred, token);
      }
    }
    if (endpoint.length > 0) {
      // Show the stored endpoint even when the token is missing, so the UI can
      // explain what is wrong instead of claiming "not configured".
      this.status = { state: GatewayConnectionState.DISCONNECTED, detail: '已保存端点', endpoint: endpoint, capabilities: [] };
    }
    if (token.length === 0 && endpoint.length > 0) {
      this.notice = '未找到该端点的设备 token，请重新配对';
    }
    if (endpoint.length > 0 && token.length > 0) {
      const deviceId = await this.preferences.deviceId();
      this.status = { state: GatewayConnectionState.CONNECTING, detail: endpoint, endpoint: endpoint, capabilities: [] };
      this.client.connect({ endpoint: endpoint, deviceId: deviceId, token: token });
    }
    this.publish();
  }

  /** Pair with a scanned/pasted payload; `endpointOverride` supports emulator/LAN fixes. */
  async pair(payloadText: string, endpointOverride: string): Promise<void> {
    const preferences = this.preferences;
    if (preferences === undefined) {
      throw new Error('应用尚未初始化');
    }
    const parsed = parsePairingPayload(payloadText, Date.now());
    const endpoint = endpointOverride.length > 0 ? endpointOverride : parsed.publicUrl;
    const deviceId = await preferences.deviceId();
    await preferences.setEndpoint(endpoint);
    this.endpointCache = endpoint;
    // Keep BOTH the QR's public address and any manual LAN override: one pairing
    // yields one token that authenticates on either listener.
    await this.rememberEndpoint(parsed.publicUrl, false);
    // A different gateway serves different sessions; never reuse cached ones.
    this.clearHistoryCache();
    this.pairingInFlight = true;
    this.status = { state: GatewayConnectionState.CONNECTING, detail: endpoint, endpoint: endpoint, capabilities: [] };
    const credentials: GatewayCredentials = {
      endpoint: endpoint,
      deviceId: deviceId,
      pairingCode: parsed.pairingCode
    };
    this.client.startPairing(credentials);
    // Keep the parsed payload around for diagnostics.
    void (parsed as GatewayPairingPayload);
  }

  /**
   * True when an endpoint + token are on disk, i.e. `connectSaved()` can actually
   * run. Distinct from the `hasSavedCredential` getter, which only reflects the
   * in-memory cache and is therefore empty on a cold start.
   */
  async hasStoredCredential(): Promise<boolean> {
    const preferences = this.preferences;
    if (preferences === undefined) {
      return false;
    }
    const endpoint = await preferences.endpoint();
    if (endpoint.length === 0) {
      return false;
    }
    const token = await this.tokens.load(endpoint);
    return token.length > 0;
  }

  /**
   * Drop the socket but KEEP the stored credential, so `重新连接` (or the next
   * app launch) returns to the same endpoint without re-pairing. 解除配对 stays
   * the destructive variant that requires a new scan/paste.
   */
  disconnect(): void {
    // No announcement: the home page already shows the connection state next to
    // 最近会话, so a second banner just duplicates it. Clear any stale notice so
    // an earlier message cannot linger after the socket is gone.
    this.client.disconnect();
    this.notice = '';
    this.noticeIsError = false;
    this.publish();
  }

  async connectSaved(): Promise<void> {
    const state = this.client.connectionState;
    if (state === GatewayConnectionState.CONNECTED || state === GatewayConnectionState.CONNECTING ||
      state === GatewayConnectionState.AUTHENTICATING) {
      // Never tear down a healthy connection just because a page re-ran init.
      return;
    }
    const preferences = this.preferences;
    if (preferences === undefined) {
      return;
    }
    const endpoint = await preferences.endpoint();
    const token = endpoint.length > 0 ? await this.tokens.load(endpoint) : '';
    if (endpoint.length === 0 || token.length === 0) {
      throw new Error('尚未配对：请先扫描或粘贴配对二维码内容');
    }
    this.savedToken = token;
    const deviceId = await preferences.deviceId();
    this.failure = undefined;
    // Reconnecting clears any notice left behind by the dropped socket.
    this.notice = '';
    this.noticeIsError = false;
    this.client.connect({ endpoint: endpoint, deviceId: deviceId, token: token });
  }

  /**
   * Remember an address the client has used, newest first, and (optionally) keep
   * a copy of the device token under its alias so a later switch reconnects
   * without re-pairing. The credential is gateway-scoped (PROTOCOL.md §1), so
   * copying it to a second listener of the same gateway is the intended model.
   */
  private async rememberEndpoint(url: string, copyToken: boolean): Promise<void> {
    const trimmed = url.replace(/^s+|s+$/g, '');
    if (trimmed.length === 0) {
      return;
    }
    this.savedEndpoints = upsertSavedEndpoint(this.savedEndpoints, trimmed, Date.now(), SAVED_ENDPOINT_LIMIT);
    const preferences = this.preferences;
    if (preferences !== undefined) {
      await preferences.setEndpointRecordsRaw(serializeSavedEndpoints(this.savedEndpoints));
    }
    if (copyToken && this.savedToken.length > 0) {
      await this.saveTokenToAll();
    }
  }

  /**
   * Keep the (gateway-scoped) device token under every saved alias, so whichever
   * address ends up active after a restart can be loaded by `connectSaved`.
   */
  private async saveTokenToAll(): Promise<void> {
    if (this.savedToken.length === 0) {
      return;
    }
    for (const saved of this.savedEndpoints) {
      try {
        await this.tokens.save(saved.url, this.savedToken);
      } catch (error) {
        hilog.warn(0x0000, 'GatewayStore', 'endpoint token copy failed: %{public}s', JSON.stringify(error));
      }
    }
  }

  /** Add a user-typed address: host, host:port or a full ws/wss URL. */
  async addEndpoint(text: string): Promise<boolean> {
    const url = normalizeEndpointInput(text);
    if (url.length === 0) {
      return false;
    }
    await this.rememberEndpoint(url, true);
    this.publish();
    return true;
  }

  /** Forget an address. If it was active, the live connection moves to another. */
  async forgetEndpoint(url: string): Promise<void> {
    this.savedEndpoints = removeSavedEndpoint(this.savedEndpoints, url);
    const preferences = this.preferences;
    if (preferences !== undefined) {
      await preferences.setEndpointRecordsRaw(serializeSavedEndpoints(this.savedEndpoints));
    }
    if (url === this.endpointCache) {
      const next = preferredEndpoint(this.savedEndpoints, this.network.hint());
      if (next.length > 0) {
        await this.switchEndpoint(next);
        return;
      }
    } else {
      await this.tokens.clear(url);
    }
    this.publish();
  }

  /**
   * Switch the live connection to another saved address of the same gateway.
   * Session/workspace caches are deliberately kept: only the transport changes.
   */
  async switchEndpoint(url: string): Promise<void> {
    const preferences = this.preferences;
    const trimmed = url.replace(/^s+|s+$/g, '');
    if (preferences === undefined || trimmed.length === 0) {
      return;
    }
    const state = this.client.connectionState;
    if (trimmed === this.endpointCache &&
      (state === GatewayConnectionState.CONNECTED || state === GatewayConnectionState.CONNECTING ||
        state === GatewayConnectionState.AUTHENTICATING)) {
      return;
    }
    let token = this.savedToken;
    if (token.length === 0 && this.endpointCache.length > 0) {
      token = await this.tokens.load(this.endpointCache);
    }
    if (token.length === 0) {
      token = await this.tokens.load(trimmed);
    }
    if (token.length === 0) {
      this.notice = '该地址没有可用凭据，请先配对';
      this.noticeIsError = true;
      await this.rememberEndpoint(trimmed, false);
      this.publish();
      return;
    }
    this.savedToken = token;
    this.endpointCache = trimmed;
    await preferences.setEndpoint(trimmed);
    await this.rememberEndpoint(trimmed, true);
    this.failure = undefined;
    this.notice = '';
    this.noticeIsError = false;
    const deviceId = await preferences.deviceId();
    // connect() tears the old channels down and opens new ones; there is no need
    // (and no safe place) for an explicit disconnect in between.
    this.client.connect({ endpoint: trimmed, deviceId: deviceId, token: token });
    this.publish();
  }

  /**
   * Auto endpoint choice (see sync/Endpoints): the LAN address at home, the
   * public one elsewhere. Never tears down a live connection — a network move
   * fails the transport on its own, and the reconnect then re-evaluates here.
   */
  private async maybeAutoSelect(): Promise<void> {
    if (!this.autoSwitch || this.autoSelecting) {
      return;
    }
    const preferences = this.preferences;
    if (preferences === undefined || this.savedEndpoints.length === 0) {
      return;
    }
    // A healthy link is never torn down: a network move fails it on its own and
    // the failure path calls back here. A reconnect IN FLIGHT is fair game —
    // that is exactly the case where the client is retrying the now-unreachable
    // listener, and the switch has to win before the backoff timer fires.
    if (this.client.connectionState === GatewayConnectionState.CONNECTED) {
      return;
    }
    const preferred = preferredEndpoint(this.savedEndpoints, this.network.hint());
    if (preferred.length === 0 || preferred === this.endpointCache) {
      return;
    }
    hilog.info(0x0000, 'GatewayStore', 'auto endpoint switch: %{public}s -> %{public}s', this.endpointCache, preferred);
    this.autoSelecting = true;
    try {
      await this.switchEndpoint(preferred);
    } finally {
      this.autoSelecting = false;
    }
  }

  /** Turn automatic endpoint selection on/off; turning it on applies it at once. */
  async setAutoSwitch(value: boolean): Promise<void> {
    this.autoSwitch = value;
    const preferences = this.preferences;
    if (preferences !== undefined) {
      await preferences.setAutoSwitch(value);
    }
    if (value) {
      await this.maybeAutoSelect();
    }
    this.publish();
  }

  /**
   * Discover the gateway's LAN listener by probing the current /24 for port
   * 3081. Only runs where a scan can succeed (a private Wi-Fi/Ethernet source,
   * which is exactly what the gateway's LAN listener accepts); every hit is
   * added as a saved LAN address the user can switch to.
   */
  async scanLan(): Promise<number> {
    if (this.scanning) {
      return 0;
    }
    const hint = this.network.hint();
    if (!hint.available || hint.privateIpv4.length === 0) {
      this.notice = '当前不在可扫描的局域网内（需要 Wi-Fi 或以太网）';
      this.noticeIsError = true;
      this.publish();
      return 0;
    }
    this.scanning = true;
    this.notice = '正在扫描局域网…';
    this.noticeIsError = false;
    this.publish();
    try {
      const hosts = subnetProbeHosts(hint.privateIpv4, hint.prefixLength, LAN_SCAN_HOST_LIMIT);
      const found = await this.lanScanner.scan(hosts, DEFAULT_LAN_PORT, LAN_SCAN_TIMEOUT_MS,
        (done: number, total: number) => {
          void done;
          void total;
        });
      for (const host of found) {
        await this.rememberEndpoint(lanUrlFor(host), true);
      }
      this.notice = found.length > 0
        ? `扫描完成：发现 ${found.length} 个局域网地址`
        : '扫描完成：没有发现局域网网关（确认 WebUI 已开启局域网监听）';
      this.noticeIsError = false;
      return found.length;
    } catch (error) {
      this.notice = `扫描失败：${(error as Error).message}`;
      this.noticeIsError = true;
      return 0;
    } finally {
      this.scanning = false;
      this.publish();
    }
  }

  async refreshSettings(): Promise<void> {
    await this.refreshAgentPresets();
    await this.refreshDefaults();
    await this.refreshDefaultModel();
    await this.refreshModelsWithoutSession();
  }

  async unpair(): Promise<void> {
    const preferences = this.preferences;
    const endpoint = preferences === undefined ? '' : await preferences.endpoint();
    this.client.disconnect();
    this.savedToken = '';
    if (endpoint.length > 0) {
      await this.tokens.clear(endpoint);
    }
    // 解除配对 drops the gateway credential, so every address for it goes too:
    // keeping them would only offer reconnects that cannot authenticate.
    for (const saved of this.savedEndpoints) {
      if (saved.url !== endpoint) {
        await this.tokens.clear(saved.url);
      }
    }
    this.savedEndpoints = [];
    if (preferences !== undefined) {
      await preferences.setEndpointRecordsRaw('');
    }
    this.selectedWorkspaceId = '';
    this.selectedSessionId = '';
    this.workspaces = [];
    this.sessions = [];
    this.sessionTitles.clear();
    this.history = [];
    this.conversation = [];
    this.clearHistoryCache();
    this.resetPlan();
    this.publish();
  }

  /** Show a transient notice (used by the chat surface for copy/queue feedback). */
  showNotice(message: string): void {
    this.notice = message;
    this.noticeIsError = false;
    this.publish();
  }

  clearNotice(): void {
    this.notice = '';
    this.noticeIsError = false;
    this.publish();
  }

  // ------------------------------------------------------- DeepSeek balance

  /** Persist (or clear, on an empty string) the DeepSeek key and refresh at once. */
  async saveDeepSeekKey(key: string): Promise<void> {
    const trimmed = key.replace(/^\s+|\s+$/g, '');
    if (trimmed.length === 0) {
      await this.deepSeekKeys.clear();
      this.deepSeekKey = '';
      this.balanceDisplay = '';
      this.balanceError = '';
      this.balanceAt = 0;
      this.balanceFetchedAt = 0;
      this.publish();
      return;
    }
    await this.deepSeekKeys.save(trimmed);
    this.deepSeekKey = trimmed;
    this.balanceFetchedAt = 0;
    await this.refreshDeepSeekBalance(true);
  }

  /**
   * Official balance refresh. Throttled unless forced. A failure keeps the last
   * value and exposes only a short message — the key is never echoed.
   */
  async refreshDeepSeekBalance(force: boolean): Promise<void> {
    if (this.deepSeekKey.length === 0 || this.balanceFetchInFlight) {
      return;
    }
    const now = Date.now();
    if (!force && now - this.balanceFetchedAt < BALANCE_REFRESH_MIN_MS) {
      return;
    }
    this.balanceFetchInFlight = true;
    this.balanceFetchedAt = now;
    try {
      const body = await fetchDeepSeekBalance(this.deepSeekKey);
      const display = formatBalance(parseBalanceSnapshot(body));
      if (display.length === 0) {
        this.balanceError = '接口返回不可用';
      } else {
        this.balanceDisplay = display;
        this.balanceError = '';
        this.balanceAt = Date.now();
      }
    } catch (failure) {
      this.balanceError = (failure as Error).message;
    } finally {
      this.balanceFetchInFlight = false;
      this.publish();
    }
  }

  /**
   * Retry only transport-level failures (`isTransportUnavailable`): a write that
   * never reached the wire is worth another attempt once the lane settles,
   * while a host error must surface immediately.
   */
  private async withConnectRetry<T>(operation: () => Promise<T>): Promise<T> {
    let last: Error | undefined = undefined;
    for (let attempt = 0; attempt < CONNECT_RETRY_DELAYS.length; attempt = attempt + 1) {
      const wait = CONNECT_RETRY_DELAYS[attempt];
      if (wait > 0) {
        await delay(wait);
      }
      try {
        return await operation();
      } catch (failure) {
        const error = failure as Error;
        if (!isTransportUnavailable(error)) {
          throw error;
        }
        last = error;
      }
    }
    throw last !== undefined ? last : new Error('连接不可用');
  }

  async refreshWorkspaces(): Promise<void> {
    await this.withConnectRetry(async (): Promise<void> => {
      const frame = await this.client.request('workspaces', new TypePayload('workspaces'));
      this.workspaces = asWorkspaces(frame);
      if (this.selectedWorkspaceId.length === 0 && this.workspaces.length > 0) {
        this.selectedWorkspaceId = this.workspaces[0].workspaceId ?? '';
      }
      this.publish();
    });
  }

  async selectWorkspace(workspaceId: string): Promise<void> {
    this.selectedWorkspaceId = workspaceId;
    await this.preferences?.setWorkspaceId(workspaceId);
    this.publish();
    await this.refreshSessions();
  }

  async refreshSessions(): Promise<void> {
    await this.withConnectRetry(async (): Promise<void> => {
      const frame = await this.client.request('sessions', new TypePayload('sessions'));
      const incoming = asSessionSummaries(frame);
      // The snapshot is authoritative, but it can lag the live events already
      // folded into the current rows (a brand-new session may still read blank
      // here) and an older title cell must not roll back a live rename.
      this.sessions = mergeSessionRows(this.sessions, incoming);
      applySummaryTitles(this.sessionTitles, this.sessions);
      this.syncTurnActivityFromHost();
      this.applyPlanFromRoster();
      this.publish();
    });
  }

  /**
   * Align the local turn state with the host's own `session.running`. This is
   * what survives a reconnect or an app restart: the events of a turn that ran
   * while the app was away are gone, but the host still reports the session as
   * running. A `false` is trusted only a few seconds after a locally observed
   * start, because the sessions list can be one round-trip older than the send
   * that just succeeded (otherwise the indicator would blink off right after
   * tapping send).
   */
  private syncTurnActivityFromHost(): void {
    for (const session of this.sessions) {
      if ((session.sessionId ?? '') !== this.selectedSessionId) {
        continue;
      }
      if (session.running === true) {
        this.turnActivity = turnRunning(this.turnActivity.startedAt);
      } else if (this.turnActivity.active) {
        const startedAt = this.turnActivity.startedAt;
        const stale = startedAt <= 0 || Date.now() - startedAt > 5000;
        if (stale) {
          this.turnActivity = turnIdle();
        }
      }
      return;
    }
  }

  /** Keep (or refresh) the bounded per-session timeline cache. */
  private cacheHistory(sessionId: string, events: WireSessionEvent[]): void {
    if (sessionId.length === 0) {
      return;
    }
    if (events.length > MAX_CACHED_EVENTS) {
      // Too large to pin; drop any previous copy instead of holding it.
      this.historyCache.delete(sessionId);
      const stale = this.historyCacheOrder.indexOf(sessionId);
      if (stale >= 0) {
        this.historyCacheOrder.splice(stale, 1);
      }
      return;
    }
    this.historyCache.set(sessionId, events);
    const previous = this.historyCacheOrder.indexOf(sessionId);
    if (previous >= 0) {
      this.historyCacheOrder.splice(previous, 1);
    }
    this.historyCacheOrder.push(sessionId);
    while (this.historyCacheOrder.length > MAX_CACHED_SESSIONS) {
      const evicted = this.historyCacheOrder.shift();
      if (evicted !== undefined) {
        this.historyCache.delete(evicted);
      }
    }
  }

  private clearHistoryCache(): void {
    this.historyCache.clear();
    this.historyCacheOrder = [];
  }

  /**
   * Synchronous half of opening a session: adopt the selection, then either
   * restore the cached transcript (instant first paint) or clear it and mark the
   * conversation as loading. Split out so the workspace can push the conversation
   * page immediately and let the data arrive after the push (see
   * `loadSessionData`) instead of blocking navigation on a large history page.
   */
  beginSession(sessionId: string): void {
    if (this.statsRefreshTimer >= 0) {
      clearTimeout(this.statsRefreshTimer);
      this.statsRefreshTimer = -1;
    }
    this.selectedSessionId = sessionId;
    const cached = this.historyCache.get(sessionId);
    if (cached !== undefined && cached.length > 0) {
      // Show the last visit right away; `loadSessionData` still merges the latest.
      this.history = cached.slice();
      this.conversation = projectFromEvents(this.history);
      this.conversationLoading = false;
    } else {
      this.history = [];
      this.conversation = [];
      this.conversationLoading = true;
    }
    // Opening a session adopts the host's truth for it (a turn may already be
    // running, e.g. after a restart); the start time is unknown at this point.
    this.turnActivity = turnIdle();
    this.syncTurnActivityFromHost();
    this.publish();
    this.client.notify('subscribe', new SessionPayload('subscribe', sessionId));
    // Drop every per-session panel before the new session's refresh lands, so
    // the previous conversation's todos/goal/stats/model/permission/commands
    // can never flash under the new one.
    this.todos = null;
    this.todosSeq = -1;
    this.goal = null;
    this.stats = null;
    this.modelGroups = [];
    this.currentModel = { provider: '', model: '', reasoningEffort: '' };
    this.permissionOptions = [];
    this.currentPermission = '';
    this.commandGroups = [];
    this.commandOutcome = null;
    this.resetPlan();
  }

  /**
   * Asynchronous half of opening a session: fetch the initial history page,
   * then the per-session panels. Safe to run detached (the workspace does); the
   * panels are skipped if the user already switched to another session.
   */
  async loadSessionData(sessionId: string): Promise<void> {
    try {
      await this.loadHistory(sessionId, undefined);
    } catch (failure) {
      // Transport failures self-heal on reconnect and would just flash here;
      // only genuine host refusals are worth a banner.
      const error = failure as Error;
      if (!isTransportUnavailable(error)) {
        this.notice = error.message;
        this.noticeIsError = true;
      }
    } finally {
      if (this.selectedSessionId === sessionId) {
        this.conversationLoading = false;
        this.publish();
      }
    }
    if (this.selectedSessionId !== sessionId) {
      return;
    }
    await this.refreshSessionPanels(sessionId);
  }

  async selectSession(sessionId: string): Promise<void> {
    this.beginSession(sessionId);
    await this.preferences?.setLastSessionId(sessionId);
    await this.loadSessionData(sessionId);
  }

  /**
   * Re-sync the open conversation after a gap (page re-shown, app resumed,
   * channel reconnected): re-subscribe and merge the history tail. The merge
   * dedupes by seq, so live-rendered bubbles stay put and only what was missed
   * is added — a long turn that finished while the app was backgrounded shows
   * up here instead of leaving a stale transcript.
   */
  async catchUpConversation(): Promise<void> {
    const sessionId = this.selectedSessionId;
    if (sessionId.length === 0 || !this.client.isConnected) {
      return;
    }
    // A fresh open may still be fetching its first page (`beginSession` +
    // `loadSessionData`); a catch-up now would duplicate that in-flight request.
    // Once it lands, the timestamp guard covers the `onPageShow` that fires
    // immediately after the push.
    if (this.conversationLoading) {
      return;
    }
    if (this.historyLoadedSessionId === sessionId && Date.now() - this.historyLoadedAt < CATCHUP_FRESH_MS) {
      return;
    }
    this.client.notify('subscribe', new SessionPayload('subscribe', sessionId));
    try {
      await this.loadHistory(sessionId, undefined);
    } catch (failure) {
      // Keep whatever is already rendered; the next visit retries.
      void failure;
    }
    this.publish();
  }

  /**
   * Foreground: re-enable reconnect attempts (a timer armed before backgrounding
   * was cancelled) and reconnect if the socket died while the app was away.
   */
  resumeFromBackground(): void {
    this.client.setForeground(true);
    // Re-evaluate the address before reconnecting so a phone that came back on a
    // different network connects straight to the listener it can actually reach.
    this.maybeAutoSelect().then(() => this.connectSaved()).then(async (): Promise<void> => {
      await this.catchUpConversation();
      // The gateway pushes no session-list notification, so a session created
      // or renamed on another client (desktop) only appears when we poll. A
      // foreground return is the natural poll point: the socket is often still
      // up, so no reconnect/bootstrap runs and the roster would stay stale.
      try {
        await this.refreshWorkspaces();
        await this.refreshSessions();
      } catch (failure) {
        // Non-fatal: the workspace page retries and shows its own error line.
        void failure;
      }
    }).catch((error: Error) => {
      void error;
    });
  }

  /**
   * Background: stop reconnect attempts. The OS freezes timers while the app is
   * suspended, and hammering the radio in the background is pointless; the
   * foreground return reconnects instead.
   */
  onBackground(): void {
    this.client.setForeground(false);
  }

  /**
   * tasks / goal / stats / models / permissions / commands are per session and
   * mutually independent; refresh them concurrently. Serially they cost six
   * round trips — invisible on a LAN (~3 ms each) but roughly six times the
   * link latency through a WAN tunnel. Each callee swallows its own failure, so
   * `Promise.all` never rejects here.
   */
  async refreshSessionPanels(sessionId: string): Promise<void> {
    if (sessionId.length === 0) {
      return;
    }
    await Promise.all([
      this.refreshTasks(sessionId),
      this.refreshGoal(sessionId),
      this.refreshSessionStats(sessionId),
      this.refreshModels(sessionId),
      this.refreshPermissions(sessionId),
      this.refreshCommands(sessionId)
    ]);
  }

  // ----------------------------------------------------------- settings (P2)

  async refreshModels(sessionId: string): Promise<void> {
    try {
      const frame = await this.client.request('models', new SessionPayload('models', sessionId));
      if (this.selectedSessionId !== sessionId) {
        return;
      }
      this.modelGroups = modelGroupsFrom(frame);
      this.currentModel = currentModelFrom(frame);
    } catch (failure) {
      void failure;
    }
    this.publish();
  }

  async selectModel(provider: string, model: string, reasoningEffort: string): Promise<void> {
    await this.client.request('select-model',
      new SelectModelPayload(this.selectedSessionId, provider, model,
        reasoningEffort.length > 0 ? reasoningEffort : undefined));
    await this.refreshModels(this.selectedSessionId);
  }

  async refreshPermissions(sessionId: string): Promise<void> {
    try {
      const frame = await this.client.request('permission-options',
        new SessionPayload('permission-options', sessionId));
      if (this.selectedSessionId !== sessionId) {
        return;
      }
      this.permissionOptions = permissionOptionsFrom(frame);
      this.currentPermission = currentPermissionFrom(frame);
    } catch (failure) {
      void failure;
    }
    this.publish();
  }

  async setPermission(name: string): Promise<void> {
    await this.client.request('permission', new PermissionPayload(this.selectedSessionId, name));
    await this.refreshPermissions(this.selectedSessionId);
  }

  async refreshAgentPresets(): Promise<void> {
    try {
      const frame = await this.client.request('agent-presets', new TypePayload('agent-presets'));
      this.agentPresets = agentPresetsFrom(frame);
    } catch (failure) {
      void failure;
    }
    this.publish();
  }

  async refreshDefaults(): Promise<void> {
    try {
      const frame = await this.client.request('defaults', new TypePayload('defaults'));
      this.defaults = {
        agentPresetDefault: frame.agentPresetDefault ?? '',
        permissionDefault: frame.permissionDefault ?? ''
      };
    } catch (failure) {
      void failure;
    }
    this.publish();
  }

  async setDefault(target: string, value: string): Promise<void> {
    await this.client.request('set-default', new SetDefaultPayload(target, value));
    await this.refreshDefaults();
    if (target === 'agent-preset') {
      await this.refreshAgentPresets();
    } else {
      await this.refreshPermissions(this.selectedSessionId);
    }
  }

  async refreshDefaultModel(): Promise<void> {
    try {
      const frame = await this.client.request('default-model', new TypePayload('default-model'));
      const selection = frame.selection;
      this.defaultModel = selection === undefined ? null : {
        provider: selection.provider ?? '',
        model: selection.model ?? '',
        reasoningEffort: selection.reasoningEffort ?? ''
      };
    } catch (failure) {
      void failure;
    }
    this.publish();
  }

  async saveDefaultModel(provider: string, model: string, reasoningEffort: string): Promise<void> {
    await this.client.request('save-default-model',
      new SaveDefaultModelPayload(provider, model, reasoningEffort.length > 0 ? reasoningEffort : undefined));
    await this.refreshDefaultModel();
  }

  async refreshModelsWithoutSession(): Promise<void> {
    try {
      const frame = await this.client.request('models', new TypePayload('models'));
      this.modelGroups = modelGroupsFrom(frame);
    } catch (failure) {
      void failure;
    }
    this.publish();
  }

  // ------------------------------------------------- commands & skills (P2)

  async refreshCommands(sessionId: string): Promise<void> {
    if (sessionId.length === 0) {
      return;
    }
    try {
      const frame = await this.client.request('commands', new CommandsQueryPayload(sessionId, 'zh-CN'));
      if (this.selectedSessionId !== sessionId) {
        return;
      }
      this.commandGroups = commandGroupsFrom(frame);
    } catch (failure) {
      void failure;
    }
    this.publish();
  }

  async executeCommand(line: string): Promise<void> {
    const sessionId = this.selectedSessionId;
    if (sessionId.length === 0) {
      return;
    }
    this.commandOutcome = null;
    this.rememberCommand(line);
    try {
      const frame = await this.client.request('command-execute',
        new CommandExecutePayload(sessionId, line));
      if (this.selectedSessionId !== sessionId) {
        return;
      }
      const result = frame.result;
      const kind = result === undefined ? 'success' : (result.kind ?? 'success');
      const text = result === undefined ? '' : (result.text ?? '');
      this.commandOutcome = {
        line: line,
        kind: kind,
        text: planCommandNotice(this.recentCommandName, kind, text)
      };
    } catch (failure) {
      if (this.selectedSessionId !== sessionId) {
        return;
      }
      this.commandOutcome = {
        line: line,
        kind: 'error',
        text: planCommandNotice(this.recentCommandName, 'error', (failure as Error).message)
      };
    }
    this.publish();
    this.afterCommand();
  }

  /** Apply the host plan projection with an asOfSeq guard (older loses). */
  private applyPlan(projections: Object | undefined): void {
    const plan = planModeOf(projections);
    if (plan === null) {
      return;
    }
    const seq = projectionsSeqOf(projections);
    if (seq < this.planSeq) {
      return;
    }
    this.plan = plan;
    this.planSeq = seq;
  }

  /** Drop per-session plan state (session switch / unpair). */
  private resetPlan(): void {
    this.plan = null;
    this.planSeq = -1;
    this.planReviewRunning = false;
    this.planReviewCommandId = '';
    this.recentCommandName = '';
    this.recentCommandLine = '';
  }

  /** The selected session's roster summary carries its own projection hints. */
  private applyPlanFromRoster(): void {
    for (const session of this.sessions) {
      if ((session.sessionId ?? '') === this.selectedSessionId) {
        this.applyPlan(session.projections);
        return;
      }
    }
  }

  private rememberCommand(line: string): void {
    this.recentCommandLine = line;
    this.recentCommandName = commandNameOf(line);
  }

  /** The host pushes no projection change: re-read the roster after plan commands. */
  private afterCommand(): void {
    if (isPlanFamilyCommand(this.recentCommandName)) {
      // Plan mode also flips the session's sandbox/permission preset (the
      // plugin's hard gate writes it through official permission-presets), and
      // the host pushes neither projection. Re-read both so the plan chip and
      // the permission picker stay truthful.
      void this.refreshSessions();
      void this.refreshPermissions(this.selectedSessionId);
    }
  }

  /**
   * Enter/leave plan mode through the plugin's /plan-toggle. The control is
   * hidden unless the plugin is installed (see planToggleCommand), so a host
   * without it never reaches this.
   */
  async togglePlanMode(): Promise<void> {
    if (planToggleCommand(this.commandGroups) !== 'plan-toggle') {
      return;
    }
    await this.executeCommand('/plan-toggle');
  }

  /** Run the plugin's review - archive - auto-execute pipeline. */
  async runPlanReview(): Promise<void> {
    if (this.planReviewRunning || !hasHostCommand(this.commandGroups, 'plan-review')) {
      return;
    }
    this.planReviewRunning = true;
    this.publish();
    try {
      await this.executeCommand('/plan-review');
    } finally {
      this.planReviewRunning = false;
      this.publish();
    }
  }

  async loadCommandOptions(command: string): Promise<void> {
    const sessionId = this.selectedSessionId;
    if (sessionId.length === 0) {
      return;
    }
    try {
      const frame = await this.client.request('command-options',
        new CommandQueryPayload('command-options', sessionId, command));
      // The user may have switched sessions while this was in flight; the flat
      // option list belongs to the session that asked for it.
      if (this.selectedSessionId !== sessionId) {
        return;
      }
      const options = frame.options;
      const rows: PermissionOptionRow[] = [];
      if (Array.isArray(options)) {
        for (const option of options) {
          const value = option.id ?? '';
          rows.push({ value: value, name: option.label ?? value, selected: option.selected === true });
        }
      }
      this.permissionOptions = rows;
      this.commandOutcome = { line: `/${command}`, kind: 'options', text: '' };
    } catch (failure) {
      if (this.selectedSessionId !== sessionId) {
        return;
      }
      this.commandOutcome = { line: `/${command}`, kind: 'error', text: (failure as Error).message };
    }
    this.publish();
  }

  async selectCommandOption(command: string, optionId: string): Promise<void> {
    await this.client.request('command-select',
      new CommandSelectPayload(this.selectedSessionId, command, optionId));
    await this.loadCommandOptions(command);
  }

  /** Full event timeline for the trajectory page (untrimmed history). */
  async loadTrajectory(sessionId: string): Promise<void> {
    if (sessionId.length === 0) {
      return;
    }
    this.trajectoryLoading = true;
    this.publish();
    try {
      const frame = await this.client.request('history', new TrajectoryPayload(sessionId, 300, 8 * 1024 * 1024));
      // A page that names another session is not this session's trajectory.
      if (!frameTargetsSession(frame, sessionId)) {
        hilog.warn(0x0000, 'GatewayStore', 'dropped trajectory page for %{public}s: frame names %{public}s',
          sessionId, typeof frame.sessionId === 'string' ? frame.sessionId : '');
        this.trajectoryLoading = false;
        this.publish();
        return;
      }
      // A late page from a previous session must not overwrite the open one.
      if (this.selectedSessionId !== sessionId) {
        return;
      }
      this.trajectory = buildTrajectory(asSessionEvents(frame));
    } catch (failure) {
      if (this.selectedSessionId !== sessionId) {
        return;
      }
      this.notice = (failure as Error).message;
      this.noticeIsError = true;
    }
    this.trajectoryLoading = false;
    this.publish();
  }

  /** Edit / remove / steer one queued item (`queue-update`). */
  async updateQueueItem(itemId: string, action: string, text?: string): Promise<void> {
    if (itemId.length === 0 || this.selectedSessionId.length === 0) {
      return;
    }
    const payload = new QueueUpdatePayload(this.selectedSessionId, itemId, action,
      text !== undefined ? text : undefined);
    const frame = await this.client.request('queue-update', payload, itemId);
    if (frame.kind === 'error') {
      throw new Error(frame.message ?? '队列操作失败');
    }
  }

  /**
   * Host-side session search. The deployment may answer with an internal error
   * (broken session persistence), so the caller keeps its local filter as the
   * fallback and this only reports what the host said.
   */
  async searchSessions(query: string): Promise<void> {
    const trimmed = query.replace(/^\s+|\s+$/g, '');
    if (trimmed.length < 2) {
      this.searchResults = [];
      this.searchError = '';
      this.publish();
      return;
    }
    try {
      const frame = await this.client.request('search', new SearchPayload(trimmed));
      if (frame.kind === 'error') {
        throw new Error(frame.message ?? '搜索失败');
      }
      const rows: SearchRow[] = [];
      const items = frame.items;
      if (Array.isArray(items)) {
        for (const raw of items) {
          const record = raw as Record<string, Object>;
          const sessionId = typeof record['sessionId'] === 'string' ? record['sessionId'] as string : '';
          const snippet = typeof record['snippet'] === 'string' ? record['snippet'] as string : '';
          if (sessionId.length > 0) {
            rows.push({ sessionId: sessionId, snippet: snippet });
          }
        }
      }
      this.searchResults = rows;
      this.searchError = '';
    } catch (failure) {
      this.searchResults = [];
      this.searchError = (failure as Error).message;
    }
    this.publish();
  }

  // ------------------------------------------------- images (P4-b)

  /** Open the system picker, then downscale + JPEG-compress every selection. */
  async pickImages(): Promise<void> {
    let uris: string[] = [];
    try {
      const picker = new photoAccessHelper.PhotoViewPicker();
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = Math.max(1, this.imageLimits.maxImages - this.preparedImages.length);
      const result = await picker.select(options);
      uris = result.photoUris ?? [];
    } catch (failure) {
      this.notice = `选择图片失败：${(failure as Error).message}`;
      this.noticeIsError = true;
      this.publish();
      return;
    }
    for (const uri of uris) {
      try {
        await this.prepareImage(uri);
      } catch (failure) {
        this.notice = `图片处理失败：${(failure as Error).message}`;
        this.noticeIsError = true;
      }
    }
    if (!fitsImageBudget(this.preparedImages, '', this.imageLimits)) {
      this.notice = '图片过大或过多：单张压缩后需 ≤ 2.5 MB，且整条消息帧 ≤ 3.5 MB';
      this.noticeIsError = true;
    }
    this.publish();
  }

  private nameOfUri(uri: string): string {
    const parts = uri.split('/');
    const last = parts.length > 0 ? parts[parts.length - 1] : '';
    return last.length > 0 ? last : `image-${Date.now()}.jpg`;
  }

  private async prepareImage(uri: string): Promise<void> {
    const name = this.nameOfUri(uri);
    const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    try {
      const source = image.createImageSource(file.fd);
      const info = await source.getImageInfo();
      const target = compressTarget(info.size.width, info.size.height, this.imageLimits);
      const pixelMap = await source.createPixelMap({
        desiredSize: { width: target.width, height: target.height }
      });
      const packer = image.createImagePacker();
      const packed: ArrayBuffer = await packer.packing(pixelMap, { format: 'image/jpeg', quality: target.quality });
      const base64 = buffer.from(packed).toString('base64');
      const bytes = base64ByteLength(base64);
      this.preparedImages.push({
        name: name.endsWith('.jpg') || name.endsWith('.jpeg') ? name : `${name}.jpg`,
        mediaType: 'image/jpeg',
        bytes: bytes,
        base64: base64,
        sourceUri: uri
      });
      await packer.release();
      await pixelMap.release();
      await source.release();
    } finally {
      try {
        fs.closeSync(file);
      } catch (closeError) {
        void closeError;
      }
    }
  }

  removePreparedImage(index: number): void {
    const next: PreparedImageRow[] = [];
    for (let i = 0; i < this.preparedImages.length; i += 1) {
      if (i !== index) {
        next.push(this.preparedImages[i]);
      }
    }
    this.preparedImages = next;
    this.publish();
  }

  clearPreparedImages(): void {
    this.preparedImages = [];
    this.publish();
  }

  imageBudgetText(): string {
    if (this.preparedImages.length === 0) {
      return '';
    }
    const bytes = outgoingFrameBytes(this.preparedImages, '');
    return `${this.preparedImages.length} 张 · ${(bytes / 1024).toFixed(0)} KB 帧预算`;
  }

  /** Fetch one history image and cache it as a local file. */
  async loadAttachment(sessionId: string, attachmentId: string): Promise<string> {
    const cached = this.attachments.get(attachmentId);
    if (cached !== undefined) {
      return cached;
    }
    try {
      const frame = await this.client.request('attachment',
        new AttachmentPayload(sessionId, attachmentId), attachmentId);
      if (frame.kind === 'error') {
        throw new Error(frame.message ?? '附件读取失败');
      }
      const attachment = frame.attachment;
      const base64 = frame.data ?? '';
      if (attachment === undefined || base64.length === 0) {
        throw new Error('附件响应缺少数据');
      }
      const declaredType = attachment.mediaType ?? 'image/jpeg';
      const suffix = declaredType === 'image/png' ? 'png' : (declaredType === 'image/webp' ? 'webp' : 'jpg');
      const localPath = `${this.filesDir}/att_${attachmentId}.${suffix}`;
      const bytes = buffer.from(base64, 'base64').buffer;
      const file = fs.openSync(localPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, bytes);
      } finally {
        fs.closeSync(file);
      }
      this.attachments.set(attachmentId, localPath);
      this.publish();
      return localPath;
    } catch (failure) {
      this.notice = `附件读取失败：${(failure as Error).message}`;
      this.noticeIsError = true;
      this.publish();
      return '';
    }
  }

  attachmentPathOf(attachmentId: string): string {
    return this.attachments.get(attachmentId) ?? '';
  }

  // ------------------------------------------------- directories (P4)

  async browseDirectories(path?: string): Promise<void> {
    this.directoryLoading = true;
    this.publish();
    try {
      const frame = await this.client.request('directories',
        path === undefined ? new TypePayload('directories') : new DirectoryListPayload(path));
      this.directoryPath = frame.path ?? '';
      this.directoryHome = frame.home ?? this.directoryPath;
      const crumbs: CrumbRow[] = [];
      const rawCrumbs = frame.crumbs;
      if (Array.isArray(rawCrumbs)) {
        for (const crumb of rawCrumbs) {
          crumbs.push({ name: crumb.name ?? '', path: crumb.path ?? '' });
        }
      }
      this.directoryCrumbs = crumbs;
      const entries = frame.entries;
      // The `directories` API only returns folders and omits `kind`, so every
      // entry must be treated as a directory.
      const rows = fileRowsFrom(Array.isArray(entries) ? entries : []);
      for (const row of rows) {
        row.isDirectory = true;
      }
      this.directoryEntries = sortEntries(rows);
    } catch (failure) {
      this.notice = `目录读取失败：${(failure as Error).message}`;
      this.noticeIsError = true;
    }
    this.directoryLoading = false;
    this.publish();
  }

  /** Create a folder and immediately register it as a workspace. */
  async createWorkspaceFolder(parentPath: string, name: string): Promise<string> {
    const created = await this.client.request('directory-create',
      new DirectoryCreatePayload(parentPath, name));
    if (created.kind === 'error') {
      throw new Error(created.message ?? '创建目录失败');
    }
    const target = created.path ?? '';
    const workspace = await this.client.request('workspace-create', new WorkspaceCreatePayload(target));
    if (workspace.kind === 'error') {
      throw new Error(workspace.message ?? '创建工作区失败');
    }
    await this.refreshWorkspaces();
    this.notice = `已创建工作区 ${target}`;
    this.noticeIsError = false;
    this.publish();
    return target;
  }

  /** Adopt an existing directory as a workspace (idempotent on the host). */
  async adoptWorkspace(path: string): Promise<void> {
    const frame = await this.client.request('workspace-create', new WorkspaceCreatePayload(path));
    if (frame.kind === 'error') {
      throw new Error(frame.message ?? '创建工作区失败');
    }
    await this.refreshWorkspaces();
    this.notice = frame.created === false ? '该目录已是工作区' : `已添加工作区 ${path}`;
    this.noticeIsError = false;
    this.publish();
  }

  // ------------------------------------------------- workspace files (P4)

  async browseWorkspaceFiles(path?: string): Promise<void> {
    const sessionId = this.selectedSessionId;
    if (sessionId.length === 0) {
      this.notice = '请先选择一个会话';
      this.noticeIsError = true;
      this.publish();
      return;
    }
    this.workspaceFilesLoading = true;
    this.publish();
    try {
      const requestId = `fl-${Date.now()}`;
      const frame = await this.client.request('file-list', new FileListPayload(sessionId, requestId, path), requestId);
      if (frame.kind === 'error') {
        throw new Error(frame.message ?? '目录读取失败');
      }
      this.workspaceFilePath = frame.path ?? '.';
      const entries = frame.entries;
      this.workspaceFiles = sortEntries(fileRowsFrom(Array.isArray(entries) ? entries : []));
    } catch (failure) {
      this.notice = `文件列表失败：${(failure as Error).message}`;
      this.noticeIsError = true;
    }
    this.workspaceFilesLoading = false;
    this.publish();
  }

  /**
   * List one workspace directory for the composer `@` completion. Unlike
   * `browseWorkspaceFiles` this is a query, not page state: the popover owns
   * the rows and drops stale replies with its own sequence number.
   */
  async listMentionFiles(path: string): Promise<FileEntryRow[]> {
    const sessionId = this.selectedSessionId;
    if (sessionId.length === 0) {
      return [];
    }
    const requestId = `mn-${Date.now()}-${Math.floor(Math.random() * 100000)}`;
    const frame = await this.client.request('file-list', new FileListPayload(sessionId, requestId, path), requestId);
    if (frame.kind === 'error') {
      throw new Error(frame.message ?? '目录读取失败');
    }
    const entries = frame.entries;
    return sortEntries(fileRowsFrom(Array.isArray(entries) ? entries : []));
  }

  filePreviewSnapshot(): FilePreviewRow | null {
    return this.filePreview;
  }

  async clearFilePreview(): Promise<void> {
    this.filePreview = null;
    this.download = null;
    this.publish();
  }

  /**
   * Download one workspace file in chunks, verify its SHA-256 and (for text
   * kinds) load a preview. Chunk offsets always follow the server's reply.
   */
  async openWorkspaceFile(entry: FileEntryRow): Promise<void> {
    const sessionId = this.selectedSessionId;
    if (sessionId.length === 0 || entry.isDirectory) {
      return;
    }
    const requestId = `dl-${Date.now()}`;
    const progress: DownloadProgress = {
      name: entry.name, received: 0, total: entry.bytes, done: false, error: ''
    };
    this.download = progress;
    this.filePreview = null;
    this.publish();
    let handle = -1;
    let localPath = '';
    try {
      const opened = await this.client.request('file-download-open',
        new FileDownloadOpenPayload(requestId, sessionId, entry.path), requestId);
      if (opened.kind === 'error') {
        throw new Error(opened.message ?? '下载失败');
      }
      const transferId = opened.transferId ?? '';
      const total = typeof opened.size === 'number' ? opened.size : entry.bytes;
      progress.total = total;
      const safeName = entry.name.length > 0 ? entry.name : 'download.bin';
      localPath = `${this.filesDir}/downloads_${safeName}`;
      const file = fs.openSync(localPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      handle = file.fd;
      const digest = cryptoFramework.createMd('SHA256');
      let offset = 0;
      let eof = false;
      let expectedSha = '';
      while (!eof) {
        const chunk = await this.client.request('file-download-read',
          new FileDownloadReadPayload(transferId, offset), transferId);
        if (chunk.kind === 'error') {
          throw new Error(chunk.message ?? '下载中断');
        }
        const base64 = chunk.data ?? '';
        const bytes = base64.length > 0 ? buffer.from(base64, 'base64').buffer : new ArrayBuffer(0);
        const size = bytes.byteLength;
        if (size > 0) {
          fs.writeSync(handle, bytes);
          digest.updateSync({ data: new Uint8Array(bytes) });
          offset = chunk.offset === undefined ? offset + size : chunk.offset + size;
        }
        progress.received = offset;
        eof = chunk.eof === true;
        if (eof) {
          expectedSha = chunk.sha256 ?? '';
        }
        this.publish();
      }
      const digestBytes = digest.digestSync();
      const actualSha = hexOf(digestBytes.data);
      const verified = sha256Matches(expectedSha, actualSha);
      progress.done = true;
      this.publish();
      const kind = previewKindOf(entry.name);
      let text = '';
      let truncated = false;
      if (isTextPreview(kind) && fs.accessSync(localPath)) {
        const limit = 200 * 1024;
        const raw = fs.readTextSync(localPath);
        if (raw.length > limit) {
          text = raw.substring(0, limit);
          truncated = true;
        } else {
          text = raw;
        }
      }
      this.filePreview = {
        path: entry.path,
        name: entry.name,
        kind: kind,
        text: text,
        truncated: truncated,
        bytes: progress.total,
        localPath: localPath,
        sha256: actualSha,
        verified: verified
      };
    } catch (failure) {
      progress.error = (failure as Error).message;
      this.notice = `下载失败：${progress.error}`;
      this.noticeIsError = true;
    } finally {
      if (handle >= 0) {
        try {
          fs.closeSync(handle);
        } catch (closeError) {
          void closeError;
        }
      }
    }
    this.publish();
  }

  clearCommandOutcome(): void {
    this.commandOutcome = null;
    this.publish();
  }

  async refreshTasks(sessionId: string): Promise<void> {
    try {
      const frame = await this.client.request('tasks', new SessionPayload('tasks', sessionId));
      if (this.selectedSessionId !== sessionId) {
        return;
      }
      // A slow query must not overwrite a push that already landed.
      if (shouldApplyTodos(frame.asOfSeq, this.todosSeq)) {
        this.todos = todoRowsOf(frame.todos);
        this.todosSeq = frame.asOfSeq ?? this.todosSeq;
      }
    } catch (failure) {
      void failure;
    }
    this.publish();
  }

  async refreshGoal(sessionId: string): Promise<void> {
    try {
      const frame = await this.client.request('goal', new SessionPayload('goal', sessionId));
      if (this.selectedSessionId !== sessionId) {
        return;
      }
      this.goal = this.goalRowOf(frame);
    } catch (failure) {
      void failure;
    }
    this.publish();
  }

  private goalRowOf(frame: WireFrame): GoalRow | null {
    const snapshot = frame.goal;
    if (snapshot === undefined || snapshot === null) {
      return null;
    }
    const definition = snapshot.goal;
    if (definition === undefined || definition === null) {
      return null;
    }
    return {
      id: definition.id ?? '',
      revision: typeof definition.revision === 'number' ? definition.revision : 0,
      objective: definition.objective ?? '',
      phase: definition.phase ?? 'active',
      roundsStarted: typeof snapshot.roundsStarted === 'number' ? snapshot.roundsStarted : 0,
      maxGoalRounds: typeof definition.maxGoalRounds === 'number' ? definition.maxGoalRounds : 0
    };
  }

  /**
   * Ask for a fresh `session-stats` while a turn runs: live events stream in
   * continuously, so this collapses them into at most one query per window and
   * keeps a trailing edge (the last step of a turn is never missed).
   */
  private scheduleStatsRefresh(sessionId: string): void {
    if (sessionId.length === 0 || this.statsRefreshTimer >= 0) {
      return;
    }
    const wait = statsRefreshDelay(Date.now() - this.statsRefreshedAt, STATS_REFRESH_MIN_MS);
    if (wait === 0) {
      void this.refreshSessionStats(sessionId);
      return;
    }
    this.statsRefreshTimer = setTimeout(() => {
      this.statsRefreshTimer = -1;
      this.scheduleStatsRefresh(this.selectedSessionId);
    }, wait);
  }

  async refreshSessionStats(sessionId: string): Promise<void> {
    if (sessionId.length === 0) {
      return;
    }
    this.statsRefreshedAt = Date.now();
    try {
      const frame = await this.client.request('session-stats', new SessionPayload('session-stats', sessionId));
      if (this.selectedSessionId !== sessionId) {
        return;
      }
      const sessionStats = frame.sessionStats;
      if (sessionStats === undefined) {
        this.stats = null;
        this.publish();
        return;
      }
      const pressure = frame.contextPressure;
      const usage = frame.tokenUsage;
      const usedPercent = contextUsedPercent(pressure);
      const totals = readTokenTotals(usage);
      this.stats = {
        turns: sessionStats.turns ?? 0,
        steps: sessionStats.steps ?? 0,
        llmMs: sessionStats.llmMs ?? 0,
        toolMs: sessionStats.toolMs ?? 0,
        ttftMs: sessionStats.ttftMs ?? 0,
        ttftSteps: sessionStats.ttftSteps ?? 0,
        decodeTokens: sessionStats.decodeTokens ?? 0,
        decodeMs: sessionStats.decodeMs ?? 0,
        inputTokens: totals.inputTokens,
        outputTokens: totals.outputTokens,
        cacheReadTokens: totals.cacheReadTokens,
        cacheWriteTokens: totals.cacheWriteTokens,
        cacheHitPercent: cacheHitPercent(totals),
        contextUsedPercent: usedPercent
      };
    } catch (failure) {
      void failure;
    }
    this.publish();
  }

  async editGoal(objective: string): Promise<void> {
    const goal = this.goal;
    if (goal === null) {
      return;
    }
    await this.client.request('goal-edit', new GoalMutationPayload('goal-edit', this.selectedSessionId,
      new GoalRef(goal.id, goal.revision), objective, undefined));
    await this.refreshGoal(this.selectedSessionId);
  }

  async goalAction(type: string): Promise<void> {
    const goal = this.goal;
    if (goal === null) {
      return;
    }
    await this.client.request(type, new GoalMutationPayload(type, this.selectedSessionId,
      new GoalRef(goal.id, goal.revision)));
    if (type === 'goal-clear') {
      this.goal = null;
      this.publish();
      return;
    }
    await this.refreshGoal(this.selectedSessionId);
  }

  async answerQuestion(rpcId: string, answers: DraftAnswer[]): Promise<void> {
    const card = this.questions.get(rpcId);
    if (card === undefined) {
      return;
    }
    const items: QuestionAnswerItem[] = [];
    for (let index = 0; index < card.questions.length; index += 1) {
      const question = card.questions[index];
      const answer = answers[index];
      items.push(new QuestionAnswerItem(question.id, answer.selected, answer.custom));
    }
    // rpcId is the wire correlation (the reply echoes it), so the lane settles
    // exactly even with several sessions' cards in flight.
    await this.client.request('question-answer',
      new QuestionAnswerPayload(rpcId, card.sessionId, items), rpcId);
  }

  async cancelQuestion(rpcId: string): Promise<void> {
    const card = this.questions.get(rpcId);
    if (card === undefined) {
      return;
    }
    await this.client.request('question-cancel', new QuestionCancelPayload(rpcId, card.sessionId), rpcId);
  }

  async respondApproval(rpcId: string, outcome: string): Promise<void> {
    const card = this.approvals.get(rpcId);
    if (card === undefined) {
      return;
    }
    await this.client.request('approval-response',
      new ApprovalResponsePayload(rpcId, card.sessionId, card.approvalId, outcome), rpcId);
  }

  /**
   * Live `event` frames are PROJECTED by the gateway: they carry `type`, `turn`,
   * `step`, `text`, `reasoning` and `toolCalls`, but **no `usage`** (measured
   * 2026-09-11 against `dsh web` 3081: history events carry
   * `usage:{inputTokens,outputTokens,…}`, live ones do not). Per-turn token
   * totals therefore only exist in the history view, so re-read it once a turn
   * ends. Safe to repeat: `loadHistory` rebuilds the conversation from the merged
   * timeline (deduped by `seq`), so usages are never counted twice and the live
   * tail is never dropped. Failures leave the live view untouched.
   */
  private async refreshHistoryAfterTurn(sessionId: string): Promise<void> {
    try {
      await this.loadHistory(sessionId, undefined);
    } catch (failure) {
      void failure;
    }
  }

  async loadHistory(sessionId: string, beforeSeq?: number): Promise<void> {
    const maxMessages = beforeSeq === undefined ? INITIAL_HISTORY_MESSAGES : HISTORY_PAGE_MESSAGES;
    const frame = await this.client.request('history', new HistoryPayload(sessionId, beforeSeq, maxMessages));
    // A page that names another session is not this session's history: adopting it
    // would import that conversation's title, transcript and cache (the session
    // bleed a freshly created session used to exhibit).
    if (!frameTargetsSession(frame, sessionId)) {
      hilog.warn(0x0000, 'GatewayStore', 'dropped history page for %{public}s: frame names %{public}s',
        sessionId, typeof frame.sessionId === 'string' ? frame.sessionId : '');
      return;
    }
    // The user may switch sessions while this page is in flight. Everything below
    // merges into `this.history` / `this.conversation`, which by then belong to
    // the *newly* selected session — applying a stale page would splice the
    // previous session's events into the active transcript and poison its cache.
    // The merge is synchronous, so checking once here is sufficient.
    if (this.selectedSessionId !== sessionId) {
      return;
    }
    // The history projection carries the same `title` cell as the roster, so
    // opening a session names it immediately — even before any live event or
    // `sessions` refresh — while the seq guard rejects an older name.
    this.setSessionTitle(sessionId, projectedTitleOf(frame.projections), projectionsSeqOf(frame.projections));
    this.applyPlan(frame.projections);
    const page = asSessionEvents(frame);
    const outcome = mergeHistoryPage(this.history, page);
    this.history = outcome.events;
    if (outcome.replaced && !outcome.prepended) {
      this.conversation = projectFromEvents(this.history);
    } else {
      let items = this.conversation;
      for (const event of page) {
        const seq = typeof event.seq === 'number' ? event.seq : 0;
        items = applyEvent(items, seq, event);
      }
      this.conversation = items;
    }
    this.historyLoadedSessionId = sessionId;
    this.historyLoadedAt = Date.now();
    this.cacheHistory(sessionId, this.history);
    this.publish();
  }

  /**
   * Create a session. Idempotent by `requestId`; when the gateway lacks the
   * capability we fall back to `message` without `sessionId` (host auto-creates).
   */
  async newSession(): Promise<string> {
    const workspaceId = this.selectedWorkspaceId;
    let sessionId: string;
    if (this.client.canCreateSession) {
      const requestId = `${Date.now()}-${Math.floor(Math.random() * 100000)}`;
      sessionId = await this.client.createSession(requestId, workspaceId.length > 0 ? workspaceId : undefined);
    } else {
      sessionId = await this.client.createSessionViaMessage('你好', workspaceId.length > 0 ? workspaceId : undefined);
    }
    await this.selectSession(sessionId);
    // `sessions` alone is not enough: the home list is scoped by the cached
    // `workspace.sessionIds`, which does not contain a session created a moment
    // ago — the new row would be filtered out until the workspace was refetched.
    await this.refreshWorkspaces();
    await this.refreshSessions();
    return sessionId;
  }

  async sendMessage(text: string, mode: string): Promise<void> {
    if (text.length === 0 && this.preparedImages.length === 0) {
      return;
    }
    const outgoing: OutgoingImage[] = [];
    for (const prepared of this.preparedImages) {
      outgoing.push(new OutgoingImage(prepared.mediaType, prepared.base64, prepared.name));
    }
    const payload = new MessagePayload(text, mode,
      this.selectedSessionId.length > 0 ? this.selectedSessionId : undefined,
      this.selectedWorkspaceId.length > 0 ? this.selectedWorkspaceId : undefined, outgoing);
    this.busy = true;
    this.publish();
    if (this.appContext !== undefined) {
      // Keep the socket and the turn alive while the app is backgrounded.
      this.backgroundTask.start(this.appContext, 'agent turn');
    }
    try {
      const frame = await this.client.request('message', payload);
      if (frame.kind === 'error') {
        // Direct-send failures have no requestType, so surface them verbatim and
        // keep the prepared images so the user can retry after fixing the cause.
        throw new Error(frame.message ?? '发送失败');
      }
      const sessionId = frame.sessionId;
      if (typeof sessionId === 'string' && sessionId.length > 0 && sessionId !== this.selectedSessionId) {
        await this.selectSession(sessionId);
      }
      this.preparedImages = [];
      // The gateway accepted the turn: from here on the agent is working even
      // before the first event arrives (and `busy` is already false again).
      if (!this.turnActivity.active) {
        this.turnActivity = turnRunning(Date.now());
      }
    } finally {
      this.busy = false;
      if (this.appContext !== undefined) {
        this.backgroundTask.stop(this.appContext);
      }
      this.publish();
    }
  }

  async stopGeneration(): Promise<void> {
    if (this.selectedSessionId.length === 0) {
      return;
    }
    await this.client.request('session-cancel', new SessionPayload('session-cancel', this.selectedSessionId));
    // The cancel is acknowledged before the final events; stop the indicator now
    // and let the closing `turn/end` confirm it.
    this.turnActivity = turnIdle();
    this.publish();
  }

  async archiveSession(sessionId: string): Promise<void> {
    await this.client.request('session-archive', new SessionPayload('session-archive', sessionId));
    await this.refreshSessions();
  }

  async renameSession(sessionId: string, title: string): Promise<void> {
    const frame = await this.client.request('session-rename', new RenamePayload(sessionId, title));
    // The reply carries the persisted seq; without one, advance past the
    // stored seq so an older snapshot cannot undo the user's rename.
    const seq = typeof frame.seq === 'number' ? frame.seq : nextTitleSeq(this.sessionTitles, sessionId);
    this.setSessionTitle(sessionId, title, seq);
    this.publish();
  }

  // ---------------------------------------------------------------- callbacks

  handleState(state: GatewayConnectionState, detail: string): void {
    const endpoint = this.status.endpoint;
    this.status = {
      state: state,
      detail: detail,
      endpoint: endpoint,
      capabilities: this.client.capabilitiesSnapshot
    };
    if (state !== GatewayConnectionState.CONNECTED) {
      // No transport, no events: stop claiming the agent is thinking.
      this.turnActivity = turnIdle();
    }
    if (state === GatewayConnectionState.CONNECTED) {
      this.failure = undefined;
      this.connectBootstrapped().then(() => {
        this.publish();
      }).catch((error: Error) => {
        // Bootstrap runs on the socket that just came up; a request rejected here
        // is a transport failure ("连接已断开"), not a user-facing notice. Keep it
        // in `failure` so the next successful connect clears it — writing it to
        // `notice` left a stale green "连接已断开" next to an "已连接" status.
        this.failure = { kind: GatewayFailureKind.NETWORK, detail: error.message };
        this.publish();
      });
    }
    this.publish();
  }

  private bootstrapDone: boolean = false;

  private async connectBootstrapped(): Promise<void> {
    const endpoint = this.preferences === undefined ? this.endpointCache : await this.preferences.endpoint();
    this.endpointCache = endpoint;
    this.status = {
      state: GatewayConnectionState.CONNECTED,
      detail: this.status.detail,
      endpoint: endpoint,
      capabilities: this.client.capabilitiesSnapshot
    };
    if (this.bootstrapDone) {
      // Reconnect: re-subscribe and catch up instead of reloading everything.
      if (this.selectedSessionId.length > 0) {
        this.client.notify('subscribe', new SessionPayload('subscribe', this.selectedSessionId));
        await this.loadHistory(this.selectedSessionId, undefined);
      }
      // B16: the roster is cheap and the home page must never keep an empty
      // list (or a "发送失败" line) just because the socket came back late.
      // Failures stay non-fatal here - the page retries on its next show.
      try {
        await this.refreshWorkspaces();
        await this.refreshSessions();
      } catch (failure) {
        void failure;
      }
      return;
    }
    this.bootstrapDone = true;
    await this.refreshWorkspaces();
    await this.refreshSessions();
    // Global roster: the conversation header resolves the session's agent preset
    // id to its display name (`ptc` → `PTC 模式`) before Settings is ever opened.
    await this.refreshAgentPresets();
    if (this.selectedSessionId.length > 0) {
      await this.selectSession(this.selectedSessionId);
    }
  }

  handleFailure(kind: GatewayFailureKind, detail: string): void {
    this.failure = { kind: kind, detail: detail };
    // A broken transport means no more events: the turn state would otherwise
    // stay "thinking" forever.
    this.turnActivity = turnIdle();
    if (kind === GatewayFailureKind.UPGRADE_REJECTED && this.pairingInFlight) {
      // A failed re-pair must not leave a previously working device offline.
      this.pairingInFlight = false;
      const endpoint = this.endpointCache;
      if (endpoint.length > 0) {
        this.tokens.load(endpoint).then((token: string) => {
          if (token.length > 0) {
            this.notice = '重新配对失败，已回退到已保存的设备凭据';
            return this.connectSaved();
          }
          return undefined;
        }).catch((error: Error) => {
          this.notice = `回退失败：${error.message}`;
        }).then(() => {
          this.publish();
        });
      }
    } else if (this.autoSwitch &&
      (kind === GatewayFailureKind.NETWORK || kind === GatewayFailureKind.UPGRADE_REJECTED)) {
      // The transport died (Wi-Fi off, subnet change, radio loss): re-pick the
      // address now, before the reconnect timer keeps hammering the old one.
      // When the preferred address is already current this is a no-op, so a
      // genuine auth failure cannot make it flap between addresses.
      void this.maybeAutoSelect();
    }
    this.publish();
  }

  handlePaired(token: string): void {
    const endpoint = this.endpointCache.length > 0 ? this.endpointCache : this.status.endpoint;
    this.pairingInFlight = false;
    this.savedToken = token;
    this.tokens.save(endpoint, token).then(() => {
      this.notice = '配对成功，设备凭据已安全保存';
      // The freshly paired address joins the saved list (and gets the token copy).
      return this.rememberEndpoint(endpoint, true);
    }).then(() => {
      this.publish();
    }).catch((error: Error) => {
      this.notice = `配对成功，但保存凭据失败：${error.message}`;
      this.publish();
    });
  }

  handleFrame(frame: WireFrame, raw: string): void {
    void raw;
    const kind = frame.kind ?? '';
    if (kind === 'event') {
      const sessionId = frame.sessionId ?? '';
      const event = frame.event;
      if (event === undefined) {
        return;
      }
      const seq = typeof frame.seq === 'number' ? frame.seq : 0;
      const wireEvent: WireSessionEvent = { type: event.type, seq: seq, time: frame.time, data: event };
      if (sessionId === this.selectedSessionId) {
        this.history = mergeLiveEvent(this.history, wireEvent).events;
        this.conversation = applyEvent(this.conversation, seq, wireEvent);
        this.cacheHistory(this.selectedSessionId, this.history);
        // Live events only: replayed history must not re-light the indicator (a
        // merged `turn/start` from an old turn would look like a running one).
        this.turnActivity = applyTurnActivity(this.turnActivity, event.type ?? '',
          typeof frame.time === 'number' ? frame.time : 0, Date.now());
        // The host pushes no stats projection: without this the run-time bar
        // would stay frozen for the whole turn and jump at `turn/end`.
        if (this.turnActivity.active) {
          this.scheduleStatsRefresh(sessionId);
        }
      }
      if ((event.type ?? '') === 'turn/end' && sessionId === this.selectedSessionId) {
        this.refreshSessionStats(sessionId);
        // Live `event` frames carry no `usage` (see `refreshHistoryAfterTurn`).
        void this.refreshHistoryAfterTurn(sessionId);
      }
      if ((event.type ?? '') === 'session/title') {
        this.setSessionTitle(sessionId, titleOf(wireEvent), seq);
      }
      const eventType = event.type ?? '';
      if (eventType === 'command/run') {
        const commandName = typeof event.name === 'string' ? event.name : '';
        this.recentCommandName = commandName;
        if (commandName === 'plan-review') {
          this.planReviewRunning = true;
          this.planReviewCommandId = typeof event.commandId === 'string' ? event.commandId : '';
        }
      } else if (eventType === 'command/done') {
        const commandId = typeof event.commandId === 'string' ? event.commandId : '';
        if (commandId.length > 0 && commandId === this.planReviewCommandId) {
          this.planReviewRunning = false;
          this.planReviewCommandId = '';
          if (sessionId === this.selectedSessionId) {
            const doneKind = typeof event.outcome === 'string' ? event.outcome : 'success';
            const doneText = typeof event.text === 'string' ? event.text : '';
            this.commandOutcome = {
              line: this.recentCommandLine,
              kind: doneKind,
              text: planCommandNotice(this.recentCommandName, doneKind, doneText)
            };
          }
        }
        if (isPlanFamilyCommand(this.recentCommandName)) {
          void this.refreshSessions();
          void this.refreshPermissions(sessionId);
        }
      }
      // Fold the event into the roster row so the home list reflects activity
      // without waiting for the next `sessions` round trip.
      applyEventToRoster(this.sessions, sessionId, wireEvent);
      this.publish();
      return;
    }
    if (kind === 'question-requested') {
      const rpcId = frame.rpcId ?? '';
      const sessionId = frame.sessionId ?? '';
      if (rpcId.length > 0) {
        const questions = Array.isArray(frame.questions) ? frame.questions : [];
        this.questions.set(rpcId, {
          rpcId: rpcId,
          sessionId: sessionId,
          questions: toQuestionViews(questions),
          replay: frame.replay === true
        });
      }
      this.publish();
      return;
    }
    if (kind === 'question-resolved') {
      const rpcId = frame.rpcId ?? '';
      if (rpcId.length > 0) {
        this.questions.delete(rpcId);
      }
      this.publish();
      return;
    }
    if (kind === 'approval-requested') {
      const rpcId = frame.rpcId ?? '';
      const approvalId = frame.approvalId ?? '';
      if (rpcId.length > 0) {
        this.approvals.set(rpcId, {
          rpcId: rpcId,
          sessionId: frame.sessionId ?? '',
          approvalId: approvalId,
          toolName: frame.toolName ?? '',
          reason: frame.reason ?? '',
          callId: frame.callId ?? '',
          replay: frame.replay === true
        });
      }
      this.publish();
      return;
    }
    if (kind === 'approval-resolved') {
      const rpcId = frame.rpcId ?? '';
      if (rpcId.length > 0) {
        this.approvals.delete(rpcId);
      }
      this.publish();
      return;
    }
    if (kind === 'tasks-updated') {
      // The gateway pushes every session's projection; only the open one owns
      // the flat todos/goal fields, otherwise another conversation's task list
      // appears under this session. An empty sessionId means a legacy push.
      const pushedSession = frame.sessionId ?? '';
      if (pushedSession.length > 0 && pushedSession !== this.selectedSessionId) {
        return;
      }
      // PROTOCOL.md 6.1: higher `asOfSeq` wins; drop stale pushes.
      if (!shouldApplyTodos(frame.asOfSeq, this.todosSeq)) {
        return;
      }
      this.todos = todoRowsOf(frame.todos);
      this.todosSeq = frame.asOfSeq ?? this.todosSeq;
      this.publish();
      return;
    }
    if (kind === 'goal-updated') {
      const pushedSession = frame.sessionId ?? '';
      if (pushedSession.length > 0 && pushedSession !== this.selectedSessionId) {
        return;
      }
      this.goal = this.goalRowOf(frame);
      this.publish();
      return;
    }
    if (kind === 'session-archives') {
      this.archivedSessionIds = Array.isArray(frame.archivedSessionIds) ? frame.archivedSessionIds : [];
      this.publish();
      return;
    }
    if (kind === 'session-title-changed') {
      const sessionId = frame.sessionId ?? '';
      const seq = typeof frame.seq === 'number' ? frame.seq : nextTitleSeq(this.sessionTitles, sessionId);
      this.setSessionTitle(sessionId, frame.title ?? '', seq);
      this.publish();
      return;
    }
    if (kind === 'session-queues') {
      this.queues = new Map<string, WireQueueItem[]>();
      const queues = frame.queues;
      if (queues !== undefined && queues !== null) {
        const record = queues as Record<string, Object>;
        for (const sessionId of Object.keys(record)) {
          const list = record[sessionId];
          if (Array.isArray(list)) {
            const items: WireQueueItem[] = [];
            for (const item of list as Object[]) {
              items.push(item as WireQueueItem);
            }
            this.queues.set(sessionId, items);
          }
        }
      }
      this.publish();
      return;
    }
    if (kind === 'session-queue') {
      const sessionId = frame.sessionId ?? '';
      if (sessionId.length > 0) {
        this.queues.set(sessionId, asQueueItems(frame));
      }
      this.publish();
      return;
    }
    if (kind === 'session-renamed') {
      const sessionId = frame.sessionId ?? '';
      const seq = typeof frame.seq === 'number' ? frame.seq : nextTitleSeq(this.sessionTitles, sessionId);
      this.setSessionTitle(sessionId, frame.title ?? '', seq);
      this.publish();
    }
  }
}

/** Lower-case hex of a digest byte array. */
function hexOf(bytes: Uint8Array): string {
  let hex = '';
  for (let index = 0; index < bytes.length; index += 1) {
    const value = bytes[index].toString(16);
    hex += value.length === 1 ? `0${value}` : value;
  }
  return hex;
}
