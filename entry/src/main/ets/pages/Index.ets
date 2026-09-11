/**
 * Entry page: initialises the store and routes to the workspace when connected.
 */
import { KeyboardAvoidMode, router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import { GatewayConnectionState } from '../gateway/GatewayClient';
import { GatewayStore } from '../store/GatewayStore';
import { UI_KEY, UiSnapshot, emptyUiSnapshot } from '../store/UiState';
import { showEndpointLine } from '../store/StatusLine';
import { AppColors, AppFont, AppRadius, AppSpacing, AppShadow, Glass } from '../common/Constants';
import { HarnessBackground } from '../common/HarnessBackground';

const TAG = 'IndexPage';

@Entry
@Component
struct Index {
  @StorageLink(UI_KEY) @Watch('onSnapshotChanged') ui: UiSnapshot = emptyUiSnapshot();
  /** Status/navigation bar insets (vp) published by WindowChrome. */
  @StorageProp('gwInsetTop') insetTop: number = 0;
  @StorageProp('gwInsetBottom') insetBottom: number = 0;
  @State message: string = '正在初始化…';
  private store: GatewayStore = GatewayStore.current;
  /** Guards the auto-advance: the page stack must not grow on every snapshot. */
  private routed: boolean = false;

  async aboutToAppear(): Promise<void> {
    // Window-wide: compress pages instead of lifting them when the keyboard opens.
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
    try {
      await this.store.init(getContext(this) as common.Context);
      this.message = this.store.hasSavedCredential ? '正在连接 DeepSeek Harness…' : '尚未配对设备';
      if (this.store.hasSavedCredential) {
        await this.store.connectSaved();
      }
    } catch (error) {
      hilog.error(0x0000, TAG, 'init failed: %{public}s', JSON.stringify(error));
      this.message = (error as Error).message;
    }
  }

  onPageShow(): void {
    this.routed = false;
    this.maybeRoute();
  }

  /** Auto-advance as soon as the (asynchronous) connection becomes ready. */
  onSnapshotChanged(): void {
    this.maybeRoute();
  }

  private maybeRoute(): void {
    if (this.routed || this.ui.connection !== GatewayConnectionState.CONNECTED) {
      return;
    }
    this.routed = true;
    // replaceUrl keeps the launcher out of the stack so back-navigation exits.
    router.replaceUrl({ url: 'pages/WorkspacePage' }).catch((error: Error) => {
      hilog.warn(0x0000, TAG, 'route failed: %{public}s', error.message);
      this.routed = false;
    });
  }

  private stateLabel(): string {
    switch (this.ui.connection) {
      case GatewayConnectionState.CONNECTED:
        return '已连接';
      case GatewayConnectionState.CONNECTING:
        return '连接中';
      case GatewayConnectionState.AUTHENTICATING:
        return '认证中';
      case GatewayConnectionState.FAILED:
        return '连接失败';
      default:
        return '未连接';
    }
  }

  private stateColor(): ResourceColor {
    switch (this.ui.connection) {
      case GatewayConnectionState.CONNECTED:
        return AppColors.SUCCESS;
      case GatewayConnectionState.FAILED:
        return AppColors.DANGER;
      default:
        return AppColors.AMBER;
    }
  }

  @Builder
  statusCard() {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Circle({ width: 9, height: 9 }).fill(this.stateColor())
        Text(this.stateLabel()).fontSize(AppFont.LABEL).fontColor(AppColors.DARK_INK)
        Text(this.ui.connectionDetail)
          .fontSize(AppFont.CAPTION)
          .fontColor(AppColors.INK_WEAK)
          .layoutWeight(1)
          .textAlign(TextAlign.End)
      }
      .width('100%')
      if (showEndpointLine(this.ui.connection === GatewayConnectionState.CONNECTED,
        this.ui.connectionDetail, this.ui.endpoint)) {
        Text(this.ui.endpoint.length > 0 ? this.ui.endpoint : '未配置端点')
          .fontSize(AppFont.CAPTION)
          .fontColor(AppColors.MIST)
          .width('100%')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
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
  primaryAction(label: string, id: string, enabled: boolean, action: () => void) {
    Text(label)
      .id(id)
      .fontSize(AppFont.SUBTITLE)
      .fontColor(enabled ? AppColors.PAPER : AppColors.INK_WEAK)
      .textAlign(TextAlign.Center)
      .width('100%')
      .height(52)
      .backgroundColor(enabled ? '#F22E6BE6' : Glass.FILL_SUBTLE)
      .borderRadius(AppRadius.CARD)
      .border({ width: Glass.BORDER_WIDTH, color: enabled ? '#66BFD6FF' : Glass.BORDER_SOFT })
      .shadow(enabled ? AppShadow.SOFT : AppShadow.NONE)
      .onClick(action)
  }

  @Builder
  secondaryAction(label: string, id: string, action: () => void) {
    Text(label)
      .id(id)
      .fontSize(AppFont.LABEL)
      .fontColor(AppColors.DARK_INK)
      .textAlign(TextAlign.Center)
      .width('100%')
      .height(46)
      .backgroundColor(Glass.FILL)
      .borderRadius(AppRadius.CARD)
      .border({ width: Glass.BORDER_WIDTH, color: Glass.BORDER_SOFT })
      .onClick(action)
  }

  build() {
    Stack() {
      HarnessBackground()
      Column({ space: AppSpacing.GAP }) {
        Column({ space: 2 }) {
          Text('DeepSeek Harness').fontSize(AppFont.SUBTITLE).fontWeight(FontWeight.Medium).fontColor(AppColors.ON_ATMOSPHERE)
          Text('鸿蒙客户端 · 预览版').fontSize(AppFont.CAPTION).fontColor(AppColors.INK_WEAK)
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')

        Column({ space: 6 }) {
          Text('探索未至之境').fontSize(AppFont.DISPLAY).fontWeight(FontWeight.Bold).fontColor(AppColors.ON_ATMOSPHERE)
          Text(this.message).fontSize(AppFont.CAPTION).fontColor(AppColors.INK_WEAK)
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .margin({ top: 26, bottom: 6 })

        this.statusCard()

        if (this.ui.failureDetail.length > 0) {
          Text(this.ui.failureDetail).fontSize(AppFont.CAPTION).fontColor(AppColors.DANGER).width('100%')
        }
        if (this.ui.notice.length > 0) {
          Text(this.ui.notice)
            .fontSize(AppFont.CAPTION)
            .fontColor(this.ui.noticeIsError ? AppColors.WARN : AppColors.OK)
            .width('100%')
        }

        this.primaryAction('扫码或粘贴配对二维码', 'openPairingButton', true, () => {
          router.pushUrl({ url: 'pages/PairingPage' });
        })
        this.primaryAction('进入工作区', 'openWorkspaceButton',
          this.ui.connection === GatewayConnectionState.CONNECTED, () => {
            router.pushUrl({ url: 'pages/WorkspacePage' });
          })
        this.secondaryAction('设置', 'openSettingsButton', () => {
          router.pushUrl({ url: 'pages/SettingsPage' });
        })
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
