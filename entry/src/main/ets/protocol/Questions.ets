/**
 * Human-in-the-loop question answering (pure logic, unit tested).
 *
 * The gateway validates answers strictly before the Host waterfall sees them
 * (docs/PROTOCOL.md §3.1): all questions in the batch must be answered, selected
 * labels must match `options[].label` exactly, single-select answers may carry at
 * most one selection, and `custom` is mutually exclusive with `selected`.
 */
import { WireQuestion } from './Types';

export interface QuestionOptionView {
  label: string;
  description: string;
}

export interface QuestionView {
  id: string;
  header: string;
  question: string;
  detail: string;
  options: QuestionOptionView[];
  multiSelect: boolean;
  /** `intent.kind`: currently `plan-review` for the reviewed exit of plan mode. */
  intentKind: string;
  /** `intent.approve`: the option label that approves the reviewed plan. */
  intentApprove: string;
}

/** The reviewed exit of plan mode (`intent.kind === 'plan-review'`). */
export interface PlanReviewView {
  /** Option label that approves the plan; submit it to leave plan mode. */
  approveLabel: string;
  /** The other option, if the host sent one; `''` when there is none. */
  rejectLabel: string;
}

function intentString(intent: Object | undefined, key: string): string {
  if (intent === undefined || intent === null || typeof intent !== 'object') {
    return '';
  }
  const value = (intent as Record<string, Object>)[key];
  return typeof value === 'string' ? value : '';
}

/**
 * Detect the plan review card. Mirrors upstream `HumanQuestionView.planReview`:
 * one single-select question carrying `intent.kind = plan-review`, the plan as
 * `detail`, and at most two options one of which is `intent.approve`.
 */
export function planReviewOf(questions: QuestionView[]): PlanReviewView | null {
  if (questions.length !== 1) {
    return null;
  }
  const question = questions[0];
  if (question.intentKind !== 'plan-review' || question.multiSelect ||
    question.detail.length === 0 || question.intentApprove.length === 0 ||
    question.options.length > 2) {
    return null;
  }
  let approve = '';
  let reject = '';
  for (const option of question.options) {
    if (option.label === question.intentApprove) {
      approve = option.label;
    } else if (reject.length === 0) {
      reject = option.label;
    }
  }
  if (approve.length === 0) {
    return null;
  }
  return { approveLabel: approve, rejectLabel: reject };
}

export interface DraftAnswer {
  id: string;
  selected: string[];
  custom: string;
}

export function toQuestionViews(questions: WireQuestion[]): QuestionView[] {
  const views: QuestionView[] = [];
  for (const question of questions) {
    const options: QuestionOptionView[] = [];
    const rawOptions = question.options;
    if (Array.isArray(rawOptions)) {
      for (const option of rawOptions) {
        options.push({
          label: option.label ?? '',
          description: option.description ?? ''
        });
      }
    }
    views.push({
      id: question.id ?? '',
      header: question.header ?? '',
      question: question.question ?? '',
      detail: question.detail ?? '',
      options: options,
      multiSelect: question.multiSelect === true,
      intentKind: intentString(question.intent, 'kind'),
      intentApprove: intentString(question.intent, 'approve')
    });
  }
  return views;
}

export function emptyDraft(question: QuestionView): DraftAnswer {
  return { id: question.id, selected: [], custom: '' };
}

/** True when the draft carries an answer (selection or free text). */
export function draftHasAnswer(draft: DraftAnswer): boolean {
  return draft.selected.length > 0 || draft.custom.replace(/^\s+|\s+$/g, '').length > 0;
}

export function isOptionSelected(draft: DraftAnswer, label: string): boolean {
  return draft.selected.indexOf(label) >= 0;
}

/** Toggle one option, honouring single-select semantics and custom exclusivity. */
export function toggleOption(draft: DraftAnswer, label: string, multiSelect: boolean): DraftAnswer {
  if (multiSelect) {
    const selected: string[] = [];
    let removed = false;
    for (const value of draft.selected) {
      if (value === label) {
        removed = true;
      } else {
        selected.push(value);
      }
    }
    if (!removed) {
      selected.push(label);
    }
    return { id: draft.id, selected: selected, custom: draft.custom };
  }
  const already = isOptionSelected(draft, label);
  return {
    id: draft.id,
    selected: already ? [] : [label],
    custom: already ? draft.custom : ''
  };
}

export function withCustom(draft: DraftAnswer, text: string): DraftAnswer {
  const trimmed = text.replace(/^\s+|\s+$/g, '');
  return {
    id: draft.id,
    // Free text is mutually exclusive with a single choice.
    selected: draft.selected.length > 0 ? [] : draft.selected,
    custom: trimmed.length > 0 ? text : ''
  };
}

/** Returns '' when the whole batch is answerable, otherwise a user-facing reason. */
export function validateAnswers(questions: QuestionView[], answers: DraftAnswer[]): string {
  if (questions.length === 0) {
    return '没有问题需要回答';
  }
  if (answers.length !== questions.length) {
    return '请回答全部问题';
  }
  for (let index = 0; index < questions.length; index += 1) {
    const question = questions[index];
    const answer = answers[index];
    if (answer.id !== question.id) {
      return '答案与问题顺序不一致';
    }
    const unique: string[] = [];
    for (const label of answer.selected) {
      if (unique.indexOf(label) >= 0) {
        return '同一选项不能重复选择';
      }
      unique.push(label);
      let known = false;
      for (const option of question.options) {
        if (option.label === label) {
          known = true;
        }
      }
      if (!known) {
        return `选项「${label}」不属于该问题`;
      }
    }
    if (!question.multiSelect && answer.selected.length > 1) {
      return '单选题只能选择一个选项';
    }
    const custom = answer.custom.replace(/^\s+|\s+$/g, '');
    if (custom.length > 0 && !question.multiSelect && answer.selected.length > 0) {
      return '单选题的自定义答案与选项互斥';
    }
    if (!draftHasAnswer(answer)) {
      const label = question.header.length > 0 ? question.header : question.question;
      return `请回答「${label}」`;
    }
  }
  return '';
}

/** Whether every question already has an answer (for enabling the submit button). */
export function isBatchComplete(questions: QuestionView[], answers: DraftAnswer[]): boolean {
  return validateAnswers(questions, answers).length === 0;
}
