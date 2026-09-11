/**
 * Run statistics bar + detail sheet (upstream: SessionStatsBanner / SessionStatsSheet).
 * Data source: `session-stats` projection (turns/steps/timings + token usage +
 * context pressure), refreshed on session select, on turn end and on demand.
 */
import { AppColors, AppFont, AppRadius, AppSpacing, AppShadow, Glass } from '../common/Constants';
import { durationLabel, tokenLabel } from '../common/Format';
import { GatewayStore } from '../store/GatewayStore';
import { StatsRow } from '../store/UiState';

/** `12.3s` / `1m20s`, or `—` when the host reported no duration. */
export function formatDuration(milliseconds: number): string {
  const label = durationLabel(milliseconds);
  return label.length === 0 ? '—' : label;
}

@Component
export struct SessionStatsBar {
  @Prop stats: StatsRow | null = null;
  @Prop busy: boolean = false;
  @State sheetOpen: boolean = false;
  private store: GatewayStore = GatewayStore.current;

  private ttftAverage(): string {
    const stats = this.stats;
    if (stats === null || stats.ttftSteps <= 0) {
      return '—';
    }
    return formatDuration(stats.ttftMs / stats.ttftSteps);
  }

  /** Cache hit share, or `—` until the host reports token usage. */
  private cacheHitLabel(): string {
    const percent = this.stats?.cacheHitPercent ?? -1;
    return percent < 0 ? '—' : `${percent}%`;
  }

  private decodeRate(): string {
    const stats = this.stats;
    if (stats === null || stats.decodeMs <= 0) {
      return '—';
    }
    return `${(stats.decodeTokens / (stats.decodeMs / 1000)).toFixed(1)} tok/s`;
  }

  @Builder
  metric(label: string, value: string) {
    Column({ space: 2 }) {
      Text(value).fontSize(AppFont.LABEL).fontColor(AppColors.DARK_INK).width('100%')
      Text(label).fontSize(AppFont.CAPTION).fontColor(AppColors.INK_WEAK).width('100%')
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  detailSheet() {
    Column({ space: AppSpacing.GAP }) {
      Text('运行统计').fontSize(AppFont.HEADING).fontWeight(FontWeight.Bold).fontColor(AppColors.DARK_INK)
      Row({ space: 10 }) {
        this.metric('轮次', `${this.stats?.turns ?? 0}`)
        this.metric('步骤', `${this.stats?.steps ?? 0}`)
        this.metric('上下文', `${this.stats?.contextUsedPercent ?? 0}%`)
        this.metric('缓存命中', this.cacheHitLabel())
      }
      .width('100%')
      Row({ space: 10 }) {
        this.metric('LLM 用时', formatDuration(this.stats?.llmMs ?? 0))
        this.metric('工具用时', formatDuration(this.stats?.toolMs ?? 0))
        this.metric('首 token', this.ttftAverage())
      }
      .width('100%')
      Row({ space: 10 }) {
        this.metric('输出速率', this.decodeRate())
        this.metric('输入 token', tokenLabel(this.stats?.inputTokens ?? 0))
        this.metric('输出 token', tokenLabel(this.stats?.outputTokens ?? 0))
      }
      .width('100%')
      Row({ space: 10 }) {
        this.metric('缓存读取', tokenLabel(this.stats?.cacheReadTokens ?? 0))
        this.metric('缓存写入', tokenLabel(this.stats?.cacheWriteTokens ?? 0))
        Text('')
          .layoutWeight(1)
      }
      .width('100%')
      Text('刷新')
        .fontSize(AppFont.LABEL)
        .fontColor(AppColors.DARK_INK)
        .textAlign(TextAlign.Center)
        .width('100%')
        .height(42)
        .backgroundColor(Glass.FILL)
        .borderRadius(AppRadius.CARD)
        .border({ width: Glass.BORDER_WIDTH, color: Glass.BORDER_SOFT })
        .onClick(() => {
          this.store.refreshSessionStats(this.store.activeSessionId);
        })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(AppSpacing.PAGE)
  }

  build() {
    Row({ space: 8 }) {
      Text(this.busy ? '生成中…' : `${this.stats?.turns ?? 0} 轮 · ${this.stats?.steps ?? 0} 步`)
        .fontSize(AppFont.CAPTION)
        .fontColor(AppColors.INK_WEAK)
      Text(`上下文已用 ${this.stats?.contextUsedPercent ?? 0}%`)
        .fontSize(AppFont.CAPTION)
        .fontColor((this.stats?.contextUsedPercent ?? 0) >= 80 ? AppColors.WARN : AppColors.INK_WEAK)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      // Cache-hit share sits right after the context metric (user request).
      Text(`缓存命中 ${this.cacheHitLabel()}`)
        .fontSize(AppFont.CAPTION)
        .fontColor(AppColors.INK_WEAK)
        .maxLines(1)
      Text('详情 ⌃').fontSize(AppFont.CAPTION).fontColor(AppColors.MIST)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .backgroundColor(Glass.FILL_SUBTLE)
    .borderRadius(AppRadius.PILL)
    .border({ width: Glass.BORDER_WIDTH, color: Glass.BORDER_SOFT })
    .onClick(() => {
      this.sheetOpen = true;
    })
    .bindSheet($$this.sheetOpen, this.detailSheet(), {
      height: 420,
      backgroundColor: '#F20D2440',
      blurStyle: BlurStyle.NONE,
      showClose: true
    })
  }
}
