/**
 * Task list + current goal (upstream: TaskGoalUi.kt).
 * Tasks are read-only (they come from the agent's `todo_write`); the goal is
 * editable and every write carries the `{id, revision}` CAS reference.
 */
import { AppColors, AppFont, AppRadius, AppSpacing, Glass } from '../common/Constants';
import { GatewayStore } from '../store/GatewayStore';
import { GoalRow } from '../store/UiState';
import { TodoRow } from '../sync/Todos';

@Component
export struct TaskGoalPanel {
  @Prop todos: TodoRow[] | null = null;
  @Prop goal: GoalRow | null = null;
  @State editing: boolean = false;
  @State draft: string = '';
  @State busy: boolean = false;
  @State error: string = '';
  private store: GatewayStore = GatewayStore.current;

  /** DSH todo statuses rendered with system symbols (todo_write projection). */
  private statusSymbol(status: string): Resource {
    if (status === 'completed') {
      return $r('sys.symbol.checkmark_circle');
    }
    if (status === 'in_progress') {
      return $r('sys.symbol.arrow_counterclockwise');
    }
    return $r('sys.symbol.circle');
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

  private phaseLabel(phase: string): string {
    switch (phase) {
      case 'active':
        return '进行中';
      case 'paused':
        return '已暂停';
      case 'blocked':
        return '受阻';
      case 'done':
        return '已完成';
      default:
        return phase;
    }
  }

  private async run(action: () => Promise<void>): Promise<void> {
    this.busy = true;
    this.error = '';
    try {
      await action();
    } catch (failure) {
      this.error = (failure as Error).message;
    }
    this.busy = false;
  }

  @Builder
  todoRows() {
    Column({ space: 6 }) {
      Text('任务').fontSize(AppFont.CAPTION).fontColor(AppColors.INK_WEAK).width('100%')
      if (this.todos === null || this.todos.length === 0) {
        Text('当前会话还没有任务列表').fontSize(AppFont.CAPTION).fontColor(AppColors.INK_WEAK).width('100%')
      }
      ForEach(this.todos ?? [], (todo: TodoRow) => {
        Row({ space: 8 }) {
          SymbolGlyph(this.statusSymbol(todo.status)).fontSize(14).fontColor([this.statusColor(todo.status)])
          Text(todo.content)
            .fontSize(AppFont.LABEL)
            .fontColor(todo.status === 'completed' ? AppColors.INK_WEAK : AppColors.DARK_INK)
            .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
      }, (todo: TodoRow, index: number) => `${index}-${todo.status}-${todo.content.length}`)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  goalBlock() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text('目标').fontSize(AppFont.CAPTION).fontColor(AppColors.INK_WEAK)
        Text(this.phaseLabel(this.goal?.phase ?? 'active'))
          .fontSize(AppFont.CAPTION)
          .fontColor(AppColors.MIST)
        Text(this.goal !== null && this.goal.maxGoalRounds > 0
          ? `${this.goal.roundsStarted}/${this.goal.maxGoalRounds} 轮`
          : `${this.goal?.roundsStarted ?? 0} 轮`)
          .fontSize(AppFont.CAPTION)
          .fontColor(AppColors.INK_WEAK)
          .layoutWeight(1)
          .textAlign(TextAlign.End)
      }
      .width('100%')

      if (this.editing) {
        TextInput({ placeholder: '目标描述', text: this.draft })
          .width('100%')
          .height(40)
          .fontSize(AppFont.LABEL)
          .fontColor(AppColors.DARK_INK)
          .placeholderColor(AppColors.INK_WEAK)
          .backgroundColor(Glass.FILL_SUBTLE)
          .borderRadius(AppRadius.INPUT)
          .onChange((value: string) => {
            this.draft = value;
          })
      } else {
        Text(this.goal?.objective ?? '')
          .fontSize(AppFont.BODY)
          .fontColor(AppColors.DARK_INK)
          .width('100%')
      }

      Row({ space: 8 }) {
        if (this.editing) {
          Text('取消')
            .fontSize(AppFont.CAPTION)
            .fontColor(AppColors.INK_WEAK)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .height(34)
            .backgroundColor(Glass.FILL)
            .borderRadius(AppRadius.PILL)
            .onClick(() => {
              this.editing = false;
            })
          Text('保存')
            .fontSize(AppFont.CAPTION)
            .fontColor(AppColors.PAPER)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .height(34)
            .backgroundColor(AppColors.BRAND)
            .borderRadius(AppRadius.PILL)
            .onClick(() => {
              const objective = this.draft.replace(/^\s+|\s+$/g, '');
              if (objective.length === 0) {
                this.error = '目标描述不能为空';
                return;
              }
              this.run(async () => {
                await this.store.editGoal(objective);
              }).then(() => {
                this.editing = false;
              });
            })
        } else {
          Text('改名')
            .fontSize(AppFont.CAPTION)
            .fontColor(AppColors.DARK_INK)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .height(34)
            .backgroundColor(Glass.FILL)
            .borderRadius(AppRadius.PILL)
            .onClick(() => {
              this.draft = this.goal?.objective ?? '';
              this.editing = true;
            })
          Text(this.goal?.phase === 'paused' ? '继续' : '暂停')
            .fontSize(AppFont.CAPTION)
            .fontColor(AppColors.DARK_INK)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .height(34)
            .backgroundColor(Glass.FILL)
            .borderRadius(AppRadius.PILL)
            .onClick(() => {
              if (this.busy) {
                return;
              }
              this.run(async () => {
                await this.store.goalAction(this.goal?.phase === 'paused' ? 'goal-resume' : 'goal-pause');
              });
            })
          Text('清除')
            .fontSize(AppFont.CAPTION)
            .fontColor(AppColors.DANGER)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .height(34)
            .backgroundColor(Glass.FILL)
            .borderRadius(AppRadius.PILL)
            .onClick(() => {
              if (this.busy) {
                return;
              }
              this.run(async () => {
                await this.store.goalAction('goal-clear');
              });
            })
        }
      }
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  build() {
    Column({ space: AppSpacing.GAP }) {
      this.todoRows()
      if (this.goal !== null) {
        this.goalBlock()
      }
      if (this.error.length > 0) {
        Text(this.error).fontSize(AppFont.CAPTION).fontColor(AppColors.DANGER).width('100%')
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(14)
    .backgroundColor(Glass.FILL)
    .borderRadius(AppRadius.CARD)
    .border({ width: Glass.BORDER_WIDTH, color: Glass.BORDER })
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK, Glass.blurOptions())
  }
}
