/**
 * 「深度求索中…」 indicator: shown at the tail of the message list while the
 * agent is working and no answer text is streaming yet (upstream: the reasoning
 * spinner above the incoming bubble).
 *
 * The elapsed clock lives inside this component, so the 250 ms tick only exists
 * while the node is mounted — the page mounts it conditionally and never has to
 * start/stop a timer of its own.
 */
import { AppColors, AppFont } from '../common/Constants';

/** 1 → 6 dots; an explicit table because ArkTS has no `String.repeat`. */
const DOT_STEPS: string[] = ['.', '..', '...', '....', '.....', '......'];
/** Fixed dot column width: the row must not reflow as the dots grow. */
const DOT_WIDTH: number = 40;

@Component
export struct ThinkingIndicator {
  /** Epoch ms the turn started; `<= 0` = running but the start is unknown. */
  @Prop startedAt: number = 0;
  @State private step: number = 0;
  @State private now: number = 0;
  private timer: number = -1;

  aboutToAppear(): void {
    this.now = Date.now();
    this.step = 0;
    this.timer = setInterval(() => {
      this.step = (this.step + 1) % DOT_STEPS.length;
      this.now = Date.now();
    }, 250);
  }

  aboutToDisappear(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  /** `12s` / `1m05s`; empty while the start time is unknown. */
  private elapsedText(): string {
    const startedAt = this.startedAt;
    if (startedAt <= 0 || this.now <= startedAt) {
      return '';
    }
    const seconds = Math.floor((this.now - startedAt) / 1000);
    if (seconds < 60) {
      return `${seconds}s`;
    }
    const minutes = Math.floor(seconds / 60);
    const rest = seconds - minutes * 60;
    return `${minutes}m${rest < 10 ? '0' : ''}${rest}s`;
  }

  build() {
    Row({ space: 6 }) {
      Text('深度求索中').fontSize(AppFont.CAPTION).fontColor(AppColors.PURPLE)
      Text(DOT_STEPS[this.step])
        .fontSize(AppFont.CAPTION)
        .fontColor(AppColors.PURPLE)
        .width(DOT_WIDTH)
        .textAlign(TextAlign.Start)
      if (this.elapsedText().length > 0) {
        Text(this.elapsedText()).fontSize(10).fontColor(AppColors.INK_WEAK)
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: 6, right: 6, top: 6, bottom: 6 })
  }
}
