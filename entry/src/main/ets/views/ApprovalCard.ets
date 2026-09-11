/**
 * Tool approval card (upstream: ApprovalRequestCard.kt).
 * One-shot decision only: allow this call or reject it.
 */
import { AppColors, AppFont, AppRadius, AppSpacing, AppShadow, Glass } from '../common/Constants';
import { GatewayStore } from '../store/GatewayStore';
import { ApprovalCardRow, emptyApprovalCard } from '../store/UiState';

@Component
export struct ApprovalCard {
  @Prop card: ApprovalCardRow = emptyApprovalCard();
  @State busy: boolean = false;
  @State error: string = '';
  private store: GatewayStore = GatewayStore.current;

  private async respond(outcome: string): Promise<void> {
    this.busy = true;
    this.error = '';
    try {
      await this.store.respondApproval(this.card.rpcId, outcome);
    } catch (failure) {
      this.error = (failure as Error).message;
    }
    this.busy = false;
  }

  build() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text('等待审批').fontSize(AppFont.CAPTION).fontColor(AppColors.DANGER)
        Text(this.card.toolName.length > 0 ? this.card.toolName : 'tool')
          .fontSize(AppFont.CAPTION)
          .fontColor(AppColors.MIST)
        Text(this.card.replay ? '（重放）' : '')
          .fontSize(AppFont.CAPTION)
          .fontColor(AppColors.INK_WEAK)
          .layoutWeight(1)
      }
      .width('100%')

      Text(this.card.reason.length > 0 ? this.card.reason : '该操作需要一次性授权')
        .fontSize(AppFont.BODY)
        .fontColor(AppColors.DARK_INK)
        .width('100%')

      if (this.error.length > 0) {
        Text(this.error).fontSize(AppFont.CAPTION).fontColor(AppColors.DANGER).width('100%')
      }

      Row({ space: 10 }) {
        Text('拒绝')
          .fontSize(AppFont.LABEL)
          .fontColor(AppColors.DANGER)
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
          .height(40)
          .backgroundColor(Glass.FILL)
          .borderRadius(AppRadius.PILL)
          .border({ width: Glass.BORDER_WIDTH, color: Glass.BORDER_SOFT })
          .onClick(() => {
            if (!this.busy) {
              this.respond('rejected');
            }
          })
        Text(this.busy ? '提交中…' : '允许一次')
          .fontSize(AppFont.LABEL)
          .fontColor(this.busy ? AppColors.INK_WEAK : AppColors.PAPER)
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
          .height(40)
          .backgroundColor(this.busy ? Glass.FILL_SUBTLE : AppColors.BRAND)
          .borderRadius(AppRadius.PILL)
          .onClick(() => {
            if (!this.busy) {
              this.respond('allowed-once');
            }
          })
      }
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(14)
    .backgroundColor(Glass.FILL_STRONG)
    .borderRadius(AppRadius.CARD)
    .border({ width: Glass.BORDER_WIDTH, color: '#66FF5C6C' })
    .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK, Glass.blurOptions())
    .shadow(AppShadow.CARD)
  }
}
