/**
 * Pairing: scan or paste the Base64URL payload produced by the WebUI, with an
 * optional endpoint override (emulator/LAN).
 */
import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import { scanBarcode, scanCore } from '@kit.ScanKit';
import { GatewayConnectionState } from '../gateway/GatewayClient';
import { GatewayStore } from '../store/GatewayStore';
import { UI_KEY, UiSnapshot, emptyUiSnapshot } from '../store/UiState';
import { AppColors, AppFont, AppRadius, AppSpacing, AppShadow, Glass } from '../common/Constants';
import { HarnessBackground } from '../common/HarnessBackground';
import { ConnectionPanel } from '../views/ConnectionPanel';

const TAG = 'PairingPage';

@Entry
@Component
struct PairingPage {
  @StorageLink(UI_KEY) ui: UiSnapshot = emptyUiSnapshot();
  /** Status/navigation bar insets (vp) published by WindowChrome. */
  @StorageProp('gwInsetTop') insetTop: number = 0;
  @StorageProp('gwInsetBottom') insetBottom: number = 0;
  @State payload: string = '';
  @State endpoint: string = '';
  @State busy: boolean = false;
  @State error: string = '';
  private store: GatewayStore = GatewayStore.current;

  private async pair(): Promise<void> {
    this.error = '';
    if (this.payload.replace(/^\s+|\s+$/g, '').length === 0) {
      this.error = '请先粘贴配对内容';
      return;
    }
    this.busy = true;
    try {
      await this.store.pair(this.payload, this.endpoint.replace(/^\s+|\s+$/g, ''));
      this.waitForConnection();
    } catch (error) {
      this.error = (error as Error).message;
    }
    this.busy = false;
  }

  private waitForConnection(): void {
    let attempts = 0;
    const tick = (): void => {
      attempts += 1;
      if (this.ui.connection === GatewayConnectionState.CONNECTED) {
        router.back();
        return;
      }
      if (attempts < 20) {
        setTimeout(tick, 500);
      }
    };
    setTimeout(tick, 500);
  }

  private async scan(): Promise<void> {
    this.error = '';
    try {
      const options: scanBarcode.ScanOptions = {
        scanTypes: [scanCore.ScanType.ALL],
        enableMultiMode: false,
        enableAlbum: false
      };
      const result = await scanBarcode.startScanForResult(getContext(this) as common.Context, options);
      const text = result.originalValue ?? '';
      if (text.length > 0) {
        this.payload = text;
      }
    } catch (error) {
      hilog.warn(0x0000, TAG, 'scan unavailable: %{public}s', JSON.stringify(error));
      this.error = '当前设备无法调用系统扫码（模拟器无相机），请改用「粘贴配对内容」';
    }
  }

  /**
   * 快捷重新连接：已有本地凭据时不再扫码，直接用保存的 endpoint + token 重连。
   * 没有凭据（例如刚解除配对）就提示去配对，而不是抛一个没有出路的错误。
   */
  private async reconnect(): Promise<void> {
    this.error = '';
    this.busy = true;
    try {
      const saved = await this.store.hasStoredCredential();
      if (!saved) {
        this.error = '没有已保存的连接，请先扫码或粘贴配对内容';
        return;
      }
      await this.store.connectSaved();
      this.waitForConnection();
    } catch (failure) {
      this.error = (failure as Error).message;
    }
    this.busy = false;
  }

  /** 断开链接但保留本地凭据，之后可随时「快捷重新连接」。 */
  private disconnect(): void {
    this.error = '';
    this.store.disconnect();
  }

  @Builder
  glassCircle(glyph: Resource, action: () => void) {
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

  build() {
    Stack() {
      HarnessBackground()
      Column({ space: AppSpacing.GAP }) {
        Row({ space: 10 }) {
          this.glassCircle($r('sys.symbol.arrow_left'), () => {
            router.back();
          })
          Text('设备认证').fontSize(AppFont.HEADING).fontWeight(FontWeight.Bold).fontColor(AppColors.DARK_INK)
          Text(this.ui.connection === 'connected' ? '已连接' : '未连接')
            .fontSize(AppFont.CAPTION)
            .fontColor(this.ui.connection === 'connected' ? AppColors.SUCCESS : AppColors.INK_WEAK)
            .layoutWeight(1)
            .textAlign(TextAlign.End)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        // The header stays pinned; everything below it scrolls, so the saved
        // connections added under 快捷重连 can never be clipped off-screen.
        Scroll() {
          Column({ space: AppSpacing.GAP }) {
            Text('在 WebUI「移动设备」中生成二维码后扫码，或粘贴配对内容（Base64URL）')
              .fontSize(AppFont.CAPTION)
              .fontColor(AppColors.MIST)
              .width('100%')
              .margin({ top: 10 })

            Column({ space: 12 }) {
              Text('配对内容').fontSize(AppFont.CAPTION).fontColor(AppColors.INK_WEAK).width('100%')
              TextArea({ placeholder: '粘贴 qrPayload（Base64URL）', text: this.payload })
                .id('pairingPayload')
                .height(120)
                .width('100%')
                .fontSize(AppFont.CAPTION)
                .fontColor(AppColors.DARK_INK)
                .placeholderColor(AppColors.INK_WEAK)
                .backgroundColor(Glass.FILL_SUBTLE)
                .borderRadius(AppRadius.INPUT)
                .onChange((value: string) => {
                  this.payload = value;
                })
              Text('端点覆盖（可选）').fontSize(AppFont.CAPTION).fontColor(AppColors.INK_WEAK).width('100%')
              TextInput({ placeholder: 'ws://10.0.2.2:3081/ws/mobile', text: this.endpoint })
                .id('pairingEndpoint')
                .width('100%')
                .height(44)
                .fontSize(AppFont.LABEL)
                .fontColor(AppColors.DARK_INK)
                .placeholderColor(AppColors.INK_WEAK)
                .backgroundColor(Glass.FILL_SUBTLE)
                .borderRadius(AppRadius.INPUT)
                .onChange((value: string) => {
                  this.endpoint = value;
                })
            }
            .width('100%')
            .padding(14)
            .backgroundColor(Glass.FILL)
            .borderRadius(AppRadius.CARD)
            .border({ width: Glass.BORDER_WIDTH, color: Glass.BORDER })
            .backgroundBlurStyle(BlurStyle.COMPONENT_THICK, Glass.blurOptions())
            .shadow(AppShadow.CARD)

            if (this.error.length > 0) {
              Text(this.error).fontSize(AppFont.CAPTION).fontColor(AppColors.DANGER).width('100%')
            }
            if (this.ui.failureDetail.length > 0) {
              Text(this.ui.failureDetail).fontSize(AppFont.CAPTION).fontColor(AppColors.WARN).width('100%')
            }
            if (this.ui.notice.length > 0) {
              Text(this.ui.notice)
                .fontSize(AppFont.CAPTION)
                .fontColor(this.ui.noticeIsError ? AppColors.WARN : AppColors.OK)
                .width('100%')
            }

            Text('扫码').id('scanButton')
              .fontSize(AppFont.LABEL).fontColor(AppColors.DARK_INK).textAlign(TextAlign.Center)
              .width('100%').height(46)
              .backgroundColor(Glass.FILL)
              .borderRadius(AppRadius.CARD)
              .border({ width: Glass.BORDER_WIDTH, color: Glass.BORDER_SOFT })
              .onClick(() => {
                this.scan();
              })

            Text(this.busy ? '请稍候…' : '开始配对')
              .id('pairButton')
              .fontSize(AppFont.SUBTITLE)
              .fontColor(this.busy ? AppColors.INK_WEAK : AppColors.PAPER)
              .textAlign(TextAlign.Center)
              .width('100%')
              .height(52)
              .backgroundColor(this.busy ? Glass.FILL_SUBTLE : '#F22E6BE6')
              .borderRadius(AppRadius.CARD)
              .border({ width: Glass.BORDER_WIDTH, color: '#66BFD6FF' })
              .onClick(() => {
                if (!this.busy) {
                  this.pair();
                }
              })

            // 快捷重连 / 断开：已有本地凭据时不必再扫码；断开只丢 socket、保留凭据。
            Row({ space: 10 }) {
              Text(this.busy ? '重连中…' : '快捷重新连接')
                .id('reconnectButton')
                .fontSize(AppFont.LABEL)
                .fontColor(this.busy ? AppColors.INK_WEAK : AppColors.DARK_INK)
                .textAlign(TextAlign.Center)
                .layoutWeight(1)
                .height(46)
                .backgroundColor(this.busy ? Glass.FILL_SUBTLE : Glass.FILL)
                .borderRadius(AppRadius.CARD)
                .border({ width: Glass.BORDER_WIDTH, color: Glass.BORDER_SOFT })
                .onClick(() => {
                  if (!this.busy) {
                    this.reconnect();
                  }
                })
              Text('断开连接')
                .id('disconnectButton')
                .fontSize(AppFont.LABEL)
                .fontColor(this.ui.connection === 'connected' ? AppColors.DANGER : AppColors.INK_WEAK)
                .textAlign(TextAlign.Center)
                .layoutWeight(1)
                .height(46)
                .backgroundColor(Glass.FILL)
                .borderRadius(AppRadius.CARD)
                .border({ width: Glass.BORDER_WIDTH, color: Glass.BORDER_SOFT })
                .onClick(() => {
                  this.disconnect();
                })
            }
            .width('100%')

            ConnectionPanel()

            Text(`连接状态：${this.ui.connection} ${this.ui.connectionDetail}`)
              .fontSize(AppFont.CAPTION)
              .fontColor(AppColors.INK_WEAK)
              .width('100%')
              .padding(12)
              .backgroundColor(Glass.FILL_SUBTLE)
              .borderRadius(AppRadius.INPUT)
          }
          .width('100%')
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
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
