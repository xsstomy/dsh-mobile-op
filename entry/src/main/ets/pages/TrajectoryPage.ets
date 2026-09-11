/**
 * Trajectory page: event timeline with per-kind labels and an inspectable detail
 * sheet for the raw payload (upstream: TrajectoryUi + TrajectoryEventDetailSheet).
 */
import { router } from '@kit.ArkUI';
import { GatewayStore } from '../store/GatewayStore';
import { UI_KEY, UiSnapshot, emptyUiSnapshot } from '../store/UiState';
import { AppColors, AppFont, AppRadius, AppSpacing, AppShadow, Glass } from '../common/Constants';
import { TrajectoryKind, TrajectoryRow, countByKind, turnDurations } from '../projection/Trajectory';
import { formatDuration } from '../views/SessionStatsBar';
import { HarnessBackground } from '../common/HarnessBackground';

function kindColor(kind: TrajectoryKind, isError: boolean): ResourceColor {
  if (isError) {
    return AppColors.DANGER;
  }
  switch (kind) {
    case TrajectoryKind.TURN:
      return AppColors.BRAND;
    case TrajectoryKind.STEP:
      return AppColors.MIST;
    case TrajectoryKind.USER:
      return AppColors.SUCCESS;
    case TrajectoryKind.ASSISTANT:
      return AppColors.DARK_INK;
    case TrajectoryKind.REASONING:
      return AppColors.PURPLE;
    case TrajectoryKind.TOOL:
      return AppColors.AMBER;
    case TrajectoryKind.TOOL_RESULT:
      return AppColors.ORANGE;
    case TrajectoryKind.CONTEXT:
      return AppColors.INK_WEAK;
    default:
      return AppColors.INK_WEAK;
  }
}

function clockOf(millis: number): string {
  if (millis <= 0) {
    return '';
  }
  const date = new Date(millis);
  const minutes = `${date.getMinutes()}`.padStart(2, '0');
  const seconds = `${date.getSeconds()}`.padStart(2, '0');
  return `${date.getHours()}:${minutes}:${seconds}`;
}

@Entry
@Component
struct TrajectoryPage {
  @StorageLink(UI_KEY) ui: UiSnapshot = emptyUiSnapshot();
  /** Status/navigation bar insets (vp) published by WindowChrome. */
  @StorageProp('gwInsetTop') insetTop: number = 0;
  @StorageProp('gwInsetBottom') insetBottom: number = 0;
  @State detailOpen: boolean = false;
  @State selected: TrajectoryRow | null = null;
  @State filter: string = 'all';
  private store: GatewayStore = GatewayStore.current;
  private scroller: Scroller = new Scroller();

  async aboutToAppear(): Promise<void> {
    await this.store.loadTrajectory(this.ui.activeSessionId);
  }

  private visibleRows(): TrajectoryRow[] {
    if (this.filter === 'all') {
      return this.ui.trajectory;
    }
    if (this.filter === 'tools') {
      const rows: TrajectoryRow[] = [];
      for (const row of this.ui.trajectory) {
        if (row.kind === TrajectoryKind.TOOL || row.kind === TrajectoryKind.TOOL_RESULT) {
          rows.push(row);
        }
      }
      return rows;
    }
    if (this.filter === 'messages') {
      const rows: TrajectoryRow[] = [];
      for (const row of this.ui.trajectory) {
        if (row.kind === TrajectoryKind.USER || row.kind === TrajectoryKind.ASSISTANT) {
          rows.push(row);
        }
      }
      return rows;
    }
    const rows: TrajectoryRow[] = [];
    for (const row of this.ui.trajectory) {
      if (row.kind === TrajectoryKind.TURN || row.kind === TrajectoryKind.STEP) {
        rows.push(row);
      }
    }
    return rows;
  }

  private summaryLine(): string {
    const rows = this.ui.trajectory;
    const durations = turnDurations(rows);
    let total = 0;
    durations.forEach((value: number) => {
      total += value;
    });
    return `${rows.length} 事件 · ${countByKind(rows, TrajectoryKind.TOOL)} 次工具 · 合计 ${formatDuration(total)}`;
  }

  @Builder
  chip(label: string, key: string) {
    Text(label)
      .fontSize(AppFont.CAPTION)
      .fontColor(this.filter === key ? AppColors.INK : AppColors.INK_WEAK)
      .padding({ left: 12, right: 12, top: 5, bottom: 5 })
      .backgroundColor(this.filter === key ? AppColors.BRAND : Glass.FILL)
      .borderRadius(AppRadius.PILL)
      .border({
        width: Glass.BORDER_WIDTH,
        color: this.filter === key ? '#66BFD6FF' : Glass.BORDER_SOFT
      })
      .onClick(() => {
        this.filter = key;
      })
  }

  @Builder
  rowView(row: TrajectoryRow) {
    Row({ space: 10 }) {
      Circle({ width: 8, height: 8 })
        .fill(kindColor(row.kind, row.isError))
        .margin({ top: 6 })

      Column({ space: 4 }) {
        Row({ space: 8 }) {
          Text(row.title)
            .fontSize(AppFont.LABEL)
            .fontColor(kindColor(row.kind, row.isError))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(clockOf(row.time)).fontSize(10).fontColor(AppColors.INK_WEAK)
          Text(`#${row.seq}`).fontSize(10).fontColor(Glass.CODE_LABEL)
        }
        .width('100%')
        if (row.subtitle.length > 0) {
          Text(row.subtitle)
            .fontSize(AppFont.CAPTION)
            .fontColor(AppColors.INK_WEAK)
            .width('100%')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        if (row.type !== row.title) {
          Text(row.type).fontSize(9).fontColor(Glass.CODE_LABEL).width('100%')
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ top: 10, bottom: 10, left: 6, right: 6 })
    .border({ width: { bottom: 1 }, color: Glass.BORDER_SOFT })
    .onClick(() => {
      this.selected = row;
      this.detailOpen = true;
    })
  }

  @Builder
  detailSheet() {
    Column({ space: AppSpacing.GAP }) {
      Text(this.selected === null ? '事件详情' : this.selected.title)
        .fontSize(AppFont.HEADING)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColors.DARK_INK)
      if (this.selected !== null) {
        Row({ space: 10 }) {
          Text(`类型 ${this.selected.type}`).fontSize(AppFont.CAPTION).fontColor(AppColors.MIST)
          Text(`seq ${this.selected.seq}`).fontSize(AppFont.CAPTION).fontColor(AppColors.INK_WEAK)
          Text(`turn ${this.selected.turn} · step ${this.selected.step}`)
            .fontSize(AppFont.CAPTION)
            .fontColor(AppColors.INK_WEAK)
        }
        .width('100%')
        Scroll() {
          Text(this.selected.detail)
            .fontSize(11)
            .fontColor(AppColors.DARK_INK)
            .width('100%')
            .textAlign(TextAlign.Start)
        }
        .layoutWeight(1)
        .width('100%')
        .padding(10)
        .backgroundColor(Glass.CODE_FILL)
        .borderRadius(AppRadius.CARD_SMALL)
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(AppSpacing.PAGE)
  }

  build() {
    Stack() {
      HarnessBackground()
      Column({ space: AppSpacing.GAP }) {
        Row({ space: 10 }) {
          Stack() {
            SymbolGlyph($r('sys.symbol.arrow_left')).fontSize(18).fontColor([AppColors.DARK_INK])
          }
          .width(38)
          .height(38)
          .borderRadius(AppRadius.CIRCLE)
          .backgroundColor(Glass.FILL)
          .border({ width: Glass.BORDER_WIDTH, color: Glass.BORDER })
          .backgroundBlurStyle(BlurStyle.COMPONENT_THICK, Glass.blurOptions())
          .onClick(() => {
            router.back();
          })
          Column({ space: 2 }) {
            Text('轨迹').fontSize(AppFont.HEADING).fontWeight(FontWeight.Bold).fontColor(AppColors.DARK_INK)
            Text(this.ui.activeSessionTitle.length > 0 ? this.ui.activeSessionTitle : '未选择会话')
              .fontSize(AppFont.CAPTION)
              .fontColor(AppColors.INK_WEAK)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          Text('刷新')
            .fontSize(AppFont.CAPTION)
            .fontColor(AppColors.MIST)
            .onClick(() => {
              this.store.loadTrajectory(this.ui.activeSessionId);
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Text(this.ui.trajectoryLoading ? '加载中…' : this.summaryLine())
          .fontSize(AppFont.CAPTION)
          .fontColor(AppColors.INK_WEAK)
          .width('100%')

        Row({ space: 8 }) {
          this.chip('全部', 'all')
          this.chip('阶段', 'phases')
          this.chip('消息', 'messages')
          this.chip('工具', 'tools')
        }
        .width('100%')

        if (this.ui.trajectory.length === 0 && !this.ui.trajectoryLoading) {
          Text('该会话还没有可展示的事件').fontSize(AppFont.CAPTION).fontColor(AppColors.INK_WEAK).width('100%')
        }

        List({ space: 0, scroller: this.scroller }) {
          ForEach(this.visibleRows(), (row: TrajectoryRow) => {
            ListItem() {
              this.rowView(row)
            }
          }, (row: TrajectoryRow) => `${row.seq}-${row.type}`)
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
    .bindSheet($$this.detailOpen, this.detailSheet(), {
      height: 520,
      backgroundColor: '#F20D2440',
      blurStyle: BlurStyle.NONE,
      showClose: true
    })
  }
}
