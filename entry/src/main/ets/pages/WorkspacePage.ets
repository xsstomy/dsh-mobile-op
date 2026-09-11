/**
 * Workspace home: atmosphere background, glass workspace selector, primary
 * new-session action, recent sessions with relative time
 * (upstream: home.png).
 */
import { router } from '@kit.ArkUI';
import { GatewayStore } from '../store/GatewayStore';
import { SessionRow, UI_KEY, UiSnapshot, WorkspaceRow, emptyUiSnapshot } from '../store/UiState';
import { AppColors, AppFont, AppRadius, AppSpacing, AppShadow, Glass } from '../common/Constants';
import { relativeTime } from '../common/Format';
import { HarnessBackground } from '../common/HarnessBackground';
import { isTransportUnavailable } from '../gateway/RequestTracker';

/** Expanded workspace dropdown cap; a long roster scrolls inside the card. */
const WORKSPACE_LIST_MAX_HEIGHT = 240;

@Entry
@Component
struct WorkspacePage {
  @StorageLink(UI_KEY) ui: UiSnapshot = emptyUiSnapshot();
  /** Status/navigation bar insets (vp) published by WindowChrome. */
  @StorageProp('gwInsetTop') insetTop: number = 0;
  @StorageProp('gwInsetBottom') insetBottom: number = 0;
  /**
   * A `session-create` this page started. Kept apart from the roster refresh:
   * `onPageShow` re-loads the list on every return from a pushed page, and that
   * background refresh must not relabel or disable the 新会话 button.
   */
  @State creating: boolean = false;
  @State error: string = '';
  /** Roster-refresh failures; kept apart so a background retry cannot wipe them. */
  @State rosterError: string = '';
  @State query: string = '';
  @State pickerOpen: boolean = false;
  @State now: number = Date.now();
  private store: GatewayStore = GatewayStore.current;
  /** Bounded self-heal timer for a roster write that lost the socket race. */
  private retryTimer: number = -1;
  private retryLeft: number = 0;
  /**
   * Session id whose `selectSession` is currently in flight. Opening a session
   * takes several round trips, so over a WAN tunnel it can take ~1 s — long
   * enough that an impatient double/triple tap used to queue several selects
   * and then push one ConversationPage per tap. The first tap latches; later
   * taps are ignored until this page is shown again (see `onPageShow`).
   */
  private openingSessionId: string = '';

  async aboutToAppear(): Promise<void> {
    await this.reload();
  }

  /**
   * Also refresh when the page is shown again (returning from a conversation or
   * the settings): this page stays in the router stack, so `aboutToAppear` does
   * not run a second time and the list would keep a stale snapshot.
   */
  onPageShow(): void {
    // Returning from a conversation (or a failed push) releases the open latch
    // so the next tap can enter a session again.
    this.openingSessionId = '';
    this.reload();
  }

  /**
   * Refresh the roster. Deliberately has no busy flag of its own: it runs in the
   * background on every page show, and the primary action must stay usable while
   * it is in flight.
   */
  private async reload(): Promise<void> {
    this.rosterError = '';
    this.now = Date.now();
    try {
      await this.store.refreshWorkspaces();
      await this.store.refreshSessions();
      this.retryLeft = 0;
    } catch (failure) {
      const error = failure as Error;
      // A "not connected" failure is already stated by the connection label next
      // to 最近会话; a red line here would just repeat it, and it flickered on and
      // off because every retry clears the field first. Only genuine host
      // refusals get the red roster text.
      if (!isTransportUnavailable(error)) {
        this.rosterError = error.message;
      }
      // The gateway can flip to `connected` a few milliseconds before a lane
      // accepts writes. Retrying beats leaving "workspaces 发送失败：连接不可用"
      // on screen until the user taps 刷新 (B16).
      if (isTransportUnavailable(error) && this.retryLeft < 3) {
        this.retryLeft = this.retryLeft + 1;
        this.scheduleReload();
      }
    }
  }

  private scheduleReload(): void {
    if (this.retryTimer >= 0) {
      clearTimeout(this.retryTimer);
    }
    this.retryTimer = setTimeout(() => {
      this.retryTimer = -1;
      this.reload();
    }, 1200);
  }

  aboutToDisappear(): void {
    if (this.retryTimer >= 0) {
      clearTimeout(this.retryTimer);
      this.retryTimer = -1;
    }
  }

  private async createSession(): Promise<void> {
    if (this.creating) {
      return;
    }
    this.creating = true;
    this.error = '';
    try {
      await this.store.newSession();
      router.pushUrl({ url: 'pages/ConversationPage' });
    } catch (failure) {
      this.error = (failure as Error).message;
    } finally {
      this.creating = false;
    }
  }

  /**
   * Open a session at most once per tap burst. `selectSession` is a chain of
   * requests, so while it is in flight every additional tap is dropped instead
   * of stacking another ConversationPage. The latch is released in
   * `onPageShow` on return, and immediately if the open fails.
   */
  private async openSession(sessionId: string): Promise<void> {
    if (this.openingSessionId.length > 0) {
      return;
    }
    this.openingSessionId = sessionId;
    this.error = '';
    try {
      await this.store.selectSession(sessionId);
      await router.pushUrl({ url: 'pages/ConversationPage' });
    } catch (failure) {
      this.error = (failure as Error).message;
      this.openingSessionId = '';
    }
  }

  private activeWorkspace(): WorkspaceRow | undefined {
    for (const workspace of this.ui.workspaces) {
      if (workspace.active) {
        return workspace;
      }
    }
    return this.ui.workspaces.length > 0 ? this.ui.workspaces[0] : undefined;
  }

  private visibleSessions(): SessionRow[] {
    const needle = this.query.replace(/^\s+|\s+$/g, '').toLowerCase();
    if (needle.length === 0) {
      return this.ui.sessions;
    }
    const result: SessionRow[] = [];
    for (const session of this.ui.sessions) {
      if (session.title.toLowerCase().indexOf(needle) >= 0 ||
        session.sessionId.toLowerCase().indexOf(needle) >= 0 ||
        session.cwd.toLowerCase().indexOf(needle) >= 0) {
        result.push(session);
      }
    }
    return result;
  }

  private statusLabel(): string {
    return this.ui.connection === 'connected' ? '已连接' : this.ui.connection;
  }

  @Builder
  glassCircle(glyph: Resource, action: () => void) {
    // Stack centres the glyph; sizing the SymbolGlyph itself pins it to the
    // top-left corner of the circle.
    Stack() {
      SymbolGlyph(glyph).fontSize(17).fontColor([AppColors.DARK_INK])
    }
    .width(40)
    .height(40)
    .borderRadius(AppRadius.CIRCLE)
    .backgroundColor(Glass.FILL)
    .border({ width: Glass.BORDER_WIDTH, color: Glass.BORDER })
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK, Glass.blurOptions())
    .onClick(action)
  }

  @Builder
  brandRow() {
    Row({ space: 10 }) {
      Column({ space: 2 }) {
        Text('DeepSeek Harness').fontSize(AppFont.SUBTITLE).fontWeight(FontWeight.Medium).fontColor(AppColors.ON_ATMOSPHERE)
        Text('鸿蒙客户端 · 预览版').fontSize(AppFont.CAPTION).fontColor(AppColors.INK_WEAK)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      // Pairing entry on the home page: after 解除配对 the only other route to
      // the scanner is the launcher page, which a running app never shows again
      // (B14), so the scan/pair action lives next to refresh.
      this.glassCircle($r('sys.symbol.barcode_viewfinder'), () => {
        router.pushUrl({ url: 'pages/PairingPage' });
      })
      this.glassCircle($r('sys.symbol.arrow_counterclockwise'), () => {
        this.reload();
      })
      this.glassCircle($r('sys.symbol.gearshape'), () => {
        router.pushUrl({ url: 'pages/SettingsPage' });
      })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  hero() {
    Column({ space: 6 }) {
      // The endpoint URL is developer noise on the home page: the connection
      // state lives next to 最近会话 and the raw URL stays in Settings/Pairing.
      Text('探索未至之境').fontSize(AppFont.DISPLAY).fontWeight(FontWeight.Bold).fontColor(AppColors.ON_ATMOSPHERE)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .margin({ top: 18, bottom: 4 })
  }

  @Builder
  workspaceSelector() {
    Column({ space: 0 }) {
      Row({ space: 12 }) {
        SymbolGlyph($r('sys.symbol.folder')).fontSize(20)
        Column({ space: 2 }) {
          Text(this.activeWorkspace()?.title ?? '未选择工作区')
            .fontSize(AppFont.SUBTITLE)
            .fontColor(AppColors.DARK_INK)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Text(this.activeWorkspace()?.path ?? '')
            .fontSize(AppFont.CAPTION)
            .fontColor(AppColors.INK_WEAK)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Circle({ width: 8, height: 8 }).fill(AppColors.SUCCESS)
        SymbolGlyph(this.pickerOpen ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down')).fontSize(16).fontColor([AppColors.INK_WEAK])
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.pickerOpen = !this.pickerOpen;
      })

      if (this.pickerOpen) {
        Row({ space: 10 }) {
          Text('浏览目录 / 新建工作区')
            .fontSize(AppFont.CAPTION)
            .fontColor(AppColors.MIST)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .height(38)
            .backgroundColor(Glass.FILL_SUBTLE)
            .borderRadius(AppRadius.PILL)
            .onClick(() => {
              this.pickerOpen = false;
              router.pushUrl({ url: 'pages/WorkspaceBrowserPage' });
            })
          Text('工作区文件')
            .fontSize(AppFont.CAPTION)
            .fontColor(AppColors.MIST)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .height(38)
            .backgroundColor(Glass.FILL_SUBTLE)
            .borderRadius(AppRadius.PILL)
            .onClick(() => {
              this.pickerOpen = false;
              router.pushUrl({ url: 'pages/WorkspaceFilesPage' });
            })
        }
        .width('100%')
        .margin({ top: 10, bottom: 4 })
        // Height-bounded so a large workspace roster can never push the
        // sessions list / composer off screen (same cap as TodoPanel).
        Scroll() {
          Column({ space: 2 }) {
            ForEach(this.ui.workspaces, (workspace: WorkspaceRow) => {
              Row({ space: 8 }) {
                Text(workspace.title)
                  .fontSize(AppFont.LABEL)
                  .fontColor(workspace.active ? AppColors.DARK_INK : AppColors.INK_WEAK)
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(`${workspace.sessionCount}`).fontSize(AppFont.CAPTION).fontColor(AppColors.INK_WEAK)
              }
              .width('100%')
              .height(AppSpacing.TOUCH)
              .padding({ left: 8, right: 8 })
              .borderRadius(AppRadius.CARD_SMALL)
              .backgroundColor(workspace.active ? Glass.FILL_STRONG : '#00000000')
              .onClick(() => {
                this.pickerOpen = false;
                this.store.selectWorkspace(workspace.workspaceId).then(() => {
                  this.now = Date.now();
                }).catch((failure: Error) => {
                  this.error = failure.message;
                });
              })
            }, (workspace: WorkspaceRow) => workspace.workspaceId)
          }
          .width('100%')
        }
        .width('100%')
        .constraintSize({ maxHeight: WORKSPACE_LIST_MAX_HEIGHT })
        .scrollBar(BarState.Auto)
        .margin({ top: 10 })
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor(Glass.FILL)
    .borderRadius(AppRadius.CARD)
    .border({ width: Glass.BORDER_WIDTH, color: Glass.BORDER })
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK, Glass.blurOptions())
    .shadow(AppShadow.CARD)
  }

  @Builder
  newSessionAction() {
    Row({ space: 8 }) {
      Text('+').fontSize(20).fontColor(AppColors.PAPER)
      Text(this.creating ? '处理中…' : '新会话').fontSize(AppFont.SUBTITLE).fontColor(AppColors.PAPER)
    }
    .id('newSessionButton')
    .width('100%')
    .height(52)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .backgroundColor('#F22E6BE6')
    .borderRadius(AppRadius.CARD)
    .border({ width: Glass.BORDER_WIDTH, color: '#66BFD6FF' })
    .onClick(() => {
      if (!this.creating) {
        this.createSession();
      }
    })
  }

  @Builder
  searchField() {
    Row({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(15).fontColor([AppColors.INK_WEAK])
      TextInput({ placeholder: '搜索会话…', text: this.query })
        .layoutWeight(1)
        .fontSize(AppFont.LABEL)
        .fontColor(AppColors.DARK_INK)
        .placeholderColor(AppColors.INK_WEAK)
        .backgroundColor('#00000000')
        .padding(0)
        .onChange((value: string) => {
          this.query = value;
        })
    }
    .width('100%')
    .height(44)
    .padding({ left: 14, right: 14 })
    .backgroundColor(Glass.FILL)
    .borderRadius(AppRadius.INPUT)
    .border({ width: Glass.BORDER_WIDTH, color: Glass.BORDER_SOFT })
  }

  @Builder
  sessionRow(session: SessionRow) {
    Row({ space: 12 }) {
      Circle({ width: 6, height: 6 })
        .fill(session.running ? AppColors.SUCCESS : Glass.BORDER)
        .margin({ top: 6 })
      Column({ space: 3 }) {
        Text(session.title)
          .fontSize(AppFont.BODY)
          .fontColor(AppColors.DARK_INK)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(session.sessionId)
          .fontSize(AppFont.CAPTION)
          .fontColor(AppColors.INK_WEAK)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      if (session.blank) {
        Text('空').fontSize(10).fontColor(AppColors.INK_WEAK)
      }
      Text(relativeTime(session.updatedAt, this.now))
        .fontSize(AppFont.CAPTION)
        .fontColor(AppColors.INK_WEAK)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ top: 12, bottom: 12 })
    .onClick(() => {
      this.openSession(session.sessionId);
    })
    .gesture(LongPressGesture().onAction(() => {
      this.store.archiveSession(session.sessionId).catch((failure: Error) => {
        this.error = failure.message;
      });
    }))
  }

  build() {
    Stack() {
      HarnessBackground()
      Column({ space: AppSpacing.GAP }) {
        this.brandRow()
        this.hero()
        this.workspaceSelector()
        this.newSessionAction()

        Row({ space: 8 }) {
          Text('最近会话').fontSize(AppFont.HEADING).fontWeight(FontWeight.Bold).fontColor(AppColors.DARK_INK)
          Text(this.statusLabel())
            .fontSize(AppFont.CAPTION)
            .fontColor(this.ui.connection === 'connected' ? AppColors.SUCCESS : AppColors.WARN)
            .layoutWeight(1)
            .textAlign(TextAlign.End)
        }
        .width('100%')
        .margin({ top: 6 })

        this.searchField()

        if (this.error.length > 0) {
          Text(this.error).fontSize(AppFont.CAPTION).fontColor(AppColors.DANGER).width('100%')
        }
        if (this.rosterError.length > 0) {
          Text(this.rosterError).fontSize(AppFont.CAPTION).fontColor(AppColors.DANGER).width('100%')
        }

        List({ space: 0 }) {
          ForEach(this.visibleSessions(), (session: SessionRow) => {
            ListItem() {
              this.sessionRow(session)
            }
          }, (session: SessionRow) => session.sessionId)
        }
        // Bounded by the remaining space (layoutWeight), so a long roster can
        // never push the page; the visible bar matches the workspace dropdown.
        .layoutWeight(1)
        .constraintSize({ minHeight: 0 })
        .width('100%')
        .divider({ strokeWidth: 1, color: Glass.BORDER_SOFT, startMargin: 18, endMargin: 0 })
        .scrollBar(BarState.Auto)

        if (this.ui.notice.length > 0) {
          Text(this.ui.notice)
            .fontSize(AppFont.CAPTION)
            .fontColor(this.ui.noticeIsError ? AppColors.WARN : AppColors.OK)
            .width('100%')
        }
      }
      .width('100%')
      .height('100%')
      .padding({
        left: AppSpacing.PAGE,
        right: AppSpacing.PAGE,
        top: 12 + this.insetTop,
        bottom: 12 + this.insetBottom
      })
    }
    .width('100%')
    .height('100%')
  }
}
