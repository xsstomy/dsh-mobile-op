/**
 * Human-in-the-loop question card (upstream: HumanQuestionCard.kt).
 * One card renders a whole question batch; answering submits every question at
 * once, exactly as the gateway validates it.
 */
import { AppColors, AppFont, AppRadius, AppSpacing, AppShadow, Glass } from '../common/Constants';
import { GatewayStore } from '../store/GatewayStore';
import { QuestionCardRow, emptyQuestionCard } from '../store/UiState';
import {
  DraftAnswer, QuestionOptionView, QuestionView, emptyDraft, isOptionSelected, planReviewOf, toggleOption,
  validateAnswers, withCustom
} from '../protocol/Questions';
import { messageContentView } from './MessageContent';

/** Plan preview window: taller plans scroll inside the card (upstream maxHeight 390). */
const PLAN_PREVIEW_MAX_HEIGHT: number = 420;

@Component
export struct HumanQuestionCard {
  @Prop @Watch('onCardChanged') card: QuestionCardRow = emptyQuestionCard();
  @State drafts: DraftAnswer[] = [];
  @State submitting: boolean = false;
  @State error: string = '';
  /** Plan review (intent.kind = plan-review): badge + plan markdown + approve/reject. */
  @State isPlanReview: boolean = false;
  @State planApprove: string = '';
  @State planReject: string = '';
  private store: GatewayStore = GatewayStore.current;

  aboutToAppear(): void {
    this.resetDrafts();
  }

  onCardChanged(): void {
    this.resetDrafts();
  }

  private resetDrafts(): void {
    const drafts: DraftAnswer[] = [];
    for (const question of this.card.questions) {
      drafts.push(emptyDraft(question));
    }
    this.drafts = drafts;
    this.error = '';
    const plan = planReviewOf(this.card.questions);
    if (plan === null) {
      this.isPlanReview = false;
      this.planApprove = '';
      this.planReject = '';
    } else {
      this.isPlanReview = true;
      this.planApprove = plan.approveLabel;
      this.planReject = plan.rejectLabel;
    }
  }

  /** Answer the single plan-review question with `label` (approve or reject). */
  private async choose(label: string): Promise<void> {
    if (this.submitting || label.length === 0 || this.card.questions.length !== 1) {
      return;
    }
    const selected: string[] = [label];
    const drafts: DraftAnswer[] = [{ id: this.card.questions[0].id, selected: selected, custom: '' }];
    this.submitting = true;
    this.error = '';
    try {
      await this.store.answerQuestion(this.card.rpcId, drafts);
    } catch (failure) {
      this.error = (failure as Error).message;
    }
    this.submitting = false;
  }

  private updateDraft(index: number, draft: DraftAnswer): void {
    const next: DraftAnswer[] = [];
    for (let i = 0; i < this.drafts.length; i += 1) {
      next.push(i === index ? draft : this.drafts[i]);
    }
    this.drafts = next;
    this.error = '';
  }

  private async submit(): Promise<void> {
    const reason = validateAnswers(this.card.questions, this.drafts);
    if (reason.length > 0) {
      this.error = reason;
      return;
    }
    this.submitting = true;
    this.error = '';
    try {
      await this.store.answerQuestion(this.card.rpcId, this.drafts);
    } catch (failure) {
      this.error = (failure as Error).message;
    }
    this.submitting = false;
  }

  private async skip(): Promise<void> {
    this.submitting = true;
    this.error = '';
    try {
      await this.store.cancelQuestion(this.card.rpcId);
    } catch (failure) {
      this.error = (failure as Error).message;
    }
    this.submitting = false;
  }

  @Builder
  optionRow(questionIndex: number, question: QuestionView, optionLabel: string, optionDescription: string) {
    Row({ space: 10 }) {
      Text(question.multiSelect
        ? (isOptionSelected(this.drafts[questionIndex], optionLabel) ? '☑' : '☐')
        : (isOptionSelected(this.drafts[questionIndex], optionLabel) ? '◉' : '○'))
        .fontSize(15)
        .fontColor(AppColors.MIST)
      Column({ space: 2 }) {
        Text(optionLabel).fontSize(AppFont.LABEL).fontColor(AppColors.DARK_INK).width('100%')
        if (optionDescription.length > 0) {
          Text(optionDescription).fontSize(AppFont.CAPTION).fontColor(AppColors.INK_WEAK).width('100%')
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ top: 8, bottom: 8, left: 8, right: 8 })
    .borderRadius(AppRadius.CARD_SMALL)
    .backgroundColor(isOptionSelected(this.drafts[questionIndex], optionLabel) ? Glass.FILL_STRONG : '#00000000')
    .onClick(() => {
      this.updateDraft(questionIndex, toggleOption(this.drafts[questionIndex], optionLabel, question.multiSelect));
    })
  }

  @Builder
  questionBlock(index: number, question: QuestionView) {
    Column({ space: 4 }) {
      if (question.header.length > 0) {
        Text(question.header).fontSize(AppFont.CAPTION).fontColor(AppColors.MIST).width('100%')
      }
      Text(question.question).fontSize(AppFont.SUBTITLE).fontWeight(FontWeight.Medium)
        .fontColor(AppColors.DARK_INK).width('100%')
      if (question.detail.length > 0) {
        Text(question.detail).fontSize(AppFont.CAPTION).fontColor(AppColors.INK_WEAK).width('100%')
      }
      ForEach(question.options, (option: QuestionOptionView) => {
        this.optionRow(index, question, option.label, option.description)
      }, (option: QuestionOptionView) => `${question.id}-${option.label}`)
      TextInput({ placeholder: '也可以直接输入你的答案', text: this.drafts[index].custom })
        .width('100%')
        .height(40)
        .fontSize(AppFont.LABEL)
        .fontColor(AppColors.DARK_INK)
        .placeholderColor(AppColors.INK_WEAK)
        .backgroundColor(Glass.FILL_SUBTLE)
        .borderRadius(AppRadius.INPUT)
        .onChange((value: string) => {
          this.updateDraft(index, withCustom(this.drafts[index], value));
        })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ top: 6, bottom: 6 })
  }

  /** Plan-mode reviewed exit: badge, plan markdown (bounded scroll) and actions. */
  @Builder
  planReviewBody() {
    Column({ space: 8 }) {
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.doc_text_magnifyingglass_fill'))
          .fontSize(14)
          .fontColor([AppColors.AMBER])
        Text('计划待审')
          .fontSize(AppFont.CAPTION)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.AMBER)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(this.card.questions[0].question)
        .fontSize(AppFont.SUBTITLE)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppColors.DARK_INK)
        .width('100%')

      Scroll() {
        Column() {
          messageContentView(this.card.questions[0].detail, false)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .constraintSize({ maxHeight: PLAN_PREVIEW_MAX_HEIGHT })
      .scrollBar(BarState.Auto)
      .nestedScroll({ scrollForward: NestedScrollMode.SELF_FIRST, scrollBackward: NestedScrollMode.SELF_FIRST })
      .backgroundColor(Glass.FILL_SUBTLE)
      .borderRadius(AppRadius.CARD_SMALL)
      .padding(8)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  planReviewFooter() {
    Row({ space: 10 }) {
      Text('去聊天里说')
        .fontSize(AppFont.LABEL)
        .fontColor(AppColors.DARK_INK)
        .textAlign(TextAlign.Center)
        .height(40)
        .padding({ left: 12, right: 12 })
        .backgroundColor(Glass.FILL)
        .borderRadius(AppRadius.PILL)
        .border({ width: Glass.BORDER_WIDTH, color: Glass.BORDER_SOFT })
        .onClick(() => {
          if (!this.submitting) {
            this.skip();
          }
        })
      Column()
        .layoutWeight(1)
      if (this.planReject.length > 0) {
        Text('拒绝')
          .fontSize(AppFont.LABEL)
          .fontColor(AppColors.DANGER)
          .textAlign(TextAlign.Center)
          .height(40)
          .padding({ left: 14, right: 14 })
          .backgroundColor(Glass.FILL)
          .borderRadius(AppRadius.PILL)
          .border({ width: Glass.BORDER_WIDTH, color: Glass.BORDER_SOFT })
          .onClick(() => {
            this.choose(this.planReject);
          })
      }
      Text(this.submitting ? '提交中…' : '确认执行')
        .fontSize(AppFont.LABEL)
        .fontColor(this.submitting ? AppColors.INK_WEAK : AppColors.PAPER)
        .textAlign(TextAlign.Center)
        .height(40)
        .padding({ left: 14, right: 14 })
        .backgroundColor(this.submitting ? Glass.FILL_SUBTLE : AppColors.BRAND)
        .borderRadius(AppRadius.PILL)
        .onClick(() => {
          this.choose(this.planApprove);
        })
    }
    .width('100%')
  }

  build() {
    Column({ space: AppSpacing.GAP }) {
      Row({ space: 8 }) {
        Text('等待回答').fontSize(AppFont.CAPTION).fontColor(AppColors.AMBER)
        Text(this.card.replay ? '（重放）' : '')
          .fontSize(AppFont.CAPTION)
          .fontColor(AppColors.INK_WEAK)
        Text(`${this.card.questions.length} 题`).fontSize(AppFont.CAPTION).fontColor(AppColors.INK_WEAK)
          .layoutWeight(1).textAlign(TextAlign.End)
      }
      .width('100%')

      if (this.isPlanReview) {
        this.planReviewBody()
      } else {
        ForEach(this.card.questions, (question: QuestionView, index: number) => {
          this.questionBlock(index, question)
        }, (question: QuestionView) => `${this.card.rpcId}-${question.id}`)
      }

      if (this.error.length > 0) {
        Text(this.error).fontSize(AppFont.CAPTION).fontColor(AppColors.DANGER).width('100%')
      }

      if (this.isPlanReview) {
        this.planReviewFooter()
      } else {
        Row({ space: 10 }) {
        Text('跳过')
          .fontSize(AppFont.LABEL)
          .fontColor(AppColors.DARK_INK)
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
          .height(40)
          .backgroundColor(Glass.FILL)
          .borderRadius(AppRadius.PILL)
          .border({ width: Glass.BORDER_WIDTH, color: Glass.BORDER_SOFT })
          .onClick(() => {
            if (!this.submitting) {
              this.skip();
            }
          })
        Text(this.submitting ? '提交中…' : '提交')
          .fontSize(AppFont.LABEL)
          .fontColor(this.submitting ? AppColors.INK_WEAK : AppColors.PAPER)
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
          .height(40)
          .backgroundColor(this.submitting ? Glass.FILL_SUBTLE : AppColors.BRAND)
          .borderRadius(AppRadius.PILL)
          .onClick(() => {
            if (!this.submitting) {
              this.submit();
            }
          })
        }
        .width('100%')
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(14)
    .backgroundColor(Glass.FILL_STRONG)
    .borderRadius(AppRadius.CARD)
    .border({ width: Glass.BORDER_WIDTH, color: '#66FFAD1F' })
    .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK, Glass.blurOptions())
    .shadow(AppShadow.CARD)
  }
}
