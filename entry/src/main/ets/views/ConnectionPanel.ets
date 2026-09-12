/**
 * Saved-connection list: manual switching between a gateway's listeners plus the
 * automatic LAN/public choice. One paired token authenticates on every listener
 * of the same gateway, so switching never needs a new QR scan.
 */
import { AppColors, AppFont, AppRadius, AppSpacing, Glass } from '../common/Constants';
import { GatewayStore } from '../store/GatewayStore';
import { UI_KEY, UiSnapshot, emptyUiSnapshot } from '../store/UiState';
import { SavedEndpoint, endpointKindLabel } from '../sync/Endpoints';

@Component
export struct ConnectionPanel {
  @StorageLink(UI_KEY) ui: UiSnapshot = emptyUiSnapshot();
  @State draft: string = '';
  @State error: string = '';
  @State message: string = '';
  @State busyUrl: string = '';
  private store: GatewayStore = GatewayStore.current;

  private async switchTo(url: string): Promise<void> {
    if (this.busyUrl.length > 0) {
      return;
    }
    this.busyUrl = url;
    this.error = '';
    try {
      await this.store.switchEndpoint(url);
    } catch (failure) {
      this.error = (failure as Error).message;
    }
    this.busyUrl = '';
  }

  private async add(): Promise<void> {
    this.error = '';
    this.message = '';
    const ok = await this.store.addEndpoint(this.draft);
    if (!ok) {
      this.error = '地址无效：请输入 IP（如 192.168.1.5）或完整的 ws:// 地址';
      return;
    }
    this.draft = '';
  }

  /** Sweep the current /24 for the gateway's LAN listener on port 3081. */
  private async scan(): Promise<void> {
    this.error = '';
    this.message = '';
    const found = await this.store.scanLan();
    this.message = found > 0 ? `发现 ${found} 个局域网地址` : '没有发现局域网网关';
  }

  @Builder
  endpointRow(item: SavedEndpoint) {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(endpointKindLabel(item.kind))
          .fontSize(AppFont.CAPTION)
          .fontColor(AppColors.DARK_INK)
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .backgroundColor(Glass.FILL_SUBTLE)
          .borderRadius(AppRadius.PILL)
        Text(item.url)
          .fontSize(AppFont.CAPTION)
          .fontColor(AppColors.INK_WEAK)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (item.url === this.ui.endpoint) {
          Text('当前').fontSize(AppFont.CAPTION).fontColor(AppColors.SUCCESS)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row({ space: 10 }) {
        Text(this.busyUrl === item.url ? '切换中…' : '切换')
          .fontSize(AppFont.CAPTION)
          .fontColor(AppColors.DARK_INK)
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
          .height(38)
          .backgroundColor(Glass.FILL)
          .borderRadius(AppRadius.CARD)
          .border({ width: Glass.BORDER_WIDTH, color: Glass.BORDER_SOFT })
          .onClick(() => {
            if (item.url !== this.ui.endpoint && this.busyUrl.length === 0) {
              this.switchTo(item.url);
            }
          })
        if (item.url !== this.ui.endpoint) {
          Text('删除')
            .fontSize(AppFont.CAPTION)
            .fontColor(AppColors.DANGER)
            .textAlign(TextAlign.Center)
            .width(64)
            .height(38)
            .backgroundColor(Glass.FILL)
            .borderRadius(AppRadius.CARD)
            .border({ width: Glass.BORDER_WIDTH, color: Glass.BORDER_SOFT })
            .onClick(() => {
              this.store.forgetEndpoint(item.url);
            })
        }
      }
      .width('100%')
    }
    .width('100%')
    .padding(10)
    .backgroundColor(item.url === this.ui.endpoint ? Glass.FILL : Glass.FILL_SUBTLE)
    .borderRadius(AppRadius.CARD)
    .border({ width: Glass.BORDER_WIDTH, color: Glass.BORDER_SOFT })
  }

  build() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text('已保存的连接').fontSize(AppFont.LABEL).fontColor(AppColors.DARK_INK).layoutWeight(1)
        Text('自动切换').fontSize(AppFont.CAPTION).fontColor(AppColors.INK_WEAK)
        Toggle({ type: ToggleType.Switch, isOn: this.ui.autoSwitch })
          .id('autoSwitchToggle')
          .selectedColor(AppColors.SUCCESS)
          .onChange((isOn: boolean) => {
            this.store.setAutoSwitch(isOn);
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text('自动：在局域网内优先用局域网地址，出门自动回到公网地址。')
        .fontSize(AppFont.CAPTION)
        .fontColor(AppColors.MIST)
        .width('100%')

      if (this.ui.savedEndpoints.length === 0) {
        Text('还没有保存的连接，配对成功后会自动记录。')
          .fontSize(AppFont.CAPTION)
          .fontColor(AppColors.INK_WEAK)
          .width('100%')
      }
      ForEach(this.ui.savedEndpoints, (item: SavedEndpoint) => {
        this.endpointRow(item)
      }, (item: SavedEndpoint) => item.url)

      Row({ space: 8 }) {
        TextInput({ placeholder: '局域网地址，如 192.168.1.5', text: this.draft })
          .id('endpointDraft')
          .layoutWeight(1)
          .height(42)
          .fontSize(AppFont.CAPTION)
          .fontColor(AppColors.DARK_INK)
          .placeholderColor(AppColors.INK_WEAK)
          .backgroundColor(Glass.FILL_SUBTLE)
          .borderRadius(AppRadius.INPUT)
          .onChange((value: string) => {
            this.draft = value;
          })
        Text('添加')
          .id('addEndpointButton')
          .fontSize(AppFont.CAPTION)
          .fontColor(AppColors.DARK_INK)
          .textAlign(TextAlign.Center)
          .width(64)
          .height(42)
          .backgroundColor(Glass.FILL)
          .borderRadius(AppRadius.CARD)
          .border({ width: Glass.BORDER_WIDTH, color: Glass.BORDER_SOFT })
          .onClick(() => {
            this.add();
          })
      }
      .width('100%')

      Text(this.ui.endpointScanning ? '正在扫描局域网…' : '扫描局域网网关')
        .id('scanLanButton')
        .fontSize(AppFont.CAPTION)
        .fontColor(this.ui.endpointScanning ? AppColors.INK_WEAK : AppColors.DARK_INK)
        .textAlign(TextAlign.Center)
        .width('100%')
        .height(40)
        .backgroundColor(Glass.FILL_SUBTLE)
        .borderRadius(AppRadius.CARD)
        .border({ width: Glass.BORDER_WIDTH, color: Glass.BORDER_SOFT })
        .onClick(() => {
          if (!this.ui.endpointScanning) {
            this.scan();
          }
        })

      if (this.message.length > 0) {
        Text(this.message).fontSize(AppFont.CAPTION).fontColor(AppColors.OK).width('100%')
      }
      if (this.error.length > 0) {
        Text(this.error).fontSize(AppFont.CAPTION).fontColor(AppColors.DANGER).width('100%')
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor(Glass.FILL)
    .borderRadius(AppRadius.CARD)
    .border({ width: Glass.BORDER_WIDTH, color: Glass.BORDER })
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK, Glass.blurOptions())
  }
}
