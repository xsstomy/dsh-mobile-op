import { describe, expect, it } from '@ohos/hypium';
import {
  DraftAnswer, QuestionView, draftHasAnswer, emptyDraft, isBatchComplete, isOptionSelected, planReviewOf,
  toQuestionViews, toggleOption, validateAnswers, withCustom
} from '../main/ets/protocol/Questions';
import { WireQuestion } from '../main/ets/protocol/Types';

function option(label: string, description: string): WireQuestionOptionLike {
  return { label: label, description: description };
}

interface WireQuestionOptionLike {
  label: string;
  description: string;
}

/** `intent` payload of a plan review (docs/PROTOCOL.md §3.1). */
interface PlanIntent {
  kind: string;
  approve: string;
}

/** A single-question plan review: the plan is `detail`, options are approve/reject. */
function planQuestion(): WireQuestion {
  const options: WireQuestionOptionLike[] = [
    { label: '批准', description: '确认执行并退出计划模式' },
    { label: '继续规划', description: '带着反馈继续规划' }
  ];
  const intent: PlanIntent = { kind: 'plan-review', approve: '批准' };
  const wire: WireQuestion = {
    id: 'plan',
    header: 'Plan review',
    question: 'Approve this plan and leave plan mode?',
    detail: '## 计划\n\n1. 改 A\n2. 改 B'
  };
  wire.options = options;
  wire.intent = intent;
  return wire;
}

function question(id: string, multiSelect: boolean, labels: string[]): WireQuestion {
  const wire: WireQuestion = { id: id, header: `${id} 标题`, question: `${id} 问题`, multiSelect: multiSelect };
  const options: WireQuestionOptionLike[] = [];
  for (const label of labels) {
    options.push(option(label, `${label} 说明`));
  }
  wire.options = options;
  return wire;
}

export default function questionsTest(): void {
  describe('questions', () => {
    it('maps wire questions into view models', 0, () => {
      const views = toQuestionViews([question('q1', false, ['A', 'B'])]);
      expect(views.length).assertEqual(1);
      expect(views[0].id).assertEqual('q1');
      expect(views[0].multiSelect).assertFalse();
      expect(views[0].options.length).assertEqual(2);
      expect(views[0].options[1].description).assertEqual('B 说明');
    });

    it('toggles single-select options and clears the previous choice', 0, () => {
      const views = toQuestionViews([question('q1', false, ['A', 'B'])]);
      let draft = emptyDraft(views[0]);
      draft = toggleOption(draft, 'A', false);
      expect(isOptionSelected(draft, 'A')).assertTrue();
      draft = toggleOption(draft, 'B', false);
      expect(isOptionSelected(draft, 'A')).assertFalse();
      expect(isOptionSelected(draft, 'B')).assertTrue();
      draft = toggleOption(draft, 'B', false);
      expect(draft.selected.length).assertEqual(0);
      expect(draftHasAnswer(draft)).assertFalse();
    });

    it('accumulates multi-select options and drops duplicates', 0, () => {
      const views = toQuestionViews([question('q1', true, ['A', 'B', 'C'])]);
      let draft = emptyDraft(views[0]);
      draft = toggleOption(draft, 'A', true);
      draft = toggleOption(draft, 'C', true);
      expect(draft.selected.join('|')).assertEqual('A|C');
      draft = toggleOption(draft, 'A', true);
      expect(draft.selected.join('|')).assertEqual('C');
    });

    it('keeps custom text exclusive with a single choice', 0, () => {
      const views = toQuestionViews([question('q1', false, ['A'])]);
      let draft = emptyDraft(views[0]);
      draft = toggleOption(draft, 'A', false);
      draft = withCustom(draft, '自定义答案');
      expect(draft.selected.length).assertEqual(0);
      expect(draft.custom).assertEqual('自定义答案');
      draft = toggleOption(draft, 'A', false);
      expect(draft.custom).assertEqual('');
    });

    it('accepts a complete single-select batch', 0, () => {
      const views = toQuestionViews([question('q1', false, ['A', 'B']), question('q2', true, ['X', 'Y'])]);
      const answers: DraftAnswer[] = [
        { id: 'q1', selected: ['A'], custom: '' },
        { id: 'q2', selected: ['X', 'Y'], custom: '' }
      ];
      expect(validateAnswers(views, answers)).assertEqual('');
      expect(isBatchComplete(views, answers)).assertTrue();
    });

    it('requires every question in the batch to be answered', 0, () => {
      const views = toQuestionViews([question('q1', false, ['A']), question('q2', false, ['B'])]);
      const answers: DraftAnswer[] = [
        { id: 'q1', selected: ['A'], custom: '' },
        { id: 'q2', selected: [], custom: '' }
      ];
      expect(validateAnswers(views, answers)).assertEqual('请回答「q2 标题」');
    });

    it('rejects too many selections on a single-select question', 0, () => {
      const views = toQuestionViews([question('q1', false, ['A', 'B'])]);
      const answers: DraftAnswer[] = [{ id: 'q1', selected: ['A', 'B'], custom: '' }];
      expect(validateAnswers(views, answers)).assertEqual('单选题只能选择一个选项');
    });

    it('rejects unknown labels and repeated labels', 0, () => {
      const views = toQuestionViews([question('q1', true, ['A'])]);
      expect(validateAnswers(views, [{ id: 'q1', selected: ['Z'], custom: '' }]))
        .assertEqual('选项「Z」不属于该问题');
      expect(validateAnswers(views, [{ id: 'q1', selected: ['A', 'A'], custom: '' }]))
        .assertEqual('同一选项不能重复选择');
    });

    it('rejects a mismatched answer count or order', 0, () => {
      const views = toQuestionViews([question('q1', false, ['A']), question('q2', false, ['B'])]);
      expect(validateAnswers(views, [{ id: 'q1', selected: ['A'], custom: '' }])).assertEqual('请回答全部问题');
      expect(validateAnswers(views, [
        { id: 'q2', selected: ['B'], custom: '' },
        { id: 'q1', selected: ['A'], custom: '' }
      ])).assertEqual('答案与问题顺序不一致');
    });

    it('accepts free text alone and rejects blank custom text', 0, () => {
      const views = toQuestionViews([question('q1', false, ['A'])]);
      expect(validateAnswers(views, [{ id: 'q1', selected: [], custom: '自己写' }])).assertEqual('');
      expect(validateAnswers(views, [{ id: 'q1', selected: [], custom: '   ' }]))
        .assertEqual('请回答「q1 标题」');
    });

    // ------------------------------------------- plan review (plan mode)

    it('decodes the plan-review intent off the wire question', 0, () => {
      const views = toQuestionViews([planQuestion()]);
      expect(views[0].intentKind).assertEqual('plan-review');
      expect(views[0].intentApprove).assertEqual('批准');
    });

    it('detects the plan review card and derives approve/reject labels', 0, () => {
      const plan = planReviewOf(toQuestionViews([planQuestion()]));
      expect(plan === null).assertFalse();
      if (plan !== null) {
        expect(plan.approveLabel).assertEqual('批准');
        expect(plan.rejectLabel).assertEqual('继续规划');
      }
    });

    it('keeps a plan review with only an approve option', 0, () => {
      const wire = planQuestion();
      const single: WireQuestionOptionLike[] = [{ label: '批准', description: '' }];
      wire.options = single;
      const plan = planReviewOf(toQuestionViews([wire]));
      expect(plan === null).assertFalse();
      if (plan !== null) {
        expect(plan.approveLabel).assertEqual('批准');
        expect(plan.rejectLabel).assertEqual('');
      }
    });

    it('falls back to the generic card for malformed plan reviews', 0, () => {
      expect(planReviewOf(toQuestionViews([question('q1', false, ['A']) ])) === null).assertTrue();
      const noDetail = planQuestion();
      noDetail.detail = '';
      expect(planReviewOf(toQuestionViews([noDetail])) === null).assertTrue();
      const badApprove = planQuestion();
      const wrong: PlanIntent = { kind: 'plan-review', approve: '不存在' };
      badApprove.intent = wrong;
      expect(planReviewOf(toQuestionViews([badApprove])) === null).assertTrue();
      const three = planQuestion();
      const options: WireQuestionOptionLike[] = [
        { label: '批准', description: '' }, { label: '继续规划', description: '' }, { label: '取消', description: '' }
      ];
      three.options = options;
      expect(planReviewOf(toQuestionViews([three])) === null).assertTrue();
      const multi = planQuestion();
      multi.multiSelect = true;
      expect(planReviewOf(toQuestionViews([multi])) === null).assertTrue();
      expect(planReviewOf(toQuestionViews([planQuestion(), planQuestion()])) === null).assertTrue();
    });
  });
}
