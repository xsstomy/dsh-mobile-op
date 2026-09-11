/**
 * Conversation page: glass top bar + 对话/轨迹 segmented control, message list,
 * run pill and the glass composer (upstream: conversation-dark.png).
 */
import { KeyboardAvoidMode, router } from '@kit.ArkUI';
import { GatewayStore } from '../store/GatewayStore';
import { UI_KEY, UiSnapshot, emptyUiSnapshot, activeWorkspace, sessionPresetId, agentPresetLabel } from '../store/UiState';
import { AppColors, AppFont, AppRadius, AppSpacing, AppShadow, Glass } from '../common/Constants';
import {
  ConversationItem, ConversationRole, conversationListItemCount, isTurnTail, shouldShowThinking,
  toolSummaryText, turnTimeSpan, turnTokenTotals
} from '../projection/Conversation';
import { WireImageAttachment } from '../protocol/Types';
import { AttachmentRow } from '../store/UiState';
import { PreparedImageRow } from '../protocol/Images';
import { HarnessBackground } from '../common/HarnessBackground';
import { messageContentView } from '../views/MessageContent';
import { HumanQuestionCard } from '../views/HumanQuestionCard';
import { ApprovalCard } from '../views/ApprovalCard';
import { TaskGoalPanel } from '../views/TaskGoalPanel';
import { SessionStatsBar } from '../views/SessionStatsBar';
import { TodoPanel } from '../views/TodoPanel';
import { ThinkingIndicator } from '../views/ThinkingIndicator';
import { ApprovalCardRow, QuestionCardRow } from '../store/UiState';
import {
  CommandGroupRow, CommandItemRow, ModelGroupRow, ModelRow, PermissionOptionRow, ReasoningEffortRow,
  filterCommands, modelRowFor, permissionLabel, slashQueryOf
} from '../protocol/Settings';
import { QueueRow, canSteer, placementLabel } from '../protocol/Queue';
import { copyToClipboard, vibrateShort } from '../common/Platform';
import { turnFooterText } from '../common/Format';
import { FileEntryRow } from '../protocol/Files';
import {
  ActiveAtToken, activeAtTokenInDraft, applyMention, filterMentionEntries, formatFileMention, mentionTargetOf
} from '../protocol/Mentions';

/** Slash-command menu cap; a long command/skill list scrolls inside the popover. */
const SLASH_MENU_MAX_HEIGHT = 260;

/** `@` completion cap; a long candidate list scrolls inside the popover. */
const MENTION_MENU_MAX_HEIGHT = 240;

/** Composer input: one line at rest, growing to a few lines before scrolling. */
const COMPOSER_INPUT_MIN_HEIGHT = 26;
const COMPOSER_INPUT_MAX_HEIGHT = 110;

@Entry
@Component
struct ConversationPage {
  @StorageLink(UI_KEY) @Watch('onSnapshotChanged') ui: UiSnapshot = emptyUiSnapshot();
  /** Status/navigation bar insets (vp) published by WindowChrome. */
  @StorageProp('gwInsetTop') insetTop: number = 0;
  @StorageProp('gwInsetBottom') insetBottom: number = 0;
  @State draft: string = '';
  @State mode: string = 'queue';
  @State error: string = '';
  @State loadingMore: boolean = false;
  @State tab: string = 'conversation';
  @State panelOpen: boolean = false;
  @State sheetOpen: boolean = false;
  @State sheetMode: string = 'more';
  @State pickerMode: string = 'model';
  @State pickerTitle: string = '';
  @State renameOpen: boolean = false;
  @State renameDraft: string = '';
  @State expandedReasoning: string[] = [];
  @State editingQueueId: string = '';
  @State queueDraft: string = '';
  @State atBottom: boolean = true;
  /** Guards the composer's quick "new session" button against double taps. */
  @State creatingSession: boolean = false;
  /** `@` completion popover: candidates come from `file-list` of the session cwd. */
  @State mentionOpen: boolean = false;
  @State mentionRows: FileEntryRow[] = [];
  @State mentionError: string = '';
  /** Caret offset inside `draft` (the @ token ends here). */
  private caret: number = 0;
  private mentionToken: ActiveAtToken | undefined = undefined;
  /** Monotonic request guard; a stale directory reply must not overwrite a newer one. */
  private mentionSeq: number = 0;
  private mentionDirectory: string = '';
  private mentionRowsRaw: FileEntryRow[] = [];
  private draftController: TextAreaController = new TextAreaController();
  private requestedAttachments: string[] = [];
  private store: GatewayStore = GatewayStore.current;
  private scroller: Scroller = new Scroller();
  private lastItemCount: number = 0;
  /** Edge-triggered follow for the thinking indicator (it adds no item). */
  private lastTurnActive: boolean = false;
  /** Edge-triggered follow for a newly arrived question/approval card. */
  private lastPendingCount: number = 0;

  aboutToAppear(): void {
    // Compress the page when the keyboard opens so the composer stays visible
    // right above it (the default OFFSET mode pushes the whole page off screen).
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
  }

  /**
   * Coming back to this page (from Settings, or from the background) must not
   * show a stale transcript: pull the history tail. Events are merged by seq, so
   * this only fills the gap left by a missed live stream.
   */
  onPageShow(): void {
    this.store.catchUpConversation();
  }

  /**
   * Follow the tail: scroll to the newest bubble when the timeline grows, or when
   * the agent starts working (the indicator is a list item too, but it does not
   * change the conversation length).
   */
  onSnapshotChanged(): void {
    const count = this.ui.conversation.length;
    const working = this.ui.turnActive;
    const pending = this.ui.approvals.length + this.ui.questions.length;
    if (pending > this.lastPendingCount) {
      // A question/approval card can be taller than the screen and its answer
      // controls live at its END, so align the card's FIRST line to the viewport
      // and let the user read down to them (following the tail would hide the
      // question text they were asked to review).
      this.scroller.scrollToIndex(this.firstPendingIndex(), true, ScrollAlign.START);
    } else if (count > this.lastItemCount || (working && !this.lastTurnActive)) {
      this.scroller.scrollEdge(Edge.Bottom);
    }
    this.lastItemCount = count;
    this.lastTurnActive = working;
    this.lastPendingCount = pending;
    this.fetchMissingAttachments();
  }

  /** 0-based List index of the first pending approval/question card. */
  private firstPendingIndex(): number {
    return conversationListItemCount(this.ui.conversation, this.ui.turnActive, 0);
  }

  /** History images are fetched lazily, once per attachment id. */
  private fetchMissingAttachments(): void {
    const sessionId = this.ui.activeSessionId;
    if (sessionId.length === 0) {
      return;
    }
    for (const item of this.ui.conversation) {
      for (const image of item.images) {
        const attachmentId = image.attachmentId ?? '';
        if (attachmentId.length === 0 || this.requestedAttachments.indexOf(attachmentId) >= 0) {
          continue;
        }
        let cached = false;
        for (const row of this.ui.attachments) {
          if (row.attachmentId === attachmentId) {
            cached = true;
          }
        }
        if (cached) {
          continue;
        }
        this.requestedAttachments.push(attachmentId);
        this.store.loadAttachment(sessionId, attachmentId);
      }
    }
  }

  private attachmentPath(attachmentId: string): string {
    for (const row of this.ui.attachments) {
      if (row.attachmentId === attachmentId) {
        return row.localPath;
      }
    }
    return '';
  }

  private async send(): Promise<void> {
    const text = this.draft.replace(/^\s+|\s+$/g, '');
    // The protocol accepts text OR images, so an image-only message is valid.
    if (text.length === 0 && this.ui.preparedImages.length === 0) {
      return;
    }
    this.error = '';
    try {
      await this.store.sendMessage(text, this.mode);
      this.draft = '';
      this.closeMention();
      // Drop the caret so the soft keyboard folds away instead of covering the
      // transcript the user just sent.
      this.getUIContext().getFocusController().clearFocus();
      vibrateShort();
      this.scroller.scrollEdge(Edge.Bottom);
    } catch (failure) {
      // Keep the draft and the images so the user can retry.
      this.error = (failure as Error).message;
    }
  }

  private async stop(): Promise<void> {
    this.error = '';
    try {
      await this.store.stopGeneration();
    } catch (failure) {
      this.error = (failure as Error).message;
    }
  }

  /**
   * 快速新建会话：在当前工作区建一个空会话并切过去。只在成功后清空草稿/待发
   * 图片，失败时保留用户已经输入的内容。
   */
  private async createNewSession(): Promise<void> {
    if (this.creatingSession) {
      return;
    }
    this.creatingSession = true;
    this.error = '';
    try {
      await this.store.newSession();
      this.draft = '';
      this.expandedReasoning = [];
      this.store.clearPreparedImages();
    } catch (failure) {
      this.error = (failure as Error).message;
    }
    this.creatingSession = false;
  }

  // ------------------------------------------------------- @ file mentions

  /** Hide the `@` popover and invalidate any in-flight candidate request. */
  private closeMention(): void {
    this.mentionSeq += 1;
    this.mentionOpen = false;
    this.mentionRows = [];
    this.mentionError = '';
    this.mentionToken = undefined;
    this.mentionDirectory = '';
    this.mentionRowsRaw = [];
  }

  /**
   * Recompute the `@` token at the caret and (re)load its candidates. The file
   * list is per-directory, so the same directory reuses the cached rows and only
   * re-filters while the user types the name.
   */
  private refreshMention(): void {
    if (slashQueryOf(this.draft) !== null) {
      this.closeMention();
      return;
    }
    const token = activeAtTokenInDraft(this.draft, this.caret);
    if (token === undefined) {
      this.closeMention();
      return;
    }
    this.mentionToken = token;
    this.mentionOpen = true;
    const target = mentionTargetOf(token.query);
    if (target.directory === this.mentionDirectory && this.mentionRowsRaw.length > 0) {
      this.mentionRows = filterMentionEntries(this.mentionRowsRaw, target.prefix);
      return;
    }
    this.mentionDirectory = target.directory;
    this.mentionRowsRaw = [];
    this.mentionRows = [];
    this.mentionError = '';
    this.mentionSeq += 1;
    const seq = this.mentionSeq;
    this.store.listMentionFiles(target.directory).then((rows: FileEntryRow[]) => {
      if (seq !== this.mentionSeq) {
        return;
      }
      this.mentionRowsRaw = rows;
      this.mentionRows = filterMentionEntries(rows, target.prefix);
    }).catch((failure: Error) => {
      if (seq !== this.mentionSeq) {
        return;
      }
      this.mentionRows = [];
      this.mentionError = failure.message;
    });
  }

  private onDraftChanged(value: string): void {
    this.draft = value;
    // `onTextSelectionChange` refines this; typing normally leaves the caret at the end.
    this.caret = value.length;
    this.refreshMention();
  }

  private onCaretChanged(selectionStart: number, selectionEnd: number): void {
    const next = selectionEnd >= 0 ? selectionEnd : selectionStart;
    if (next === this.caret) {
      return;
    }
    this.caret = next;
    this.refreshMention();
  }

  /** Splice the picked path over the active token (directories stay open). */
  private selectMention(entry: FileEntryRow): void {
    const token = this.mentionToken;
    if (token === undefined) {
      return;
    }
    const mention = formatFileMention(entry.path, entry.isDirectory, token.quoted);
    if (mention === undefined) {
      return;
    }
    // A file mention is terminated by a space, otherwise the caret sitting at
    // its end would immediately re-open the completion for the path just picked.
    const insertion = entry.isDirectory ? mention : `${mention} `;
    const spliced = applyMention(this.draft, this.caret, token, insertion);
    this.draft = spliced.text;
    this.caret = spliced.caret;
    this.draftController.caretPosition(spliced.caret);
    if (entry.isDirectory) {
      // Keep the popover open so the user can descend into the directory.
      this.mentionDirectory = '';
      this.mentionRowsRaw = [];
      this.refreshMention();
    } else {
      this.closeMention();
    }
  }

  private isReasoningExpanded(key: string): boolean {
    return this.expandedReasoning.indexOf(key) >= 0;
  }

  private toggleReasoning(key: string): void {
    const next: string[] = [];
    let removed = false;
    for (const value of this.expandedReasoning) {
      if (value === key) {
        removed = true;
      } else {
        next.push(value);
      }
    }
    if (!removed) {
      next.push(key);
    }
    this.expandedReasoning = next;
  }

  private turnTokens(turn: number): number {
    const totals = turnTokenTotals(this.ui.conversation, turn);
    return totals.input + totals.output;
  }

  private turnFooterLabel(item: ConversationItem): string {
    const span = turnTimeSpan(this.ui.conversation, item.turn);
    return turnFooterText(this.turnTokens(item.turn), span.startedAt, span.endedAt, Date.now());
  }

  private async loadOlder(): Promise<void> {
    const sessionId = this.ui.activeSessionId;
    if (sessionId.length === 0 || this.loadingMore) {
      return;
    }
    this.loadingMore = true;
    const items = this.ui.conversation;
    if (items.length > 0) {
      try {
        await this.store.loadHistory(sessionId, items[0].time);
      } catch (failure) {
        this.error = (failure as Error).message;
      }
    }
    this.loadingMore = false;
  }

  @Builder
  glassCircle(glyph: Resource, action: () => void) {
    // Stack centres the glyph; sizing the SymbolGlyph itself leaves it in the
    // top-left corner of the circle.
    Stack() {
      SymbolGlyph(glyph).fontSize(18).fontColor([AppColors.DARK_INK])
    }
    .width(38)
    .height(38)
    .borderRadius(AppRadius.CIRCLE)
    .backgroundColor(Glass.FILL)
    .border({ width: Glass.BORDER_WIDTH, color: Glass.BORDER })
      .backgroundBlurStyle(BlurStyle.COMPONENT_THICK, Glass.blurOptions())
      .onClick(action)
  }

  @Builder
  topBar() {
    Column({ space: 2 }) {
      // Line 1: navigation + the workspace name. It used to share the row with
      // the run mode, which squeezed a long name into `dsh-…`; it now owns the
      // whole width between the back button and the two trailing actions.
      Row({ space: 10 }) {
        this.glassCircle($r('sys.symbol.arrow_left'), () => {
          router.back();
        })
        Text(this.workspaceTitle())
          .fontSize(AppFont.SUBTITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColors.DARK_INK)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        // One-tap "new session" in the header, kept away from the composer where
        // a `+` reads as "add attachment" (C18); ⋯ sheet keeps the same action.
        this.glassCircle($r('sys.symbol.square_and_pencil'), () => {
          this.createNewSession();
        })
        this.glassCircle($r('sys.symbol.ellipsis_message_1'), () => {
          this.openSheet('more');
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      // Line 2: the session's own title (aligned under the workspace name) and
      // how the session runs (connection + agent preset).
      Row({ space: 8 }) {
        Text(this.sessionTitle())
          .fontSize(AppFont.CAPTION)
          .fontColor(AppColors.INK_WEAK)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Row({ space: 6 }) {
          Circle({ width: 7, height: 7 })
            .fill(this.ui.connection === 'connected' ? AppColors.SUCCESS : AppColors.WARN)
          Text(this.modeLabel())
            .fontSize(AppFont.CAPTION)
            .fontColor(AppColors.INK_WEAK)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .width('100%')
      // 38vp circle + 10vp gap: keeps the title under the workspace name.
      .padding({ left: 48, right: 2 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  private workspaceTitle(): string {
    const workspace = activeWorkspace(this.ui);
    if (workspace !== undefined && workspace.title.length > 0) {
      return workspace.title;
    }
    return '未选择工作区';
  }

  private sessionTitle(): string {
    if (this.ui.activeSessionTitle.length > 0) {
      return this.ui.activeSessionTitle;
    }
    return this.ui.activeSessionId.length > 0 ? '新会话' : '未选择会话';
  }

  /** Connection state + agent preset (`PTC 模式`), matching the Android header. */
  private modeLabel(): string {
    const id = sessionPresetId(this.ui);
    const preset = agentPresetLabel(this.ui, id);
    const state = this.ui.busy ? '生成中' : (this.ui.connection === 'connected' ? '已连接' : this.ui.connection);
    return preset.length > 0 ? `${state} · ${preset}` : state;
  }

  /**
   * Sheet header, drawn inside the content flow. bindSheet's built-in close
   * button floats over the top-right of the content, which covered the first
   * setting row; with `showClose: false` this header owns both the title and
   * the dismiss action, so they can never overlap the rows below.
   */
  @Builder
  sheetHeader(title: string) {
    Row() {
      Text(title)
        .fontSize(AppFont.HEADING)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColors.DARK_INK)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Stack() {
        SymbolGlyph($r('sys.symbol.xmark')).fontSize(16).fontColor([AppColors.DARK_INK])
      }
      .id('sheetCloseButton')
      .width(34)
      .height(34)
      .backgroundColor(Glass.FILL_STRONG)
      .borderRadius(AppRadius.CIRCLE)
      .border({ width: Glass.BORDER_WIDTH, color: Glass.BORDER_SOFT })
      .onClick(() => {
        this.sheetOpen = false;
      })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  panelsSheet() {
    Column({ space: AppSpacing.GAP }) {
      this.sheetHeader('会话')
      TaskGoalPanel({ todos: this.ui.todos, goal: this.ui.goal })
      Text('设置')
        .fontSize(AppFont.LABEL)
        .fontColor(AppColors.DARK_INK)
        .textAlign(TextAlign.Center)
        .width('100%')
        .height(44)
        .backgroundColor(Glass.FILL)
        .borderRadius(AppRadius.CARD)
        .border({ width: Glass.BORDER_WIDTH, color: Glass.BORDER_SOFT })
        .onClick(() => {
          this.panelOpen = false;
          router.pushUrl({ url: 'pages/SettingsPage' });
        })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(AppSpacing.PAGE)
    .onAppear(() => {
      this.store.refreshSessionPanels(this.ui.activeSessionId);
    })
  }

  @Builder
  segmented() {
    Row() {
      Text('对话')
        .fontSize(AppFont.LABEL)
        .fontColor(AppColors.DARK_INK)
        .textAlign(TextAlign.Center)
        .layoutWeight(1)
        .height(34)
        .borderRadius(AppRadius.PILL)
        .backgroundColor(this.tab === 'conversation' ? Glass.FILL_STRONG : '#00000000')
        .border({
          width: this.tab === 'conversation' ? Glass.BORDER_WIDTH : 0,
          color: Glass.BORDER
        })
        .onClick(() => {
          this.tab = 'conversation';
        })
      Text('轨迹')
        .fontSize(AppFont.LABEL)
        .fontColor(AppColors.INK_WEAK)
        .textAlign(TextAlign.Center)
        .layoutWeight(1)
        .height(34)
        .borderRadius(AppRadius.PILL)
        .onClick(() => {
          router.pushUrl({ url: 'pages/TrajectoryPage' });
        })
    }
    .width('100%')
    .padding(3)
    .backgroundColor(Glass.FILL_SUBTLE)
    .borderRadius(AppRadius.PILL)
    .border({ width: Glass.BORDER_WIDTH, color: Glass.BORDER_SOFT })
  }

  /**
   * Tail of the turn: `1.2k tokens · 用时 12.3s · 20:15`. A @Builder (not a
   * custom component) so the label is recomputed from `this.ui` on every
   * repaint; the pure formatter is unit-tested in `common/Format.ets`.
   */
  @Builder
  turnFooter(item: ConversationItem) {
    if (this.turnFooterLabel(item).length > 0) {
      Text(this.turnFooterLabel(item))
        .fontSize(10)
        .fontColor(AppColors.INK_WEAK)
        .width('100%')
        .padding({ top: 2 })
    }
  }

  /**
   * The item the ForEach generator captured is a SNAPSHOT: ArkUI reuses a keyed
   * child as-is, so reads of `item.*` keep the values from the moment the key was
   * created (measured: a finished turn still showed `生成中…` +
   * `1 个工具 · 进行中`). Re-read the current item from the observed snapshot, so
   * every `this.ui.conversation` publish refreshes the bubble.
   */
  private currentItem(item: ConversationItem, index: number): ConversationItem {
    const items = this.ui.conversation;
    if (index >= 0 && index < items.length && items[index].key === item.key) {
      return items[index];
    }
    return item;
  }

  @Builder
  messageBubble(item: ConversationItem, index: number) {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(item.role === ConversationRole.USER ? '你' : (item.role === ConversationRole.ASSISTANT ? 'Agent' : item.role))
          .fontSize(AppFont.CAPTION)
          .fontColor(item.role === ConversationRole.USER ? AppColors.MIST : AppColors.INK_WEAK)
        if (this.currentItem(item, index).streaming) {
          Text('生成中…').fontSize(AppFont.CAPTION).fontColor(AppColors.OK)
        }
        // One-line stand-in for the tool cards (count + total duration); not
        // expandable, the call details stay on the 轨迹 page.
        if (toolSummaryText(this.currentItem(item, index)).length > 0) {
          Text(toolSummaryText(this.currentItem(item, index)))
            .fontSize(AppFont.CAPTION)
            .fontColor(AppColors.INK_WEAK)
        }
      }
      .width('100%')

      // Reasoning is device-local: off (default) renders nothing at all, on keeps
      // the collapsible block below.
      if (this.ui.showReasoning && this.currentItem(item, index).reasoning.length > 0) {
        Column({ space: 4 }) {
          Row({ space: 6 }) {
            Text('思考过程').fontSize(AppFont.CAPTION).fontColor(AppColors.PURPLE)
            Text(`${this.currentItem(item, index).reasoning.length} 字`).fontSize(10).fontColor(AppColors.INK_WEAK)
            Text(this.isReasoningExpanded(item.key) ? '收起' : '展开')
              .fontSize(10)
              .fontColor(AppColors.MIST)
              .layoutWeight(1)
              .textAlign(TextAlign.End)
          }
          .width('100%')
          .onClick(() => {
            this.toggleReasoning(item.key);
          })
          if (this.isReasoningExpanded(item.key)) {
            Text(this.currentItem(item, index).reasoning)
              .fontSize(AppFont.CAPTION)
              .fontColor(AppColors.INK_WEAK)
              .width('100%')
          }
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
      }

      if (this.currentItem(item, index).images.length > 0) {
        Column({ space: 6 }) {
          ForEach(this.currentItem(item, index).images, (image: WireImageAttachment) => {
            if (this.attachmentPath(image.attachmentId ?? '').length > 0) {
              Image(`file://${this.attachmentPath(image.attachmentId ?? '')}`)
                .width('100%')
                .constraintSize({ maxHeight: 360 })
                .objectFit(ImageFit.Contain)
                .backgroundColor(Glass.CODE_FILL)
                .borderRadius(AppRadius.CARD_SMALL)
            } else {
              Text(`图片加载中… ${image.name ?? ''} · ${Math.round((image.bytes ?? 0) / 1024)} KB`)
                .fontSize(10)
                .fontColor(AppColors.INK_WEAK)
                .width('100%')
                .padding(10)
                .backgroundColor(Glass.CODE_FILL)
                .borderRadius(AppRadius.CARD_SMALL)
            }
          }, (image: WireImageAttachment) => image.attachmentId ?? '')
        }
        .width('100%')
      }

      if (this.currentItem(item, index).text.length > 0) {
        messageContentView(this.currentItem(item, index).text, false)
      }

      // Tail of the turn: how much it cost and when it finished.
      if (isTurnTail(this.ui.conversation, index)) {
        this.turnFooter(this.currentItem(item, index))
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .gesture(LongPressGesture().onAction(() => {
      this.copyMessage(item);
    }))
    .padding({
      left: item.role === ConversationRole.USER ? 14 : 4,
      right: item.role === ConversationRole.USER ? 14 : 4,
      top: 12,
      bottom: 12
    })
    .backgroundColor(item.role === ConversationRole.USER ? Glass.FILL : '#00000000')
    .border({
      width: item.role === ConversationRole.USER ? Glass.BORDER_WIDTH : 0,
      color: Glass.BORDER_SOFT
    })
    .borderRadius(AppRadius.CARD)
  }

  @Builder
  runPill() {
    Row({ space: 6 }) {
      Text(`${this.ui.conversation.length} 条 · 排队 ${this.ui.queueCount}`)
        .fontSize(AppFont.CAPTION)
        .fontColor(AppColors.INK_WEAK)
    }
    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
    .backgroundColor(Glass.FILL)
    .borderRadius(AppRadius.PILL)
    .border({ width: Glass.BORDER_WIDTH, color: Glass.BORDER_SOFT })
    .alignSelf(ItemAlign.End)
  }

  /**
   * The catalogue entry the session is actually running, matched on provider AND
   * model id - the same rule DSH uses. A live/routing provider can carry a model
   * id that also exists under its declared provider, and only the route pair
   * identifies the entry whose reasoning efforts the host will accept.
   */
  private currentModelRow(): ModelRow | undefined {
    const current = this.ui.currentModel;
    return modelRowFor(this.ui.modelGroups, current.provider, current.model);
  }

  /** DSH shows the model display name, falling back to `provider/model`. */
  private modelLabel(): string {
    const current = this.ui.currentModel;
    if (current.model.length === 0) {
      return '模型';
    }
    const row = this.currentModelRow();
    if (row !== undefined) {
      return row.name;
    }
    return current.provider.length > 0 ? `${current.provider}/${current.model}` : current.model;
  }

  /** DSH permission display names (`仅可查看` / `工作区内修改` / `完全权限`). */
  private permissionLabelFor(value: string): string {
    return permissionLabel(value);
  }

  /** Display name of one effort id (`high` -> `High`). */
  private effortName(row: ModelRow, id: string): string {
    for (const effort of row.efforts) {
      if (effort.id === id) {
        return effort.name;
      }
    }
    return id;
  }

  /**
   * What DSH prints for the effort on the composer trigger: the active effort's
   * display name, `默认` when the model offers levels but none is pinned, and
   * `不支持` when the route declares no reasoning levels at all (a routing
   * provider such as `opencode-go-live` does not). The picker must never be a
   * blank sheet - it says which of these it is.
   */
  private effortLabel(): string {
    const current = this.ui.currentModel;
    if (current.model.length === 0) {
      return '未同步';
    }
    const row = this.currentModelRow();
    if (row === undefined) {
      return '未同步';
    }
    if (row.efforts.length === 0) {
      return '不支持';
    }
    const effort = this.ui.currentModel.reasoningEffort;
    if (effort.length > 0) {
      return this.effortName(row, effort);
    }
    return row.defaultEffort.length > 0 ? this.effortName(row, row.defaultEffort) : '默认';
  }

  private permissionLabel(): string {
    const current = this.ui.currentPermission;
    if (current.length > 0) {
      return this.permissionLabelFor(current);
    }
    for (const option of this.ui.permissionOptions) {
      if (option.selected) {
        return this.permissionLabelFor(option.value);
      }
    }
    return '访问模式';
  }

  private openPicker(mode: string, title: string): void {
    this.pickerMode = mode;
    this.pickerTitle = title;
    this.sheetMode = 'picker';
    this.sheetOpen = true;
  }

  private openSheet(mode: string): void {
    this.sheetMode = mode;
    this.sheetOpen = true;
  }


  /**
   * Single entry point for the three rarely-changed session switches. A plain
   * gear circle, sized and styled exactly like the image button next to it -
   * the label would make it a pill and break the action row's rhythm.
   */
  @Builder
  settingsButton() {
    Stack() {
      SymbolGlyph($r('sys.symbol.gearshape')).fontSize(16).fontColor([AppColors.DARK_INK])
    }
    .id('settingsButton')
    .width(34)
    .height(34)
    .backgroundColor(Glass.FILL_STRONG)
    .borderRadius(AppRadius.CIRCLE)
    .border({ width: Glass.BORDER_WIDTH, color: Glass.BORDER_SOFT })
    .onClick(() => {
      // The picker rows read model/permission state that the host owns; refresh
      // it on open so a model or permission changed elsewhere (Settings page,
      // another client) is never shown stale.
      const sessionId = this.ui.activeSessionId;
      if (sessionId.length > 0) {
        this.store.refreshModels(sessionId);
        this.store.refreshPermissions(sessionId);
      }
      this.openSheet('session');
    })
  }

  /**
   * `value` is a getter, not a string: an async refresh can land while the
   * sheet is already open, and a by-value parameter would keep showing the
   * pre-refresh name (the observed read happens inside this builder).
   */
  @Builder
  settingRow(label: string, value: () => string, action: () => void) {
    Row({ space: 8 }) {
      Text(label).fontSize(AppFont.LABEL).fontColor(AppColors.DARK_INK)
      Text(value())
        .fontSize(AppFont.CAPTION)
        .fontColor(AppColors.INK_WEAK)
        .layoutWeight(1)
        .maxLines(1)
        .textAlign(TextAlign.End)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14).fontColor([AppColors.INK_WEAK])
    }
    .width('100%')
    .height(AppSpacing.TOUCH)
    .padding({ left: 12, right: 12 })
    .backgroundColor(Glass.FILL)
    .borderRadius(AppRadius.CARD)
    .border({ width: Glass.BORDER_WIDTH, color: Glass.BORDER_SOFT })
    .onClick(action)
  }

  @Builder
  sessionSettingsSheet() {
    Column({ space: AppSpacing.GAP }) {
      this.sheetHeader('会话设置')
      this.settingRow('模型', () => this.modelLabel(), () => {
        this.openPicker('model', '选择模型');
      })
      this.settingRow('思考等级', () => this.effortLabel(), () => {
        this.openPicker('effort', '思考等级');
      })
      this.settingRow('权限', () => this.permissionLabel(), () => {
        this.openPicker('permission', '会话权限');
      })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(AppSpacing.PAGE)
  }

  @Builder
  slashMenu() {
    Column({ space: 2 }) {
      // The unfiltered `/` menu lists every command plus every skill; without this
      // inner Scroll the rows rendered past the panel and landed under the composer
      // buttons (the same ArkUI trap as B13/C12). The card only styles the popover.
      Scroll() {
        Column({ space: 2 }) {
          ForEach(filterCommands(this.ui.commandGroups, slashQueryOf(this.draft) ?? ''), (group: CommandGroupRow) => {
            Text(group.title).fontSize(AppFont.CAPTION).fontColor(AppColors.INK_WEAK).width('100%')
              .padding({ left: 6, top: 4 })
            ForEach(group.items, (item: CommandItemRow) => {
              Row({ space: 8 }) {
                Text(`/${item.name}`).fontSize(AppFont.LABEL).fontColor(AppColors.DARK_INK)
                Text(item.description.length > 0 ? item.description : item.displayHint)
                  .fontSize(AppFont.CAPTION)
                  .fontColor(AppColors.INK_WEAK)
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                if (item.source === 'skill') {
                  Text('技能').fontSize(10).fontColor(AppColors.MIST)
                }
              }
              .width('100%')
              .height(40)
              .padding({ left: 6, right: 6 })
              .borderRadius(AppRadius.CARD_SMALL)
              .onClick(() => {
                if (item.kind === 'immediate' && item.submitRequest === 'command-execute') {
                  this.draft = '';
                  this.store.executeCommand(item.submitText.length > 0 ? item.submitText : `/${item.name}`);
                } else if (item.insertText.length > 0) {
                  this.draft = item.insertText;
                } else {
                  this.draft = `/${item.name} `;
                }
              })
            }, (item: CommandItemRow) => item.id)
          }, (group: CommandGroupRow) => group.id)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .constraintSize({ maxHeight: SLASH_MENU_MAX_HEIGHT })
      .scrollBar(BarState.Auto)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(8)
    .backgroundColor('#F20D2440')
    .borderRadius(AppRadius.CARD)
    .border({ width: Glass.BORDER_WIDTH, color: Glass.BORDER })
    .clip(true)
  }

  @Builder
  mentionMenu() {
    Column({ space: 2 }) {
      Scroll() {
        Column({ space: 2 }) {
          if (this.mentionError.length > 0) {
            Text(this.mentionError).fontSize(AppFont.CAPTION).fontColor(AppColors.DANGER)
              .width('100%').padding({ left: 6, top: 4, bottom: 4 })
          } else if (this.mentionRows.length === 0) {
            Text('没有匹配的文件').fontSize(AppFont.CAPTION).fontColor(AppColors.INK_WEAK)
              .width('100%').padding({ left: 6, top: 4, bottom: 4 })
          }
          ForEach(this.mentionRows, (entry: FileEntryRow) => {
            Row({ space: 8 }) {
              SymbolGlyph(entry.isDirectory ? $r('sys.symbol.folder') : $r('sys.symbol.doc_text'))
                .fontSize(14)
                .fontColor([AppColors.INK_WEAK])
              Text(entry.name).fontSize(AppFont.LABEL).fontColor(AppColors.DARK_INK)
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              if (entry.isDirectory) {
                SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(12).fontColor([AppColors.MIST])
              }
            }
            .width('100%')
            .height(40)
            .padding({ left: 6, right: 6 })
            .borderRadius(AppRadius.CARD_SMALL)
            .onClick(() => {
              this.selectMention(entry);
            })
          }, (entry: FileEntryRow) => entry.path)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .constraintSize({ maxHeight: MENTION_MENU_MAX_HEIGHT })
      .scrollBar(BarState.Auto)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(8)
    .backgroundColor('#F20D2440')
    .borderRadius(AppRadius.CARD)
    .border({ width: Glass.BORDER_WIDTH, color: Glass.BORDER })
    .clip(true)
  }

  @Builder
  moreSheet() {
    Column({ space: AppSpacing.GAP }) {
      this.sheetHeader('会话操作')
      if (this.renameOpen) {
        TextInput({ placeholder: '会话名称', text: this.renameDraft })
          .width('100%')
          .height(44)
          .fontSize(AppFont.LABEL)
          .fontColor(AppColors.DARK_INK)
          .placeholderColor(AppColors.INK_WEAK)
          .backgroundColor(Glass.FILL_SUBTLE)
          .borderRadius(AppRadius.INPUT)
          .onChange((value: string) => {
            this.renameDraft = value;
          })
        Row({ space: 10 }) {
          Text('取消')
            .fontSize(AppFont.LABEL).fontColor(AppColors.INK_WEAK).textAlign(TextAlign.Center)
            .layoutWeight(1).height(42)
            .backgroundColor(Glass.FILL).borderRadius(AppRadius.PILL)
            .onClick(() => {
              this.renameOpen = false;
            })
          Text('保存')
            .fontSize(AppFont.LABEL).fontColor(AppColors.PAPER).textAlign(TextAlign.Center)
            .layoutWeight(1).height(42)
            .backgroundColor(AppColors.BRAND).borderRadius(AppRadius.PILL)
            .onClick(() => {
              const title = this.renameDraft.replace(/^\s+|\s+$/g, '');
              if (title.length === 0) {
                this.error = '名称不能为空';
                return;
              }
              this.store.renameSession(this.ui.activeSessionId, title).then(() => {
                this.renameOpen = false;
                this.sheetOpen = false;
              }).catch((failure: Error) => {
                this.error = failure.message;
              });
            })
        }
        .width('100%')
      } else {
        // Session-level actions live here (header ⋯), not on the composer row:
        // a composer `+` reads as "add attachment" and was a mistap magnet.
        this.menuAction('新建会话', true, () => {
          this.sheetOpen = false;
          this.createNewSession();
        })
        this.menuAction('重命名会话', false, () => {
          this.renameDraft = this.ui.activeSessionTitle;
          this.renameOpen = true;
        })
        this.menuAction('归档会话', false, () => {
          this.store.archiveSession(this.ui.activeSessionId).then(() => {
            this.sheetOpen = false;
            router.back();
          }).catch((failure: Error) => {
            this.error = failure.message;
          });
        })
        this.menuAction('清空输入', false, () => {
          this.draft = '';
          this.sheetOpen = false;
        })
        this.menuAction('任务与目标', false, () => {
          this.openSheet('panel');
        })
        this.menuAction('工作区文件', false, () => {
          this.sheetOpen = false;
          router.pushUrl({ url: 'pages/WorkspaceFilesPage' });
        })
        this.menuAction('刷新统计', false, () => {
          this.store.refreshSessionStats(this.ui.activeSessionId);
          this.sheetOpen = false;
        })
        this.menuAction('设置', true, () => {
          this.sheetOpen = false;
          router.pushUrl({ url: 'pages/SettingsPage' });
        })
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(AppSpacing.PAGE)
  }

  @Builder
  menuAction(label: string, primary: boolean, action: () => void) {
    Text(label)
      .fontSize(primary ? AppFont.SUBTITLE : AppFont.LABEL)
      .fontColor(primary ? AppColors.PAPER : AppColors.DARK_INK)
      .textAlign(TextAlign.Center)
      .width('100%')
      .height(primary ? 48 : 44)
      .backgroundColor(primary ? AppColors.BRAND : Glass.FILL)
      .borderRadius(AppRadius.CARD)
      .border({ width: Glass.BORDER_WIDTH, color: primary ? '#66BFD6FF' : Glass.BORDER_SOFT })
      .onClick(action)
  }

  private copyMessage(item: ConversationItem): void {
    // Reasoning is only copied when it is actually on screen: with the toggle
    // off (default) the transcript shows no reasoning, so long-press must not
    // paste invisible text into the clipboard.
    const text = item.text.length > 0 ? item.text : (this.ui.showReasoning ? item.reasoning : '');
    if (copyToClipboard(text)) {
      this.error = '';
      this.store.showNotice('已复制到剪贴板');
    } else {
      this.error = '复制失败';
    }
  }

  @Builder
  queueSheet() {
    Column({ space: AppSpacing.GAP }) {
      this.sheetHeader(`待处理消息 · ${this.ui.queue.length}`)
      if (this.ui.queue.length === 0) {
        Text('当前没有排队消息').fontSize(AppFont.CAPTION).fontColor(AppColors.INK_WEAK).width('100%')
      }
      ForEach(this.ui.queue, (row: QueueRow) => {
        Column({ space: 8 }) {
          Row({ space: 8 }) {
            Text(placementLabel(row.placement)).fontSize(10).fontColor(AppColors.MIST)
            if (row.images > 0) {
              Text(`${row.images} 张图`).fontSize(10).fontColor(AppColors.INK_WEAK)
            }
            Text(row.itemId).fontSize(9).fontColor(Glass.CODE_LABEL).layoutWeight(1)
          }
          .width('100%')
          if (this.editingQueueId === row.itemId) {
            TextInput({ placeholder: '修改后发送的内容', text: this.queueDraft })
              .width('100%')
              .height(44)
              .fontSize(AppFont.LABEL)
              .fontColor(AppColors.DARK_INK)
              .placeholderColor(AppColors.INK_WEAK)
              .backgroundColor(Glass.FILL_SUBTLE)
              .borderRadius(AppRadius.INPUT)
              .onChange((value: string) => {
                this.queueDraft = value;
              })
          } else {
            Text(row.text.length > 0 ? row.text : '（无文本）')
              .fontSize(AppFont.LABEL)
              .fontColor(AppColors.DARK_INK)
              .width('100%')
              .maxLines(3)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          Row({ space: 8 }) {
            if (this.editingQueueId === row.itemId) {
              Text('保存')
                .fontSize(AppFont.CAPTION)
                .fontColor(AppColors.PAPER)
                .textAlign(TextAlign.Center)
                .layoutWeight(1)
                .height(36)
                .backgroundColor(AppColors.BRAND)
                .borderRadius(AppRadius.PILL)
                .onClick(() => {
                  const text = this.queueDraft.replace(/^\s+|\s+$/g, '');
                  if (text.length === 0) {
                    this.error = '内容不能为空';
                    return;
                  }
                  this.store.updateQueueItem(row.itemId, 'edit', text).then(() => {
                    this.editingQueueId = '';
                  }).catch((failure: Error) => {
                    this.error = failure.message;
                  });
                })
              Text('取消')
                .fontSize(AppFont.CAPTION)
                .fontColor(AppColors.INK_WEAK)
                .textAlign(TextAlign.Center)
                .layoutWeight(1)
                .height(36)
                .backgroundColor(Glass.FILL)
                .borderRadius(AppRadius.PILL)
                .onClick(() => {
                  this.editingQueueId = '';
                })
            } else {
              Text('编辑')
                .fontSize(AppFont.CAPTION)
                .fontColor(AppColors.DARK_INK)
                .textAlign(TextAlign.Center)
                .layoutWeight(1)
                .height(36)
                .backgroundColor(Glass.FILL)
                .borderRadius(AppRadius.PILL)
                .onClick(() => {
                  this.queueDraft = row.text;
                  this.editingQueueId = row.itemId;
                })
              if (canSteer(row, true)) {
                Text('立即插入')
                  .fontSize(AppFont.CAPTION)
                  .fontColor(AppColors.DARK_INK)
                  .textAlign(TextAlign.Center)
                  .layoutWeight(1)
                  .height(36)
                  .backgroundColor(Glass.FILL)
                  .borderRadius(AppRadius.PILL)
                  .onClick(() => {
                    this.store.updateQueueItem(row.itemId, 'steer').catch((failure: Error) => {
                      this.error = failure.message;
                    });
                  })
              }
              Text('删除')
                .fontSize(AppFont.CAPTION)
                .fontColor(AppColors.DANGER)
                .textAlign(TextAlign.Center)
                .layoutWeight(1)
                .height(36)
                .backgroundColor(Glass.FILL)
                .borderRadius(AppRadius.PILL)
                .onClick(() => {
                  this.store.updateQueueItem(row.itemId, 'remove').catch((failure: Error) => {
                    this.error = failure.message;
                  });
                })
            }
          }
          .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding(10)
        .backgroundColor(Glass.FILL_SUBTLE)
        .borderRadius(AppRadius.CARD_SMALL)
      }, (row: QueueRow) => row.itemId)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(AppSpacing.PAGE)
  }

  @Builder
  sheetContent() {
    if (this.sheetMode === 'more') {
      this.moreSheet()
    } else if (this.sheetMode === 'session') {
      this.sessionSettingsSheet()
    } else if (this.sheetMode === 'picker') {
      this.pickerSheet()
    } else if (this.sheetMode === 'queue') {
      this.queueSheet()
    } else {
      this.panelsSheet()
    }
  }

  @Builder
  pickerSheet() {
    Column({ space: 8 }) {
      this.sheetHeader(this.pickerTitle)
      if (this.pickerMode === 'model') {
        ForEach(this.ui.modelGroups, (group: ModelGroupRow) => {
          Text(group.name).fontSize(AppFont.CAPTION).fontColor(AppColors.INK_WEAK).width('100%')
            .padding({ top: 6 })
          ForEach(group.models, (model: ModelRow) => {
            this.pickerRow(model.name, model.description, model.selected, () => {
              this.sheetOpen = false;
              // Switching routes adopts the new model's default effort, exactly
              // like DSH; a route without a default keeps the provider's choice.
              this.store.selectModel(group.id, model.id, model.defaultEffort)
                .catch((failure: Error) => {
                  this.fail(failure.message);
                });
            })
          }, (model: ModelRow) => `${group.id}-${model.id}`)
        }, (group: ModelGroupRow) => group.id)
      } else if (this.pickerMode === 'effort') {
        // A blank list used to look like a broken sheet; say why there is
        // nothing to pick (the session runs a live route with no reasoning
        // levels) instead.
        if (this.currentModelRow() === undefined) {
          Text('思考等级同步中，请稍候重试。')
            .fontSize(AppFont.CAPTION)
            .fontColor(AppColors.INK_WEAK)
            .width('100%')
            .padding({ top: 8, bottom: 8 })
        } else if (this.currentEfforts().length === 0) {
          Text('当前模型不支持思考等级，请先切换到带推理的模型。')
            .fontSize(AppFont.CAPTION)
            .fontColor(AppColors.INK_WEAK)
            .width('100%')
            .padding({ top: 8, bottom: 8 })
        } else {
          // DSH offers a "provider default" row whenever the catalogue does not
          // pin a default effort.
          if (this.currentDefaultEffort().length === 0) {
            this.pickerRow('默认', '使用服务商默认思考等级',
              this.ui.currentModel.reasoningEffort.length === 0, () => {
                this.applyEffort('');
              })
          }
          ForEach(this.currentEfforts(), (effort: ReasoningEffortRow) => {
            this.pickerRow(effort.name, effort.description,
              effort.id === this.ui.currentModel.reasoningEffort, () => {
                this.applyEffort(effort.id);
              })
          }, (effort: ReasoningEffortRow) => effort.id)
        }
      } else {
        ForEach(this.ui.permissionOptions, (option: PermissionOptionRow) => {
          this.pickerRow(this.permissionLabelFor(option.value), option.value, option.selected, () => {
            this.confirmPermission(option.value);
          })
        }, (option: PermissionOptionRow) => option.value)
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(AppSpacing.PAGE)
  }

  /** Efforts the current route declares (`[]` when it supports none). */
  private currentEfforts(): ReasoningEffortRow[] {
    const row = this.currentModelRow();
    return row === undefined ? [] : row.efforts;
  }

  /** Default effort of the current route ('' when the provider decides). */
  private currentDefaultEffort(): string {
    const row = this.currentModelRow();
    return row === undefined ? '' : row.defaultEffort;
  }

  /**
   * The picker closes before its host call settles, so an inline error line on
   * the page behind the sheet is invisible; surface it as a toast too.
   */
  private fail(message: string): void {
    this.error = message;
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 4000 });
    } catch (error) {
      void error;
    }
  }

  private applyEffort(effort: string): void {
    this.sheetOpen = false;
    this.store.selectModel(this.ui.currentModel.provider, this.ui.currentModel.model, effort)
      .catch((failure: Error) => {
        this.fail(failure.message);
      });
  }

  /** DSH gates the full-access preset behind an explicit risk confirmation. */
  private confirmPermission(value: string): void {
    this.sheetOpen = false;
    if (value !== 'danger-full-access') {
      this.store.setPermission(value).catch((failure: Error) => {
        this.fail(failure.message);
      });
      return;
    }
    this.getUIContext().showAlertDialog({
      title: '确认启用完全权限？',
      message: '启用完全权限后，智能体将减少确认步骤，并可直接执行更多操作，包括敏感操作、文件修改或外部命令。',
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '启用完全权限',
        fontColor: AppColors.DANGER,
        action: () => {
          this.store.setPermission(value).catch((failure: Error) => {
            this.fail(failure.message);
          });
        }
      }
    });
  }

  @Builder
  pickerRow(title: string, subtitle: string, selected: boolean, action: () => void) {
    Row({ space: 8 }) {
      Column({ space: 2 }) {
        Text(title).fontSize(AppFont.LABEL).fontColor(AppColors.DARK_INK).width('100%')
        if (subtitle.length > 0) {
          Text(subtitle).fontSize(AppFont.CAPTION).fontColor(AppColors.INK_WEAK).width('100%')
            .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      if (selected) {
        SymbolGlyph($r('sys.symbol.checkmark')).fontSize(14).fontColor([AppColors.SUCCESS])
      }
    }
    .width('100%')
    .padding({ top: 10, bottom: 10, left: 8, right: 8 })
    .backgroundColor(selected ? Glass.FILL_STRONG : '#00000000')
    .borderRadius(AppRadius.CARD_SMALL)
    .onClick(action)
  }

  /**
   * Album picker URIs (`file://media/Photo/...`) are already complete; a bare
   * sandbox path still needs the `file://` prefix. Concatenating blindly gave
   * `file://file://media/...`, which ArkUI rejects ("GetAsset failed") - the
   * thumbnail box rendered with only the remove button (user report).
   */
  private previewSource(prepared: PreparedImageRow): string {
    const uri = prepared.sourceUri;
    return uri.indexOf('://') >= 0 ? uri : `file://${uri}`;
  }

  @Builder
  composer() {
    Column({ space: 10 }) {
      // Multi-line: TextInput is single-line by contract, so long prompts were
      // clipped. TextArea soft-wraps and grows up to a few lines, then scrolls.
      TextArea({
        placeholder: '描述你的需求，/ 指令，@ 文件',
        text: this.draft,
        controller: this.draftController
      })
        .id('composerInput')
        .fontSize(AppFont.BODY)
        .fontColor(AppColors.DARK_INK)
        .placeholderColor(AppColors.INK_WEAK)
        .backgroundColor('#00000000')
        .borderRadius(AppRadius.NONE)
        .padding(0)
        .width('100%')
        .lineHeight(22)
        .constraintSize({ minHeight: COMPOSER_INPUT_MIN_HEIGHT, maxHeight: COMPOSER_INPUT_MAX_HEIGHT })
        // Send on the IME action key; the transcript keeps the send button too.
        .enterKeyType(EnterKeyType.Send)
        .onChange((value: string) => {
          this.onDraftChanged(value);
        })
        .onTextSelectionChange((selectionStart: number, selectionEnd: number) => {
          this.onCaretChanged(selectionStart, selectionEnd);
        })
        .onSubmit(() => {
          this.send();
        })
      if (slashQueryOf(this.draft) !== null) {
        this.slashMenu()
      }
      if (this.mentionOpen) {
        this.mentionMenu()
      }
      if (this.ui.commandOutcome !== null) {
        Row() {
          Text(this.ui.commandOutcome?.kind === 'error' ? '命令失败' : '命令完成')
            .fontSize(10)
            .fontColor(this.ui.commandOutcome?.kind === 'error' ? AppColors.DANGER : AppColors.OK)
            .onClick(() => {
              this.store.clearCommandOutcome();
            })
        }
        .width('100%')
      }

      if (this.ui.preparedImages.length > 0) {
        Column({ space: 6 }) {
          Row({ space: 8 }) {
            ForEach(this.ui.preparedImages, (prepared: PreparedImageRow, index: number) => {
              Stack({ alignContent: Alignment.TopEnd }) {
                Image(this.previewSource(prepared))
                  .width(64)
                  .height(64)
                  .objectFit(ImageFit.Cover)
                  .borderRadius(AppRadius.CARD_SMALL)
                Stack() {
                  SymbolGlyph($r('sys.symbol.xmark')).fontSize(12).fontColor([AppColors.PAPER])
                }
                .width(20)
                .height(20)
                .backgroundColor('#CC000000')
                .borderRadius(AppRadius.CIRCLE)
                .onClick(() => {
                  this.store.removePreparedImage(index);
                })
              }
              .width(64)
              .height(64)
            }, (prepared: PreparedImageRow, index: number) => `${index}-${prepared.name}`)
          }
          .width('100%')
          Text(`${this.store.imageBudgetText()}${this.ui.imageBudgetOk ? '' : ' · 超出预算'}`)
            .fontSize(10)
            .fontColor(this.ui.imageBudgetOk ? AppColors.INK_WEAK : AppColors.DANGER)
            .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
      }

      Row({ space: 10 }) {
        Stack() {
          SymbolGlyph($r('sys.symbol.ohos_photo')).fontSize(16).fontColor([AppColors.DARK_INK])
        }
        .id('pickImageButton')
        .width(34)
        .height(34)
        .backgroundColor(Glass.FILL_STRONG)
        .borderRadius(AppRadius.CIRCLE)
        .border({ width: Glass.BORDER_WIDTH, color: Glass.BORDER_SOFT })
        .onClick(() => {
          if (!this.ui.busy) {
            this.store.pickImages();
          }
        })
        // Model / effort / permission are set once and rarely touched, so the
        // three of them live behind one gear button on the composer action row.
        this.settingsButton()
        // The queue/steer delimiter only means something while a turn is running
        // (when idle both modes deliver a plain message), so it stays hidden
        // until then — same as DSH, which names the mode on the send button only
        // while the session is running.
        if (this.ui.busy) {
          Text(this.mode === 'queue' ? '排队发送' : '插话发送')
            .id('modeToggle')
            .fontSize(AppFont.CAPTION)
            .fontColor(AppColors.DARK_INK)
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .backgroundColor(Glass.FILL_STRONG)
            .borderRadius(AppRadius.PILL)
            .border({ width: Glass.BORDER_WIDTH, color: Glass.BORDER_SOFT })
            .onClick(() => {
              this.mode = this.mode === 'queue' ? 'steer' : 'queue';
            })
        }
        Text(this.ui.busy ? '发送中…' : '')
          .fontSize(AppFont.CAPTION)
          .fontColor(AppColors.INK_WEAK)
          .layoutWeight(1)
        Stack() {
          SymbolGlyph($r('sys.symbol.arrow_up')).fontSize(18).fontColor([AppColors.PAPER])
        }
        .id('sendButton')
        .width(34)
        .height(34)
        .borderRadius(AppRadius.CIRCLE)
        .backgroundColor(this.ui.busy ? '#40FFFFFF' : AppColors.BRAND)
        .onClick(() => {
          if (!this.ui.busy) {
            this.send();
          }
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .backgroundColor(Glass.FILL_STRONG)
    .borderRadius(AppRadius.CARD)
    .border({ width: Glass.BORDER_WIDTH, color: Glass.BORDER })
    .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK, Glass.blurOptions())
    .shadow(AppShadow.CARD)
  }

  build() {
    Stack() {
      HarnessBackground()
      Column({ space: AppSpacing.GAP }) {
        this.topBar()
        this.segmented()

        if (this.error.length > 0) {
          // Bounded: a long failure body must not push the composer off screen.
          Text(this.error)
            .fontSize(AppFont.CAPTION)
            .fontColor(AppColors.DANGER)
            .width('100%')
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }

        Stack() {
          List({ space: 4, scroller: this.scroller }) {
          if (this.ui.conversationLoading && this.ui.conversation.length === 0) {
            ListItem() {
              Row({ space: 8 }) {
                LoadingProgress().width(18).height(18).color(AppColors.MIST)
                Text('加载对话…')
                  .fontSize(AppFont.CAPTION)
                  .fontColor(AppColors.MIST)
              }
              .width('100%')
              .justifyContent(FlexAlign.Center)
              .padding({ top: 28, bottom: 28 })
            }
          }
          if (!(this.ui.conversationLoading && this.ui.conversation.length === 0)) {
            ListItem() {
              Text(this.loadingMore ? '加载中…' : '加载更早的历史')
                .fontSize(AppFont.CAPTION)
                .fontColor(AppColors.MIST)
                .width('100%')
                .textAlign(TextAlign.Center)
                .padding({ top: 6, bottom: 10 })
                .onClick(() => {
                  this.loadOlder();
                })
            }
          }
          ForEach(this.ui.conversation, (item: ConversationItem, index: number) => {
            ListItem() {
              this.messageBubble(item, index)
            }
          }, (item: ConversationItem) => item.key)
          if (shouldShowThinking(this.ui.conversation, this.ui.turnActive)) {
            ListItem() {
              ThinkingIndicator({ startedAt: this.ui.turnStartedAt })
            }
          }
          ListItem() {
            Column({ space: 6 }) {
              this.runPill()
            }
            .width('100%')
            .padding({ top: 8 })
          }
          // Pending human-in-the-loop cards scroll WITH the transcript instead of
          // sitting fixed below it. A question's detail can be a whole plan and
          // far taller than the screen; because this List is the page's only
          // flexible child, a tall card can no longer push the composer (or the
          // card's own answer controls) off screen.
          ForEach(this.ui.approvals, (cardRow: ApprovalCardRow) => {
            ListItem() {
              ApprovalCard({ card: cardRow })
            }
          }, (cardRow: ApprovalCardRow) => cardRow.rpcId)
          ForEach(this.ui.questions, (cardRow: QuestionCardRow) => {
            ListItem() {
              HumanQuestionCard({ card: cardRow })
            }
          }, (cardRow: QuestionCardRow) => cardRow.rpcId)
        }
          .layoutWeight(1)
          .width('100%')
          .scrollBar(BarState.Off)
          .onScrollIndex((first: number, last: number) => {
            if (first === 0) {
              this.loadOlder();
            }
            // The index range counts every List item — messages, thinking, run
            // pill and pending cards — not just messages.
            this.atBottom = last >= conversationListItemCount(this.ui.conversation, this.ui.turnActive,
              this.ui.approvals.length + this.ui.questions.length) - 1;
          })
          if (!this.atBottom) {
            SymbolGlyph($r('sys.symbol.arrow_down'))
              .fontSize(AppFont.CAPTION)
              .fontColor([AppColors.DARK_INK])
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .backgroundColor('#F20D2440')
              .borderRadius(AppRadius.PILL)
              .border({ width: Glass.BORDER_WIDTH, color: Glass.BORDER })
              .onClick(() => {
                this.scroller.scrollEdge(Edge.Bottom);
              })
          }
        }
        .layoutWeight(1)
        .width('100%')

        // Live task list (WebUI parity): hidden until the agent writes one.
        if (this.ui.todos !== null && this.ui.todos.length > 0) {
          TodoPanel({ todos: this.ui.todos })
        }

        SessionStatsBar({ stats: this.ui.stats, busy: this.ui.busy })

        Row({ space: 10 }) {
          Button('停止生成')
            .id('stopButton')
            .fontSize(AppFont.CAPTION)
            .fontColor(AppColors.DARK_INK)
            .layoutWeight(1)
            .height(34)
            .backgroundColor(Glass.FILL)
            .border({ width: Glass.BORDER_WIDTH, color: Glass.BORDER_SOFT })
            .borderRadius(AppRadius.PILL)
            .onClick(() => {
              this.stop();
            })
        }
        .width('100%')

        this.composer()
      }
      .width('100%')
      .height('100%')
      .padding({
        left: AppSpacing.PAGE,
        right: AppSpacing.PAGE,
        top: 8 + this.insetTop,
        bottom: 12 + this.insetBottom
      })
    }
    .width('100%')
    .height('100%')
    .bindSheet($$this.sheetOpen, this.sheetContent(), {
      height: 560,
      backgroundColor: '#F20D2440',
      blurStyle: BlurStyle.NONE,
      showClose: false
    })
  }
}
