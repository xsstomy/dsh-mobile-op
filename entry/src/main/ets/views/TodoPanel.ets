/**
 * Live task list above the composer (WebUI parity: ui-conversation/TodoPanel.tsx).
 *
 * Collapsed by default - the header already carries `任务` + the per-status
 * counts. The expanded list is height-bounded and scrolls on its own, so a long
 * plan can never push the composer off screen (see B13).
 */
import { AppColors, AppFont, AppRadius, AppShadow, Glass } from '../common/Constants';
import { TodoRow, todoProgressLabel, todoProgressOf } from '../sync/Todos';

/** Expanded list cap; taller lists scroll inside the card. */
const LIST_MAX_HEIGHT = 240;

@Component
export struct TodoPanel {
  @Prop todos: TodoRow[] | null = null;
  @State collapsed: boolean = true;

  /** Status glyphs mirror the WebUI artboard (done ring / spinner / dashed ring). */
  private statusSymbol(status: string): Resource {
    if (status === 'completed') {
      return $r('sys.symbol.checkmark_circle');
    }
    if (status === 'in_progress') {
      return $r('sys.symbol.arrow_counterclockwise');
    }
    return $r('sys.symbol.circle_dashed');
  }

  private statusColor(status: string): ResourceColor {
    if (status === 'completed') {
      return AppColors.SUCCESS;
    }
    if (status === 'in_progress') {
      return AppColors.AMBER;
    }
    return AppColors.INK_WEAK;
  }

  @Builder
  header() {
    Row({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.list_checkmark'))
        .fontSize(14)
        .fontColor([AppColors.INK_WEAK])
      Text('任务').fontSize(AppFont.LABEL).fontColor(AppColors.DARK_INK)
      Text(todoProgressLabel(todoProgressOf(this.todos)))
        .fontSize(AppFont.CAPTION)
        .fontColor(AppColors.INK_WEAK)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      SymbolGlyph(this.collapsed ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
        .fontSize(14)
        .fontColor([AppColors.MIST])
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.collapsed = !this.collapsed;
    })
  }

  @Builder
  rows() {
    Scroll() {
      Column({ space: 8 }) {
        ForEach(this.todos ?? [], (todo: TodoRow, index: number) => {
          Row({ space: 8 }) {
            SymbolGlyph(this.statusSymbol(todo.status))
              .fontSize(14)
              .fontColor([this.statusColor(todo.status)])
            Text(todo.content)
              .fontSize(AppFont.LABEL)
              .fontColor(todo.status === 'completed' ? AppColors.INK_WEAK : AppColors.DARK_INK)
              .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        }, (todo: TodoRow, index: number) =>
          index.toString() + '-' + todo.status + '-' + todo.content.length.toString())
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .constraintSize({ maxHeight: LIST_MAX_HEIGHT })
    .scrollBar(BarState.Auto)
  }

  build() {
    Column({ space: 10 }) {
      this.header()
      if (!this.collapsed) {
        this.rows()
      }
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
    .backgroundColor(Glass.FILL)
    .borderRadius(AppRadius.CARD)
    .border({ width: Glass.BORDER_WIDTH, color: Glass.BORDER })
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK, Glass.blurOptions())
    .shadow(AppShadow.CARD)
  }
}