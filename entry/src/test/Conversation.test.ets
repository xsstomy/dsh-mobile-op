import { describe, expect, it } from '@ohos/hypium';
import { ConversationItem, ConversationRole, applyEvent, conversationListItemCount, isTurnTail, projectFromEvents, shouldShowThinking, toolSummaryText, turnTimeSpan, turnTokenTotals, usageTotalsOf } from '../main/ets/projection/Conversation';
import { durationLabel } from '../main/ets/common/Format';
import { HISTORY_RAW_TOOL_CALL, HISTORY_RAW_TOOL_RESULT, HISTORY_FRAME, EVENT_ASSISTANT_MESSAGE, EVENT_CHUNK_REASONING, EVENT_CHUNK_TEXT, EVENT_CHUNK_TEXT_STEP2, EVENT_CHUNK_USAGE, EVENT_CHUNK_USAGE_STEP2, EVENT_TOOL_CALL, EVENT_TOOL_RESULT, EVENT_TURN_END, EVENT_USER_MESSAGE, HISTORY_RAW_USER_MESSAGE, HISTORY_RAW_ASSISTANT_MESSAGE, HISTORY_RAW_TURN_END, TURN_START_EARLIER, TURN_START_LATER } from './fixtures/Frames';
import { asSessionEvents, decodeFrame } from '../main/ets/protocol/WireDecoder';
import { WireSessionEvent } from '../main/ets/protocol/Types';
import { eventAtSeq, rawEvent, userEvent, userEventAt, assistantEventAt, turnEndEventAt, toolResultAt } from './TestHelpers';
import { TOOL_TURN_EVENTS } from './fixtures/ToolTurn';

function eventOf(raw: string): WireSessionEvent {
  const frame = decodeFrame(raw);
  return { type: frame?.event?.type, seq: frame?.seq, time: frame?.time, data: frame?.event };
}

export default function conversationTest(): void {
  describe('conversation', () => {
    it('appends a user message', 0, () => {
      const items = applyEvent([], 1, eventOf(EVENT_USER_MESSAGE));
      expect(items.length).assertEqual(1);
      expect(items[0].role).assertEqual(ConversationRole.USER);
      expect(items[0].text.length > 0).assertTrue();
    });

    it('ignores non-user message sources', 0, () => {
      const items = applyEvent([], 2, userEvent(2, 'system', 'plugin'));
      expect(items.length).assertEqual(0);
    });

    it('accumulates streaming chunks into one assistant bubble', 0, () => {
      let items = applyEvent([], 7, eventOf(EVENT_CHUNK_TEXT));
      items = applyEvent(items, 8, eventOf(EVENT_CHUNK_REASONING));
      items = applyEvent(items, 7, eventOf(EVENT_CHUNK_TEXT));
      expect(items.length).assertEqual(1);
      expect(items[0].role).assertEqual(ConversationRole.ASSISTANT);
      expect(items[0].text).assertEqual('okok');
      expect(items[0].reasoning).assertEqual('thinking');
      expect(items[0].streaming).assertTrue();
    });

    it('finalises the bubble on assistant/message', 0, () => {
      let items = applyEvent([], 7, eventOf(EVENT_CHUNK_TEXT));
      items = applyEvent(items, 11, eventOf(EVENT_ASSISTANT_MESSAGE));
      expect(items.length).assertEqual(1);
      expect(items[0].streaming).assertFalse();
    });

    it('attaches tool results to the matching tool call', 0, () => {
      let items = applyEvent([], 9, eventOf(EVENT_TOOL_CALL));
      items = applyEvent(items, 10, eventOf(EVENT_TOOL_RESULT));
      expect(items.length).assertEqual(1);
      expect(items[0].toolCalls.length).assertEqual(1);
      expect(items[0].toolCalls[0].name).assertEqual('bash');
      expect(items[0].toolCalls[0].done).assertTrue();
      expect(items[0].toolCalls[0].isError).assertFalse();
    });

    it('clears the streaming flag on turn/end', 0, () => {
      let items = applyEvent([], 7, eventOf(EVENT_CHUNK_TEXT));
      items = applyEvent(items, 12, eventOf(EVENT_TURN_END));
      expect(items[0].streaming).assertFalse();
    });

    it('renders the raw (unprojected) history text shape', 0, () => {
      const items = projectFromEvents([
        rawEvent(HISTORY_RAW_USER_MESSAGE),
        rawEvent(HISTORY_RAW_ASSISTANT_MESSAGE)
      ]);
      expect(items.length).assertEqual(2);
      expect(items[0].role).assertEqual(ConversationRole.USER);
      expect(items[0].text.length > 0).assertTrue();
      expect(items[1].role).assertEqual(ConversationRole.ASSISTANT);
      expect(items[1].text).assertEqual('ok');
    });

    it('matches a raw tool result to its call and clears the running state', 0, () => {
      const items = projectFromEvents([
        rawEvent(HISTORY_RAW_TOOL_CALL),
        rawEvent(HISTORY_RAW_TOOL_RESULT)
      ]);
      expect(items.length).assertEqual(1);
      expect(items[0].toolCalls.length).assertEqual(1);
      const call = items[0].toolCalls[0];
      expect(call.name).assertEqual('run_code');
      expect(call.done).assertTrue();
      expect(call.isError).assertFalse();
      expect(call.result.length > 0).assertTrue();
      expect(call.arguments.length > 0).assertTrue();
    });

    it('keeps one bubble per step so a tool-call step and the answer step do not share a card', 0, () => {
      // Shape captured from a real host (view=conversation): the step that issues a
      // tool call has its own assistant/message carrying the call, and the answer
      // arrives as the next step's assistant/message. Keying bubbles by seq used to
      // split the tool step in two (duplicated tool card) and glue the answer to it.
      const raws: string[] = [
        '{"type":"user/message","seq":61,"data":{"turn":5,"text":"跑一下","source":{"kind":"user"}}}',
        '{"type":"assistant/message","seq":62,"data":{"turn":5,"step":1,"toolCalls":[{"callId":"c1","name":"run_code","arguments":{}}]}}',
        '{"type":"tool/call","seq":63,"data":{"turn":5,"step":1,"callId":"c1","name":"run_code","arguments":{}}}',
        '{"type":"tool/result","seq":66,"data":{"turn":5,"step":1,"callId":"c1","text":"ok","isError":false}}',
        '{"type":"step/end","seq":67,"data":{"turn":5,"step":1}}',
        '{"type":"step/start","seq":68,"data":{"turn":5,"step":2}}',
        '{"type":"assistant/message","seq":69,"data":{"turn":5,"step":2,"text":"DONE"}}',
        '{"type":"step/end","seq":70,"data":{"turn":5,"step":2}}',
        '{"type":"turn/end","seq":71,"data":{"turn":5,"reason":{"kind":"completed"}}}'
      ];
      const events: WireSessionEvent[] = [];
      for (const raw of raws) {
        events.push(rawEvent(raw));
      }
      const items = projectFromEvents(events);
      expect(items.length).assertEqual(3);
      expect(items[0].role).assertEqual(ConversationRole.USER);
      // Step 1: the tool card, with the result attached and no answer text.
      expect(items[1].role).assertEqual(ConversationRole.ASSISTANT);
      expect(items[1].toolCalls.length).assertEqual(1);
      expect(items[1].toolCalls[0].done).assertTrue();
      expect(items[1].text).assertEqual('');
      // Step 2: the answer in its own bubble, without a duplicate tool card.
      expect(items[2].role).assertEqual(ConversationRole.ASSISTANT);
      expect(items[2].text).assertEqual('DONE');
      expect(items[2].toolCalls.length).assertEqual(0);
      expect(items[1].key === items[2].key).assertFalse();
    });

    it('accepts the raw turn/end reason object', 0, () => {
      const event = rawEvent(HISTORY_RAW_TURN_END); // turn 7, reason:{kind}
      let items = applyEvent([], 7, eventOf(EVENT_CHUNK_TEXT));
      items = applyEvent(items, 8, event);
      expect(items.length).assertEqual(1);
      // The payload is parsed (no crash) and the later turn/end clears the
      // streaming flag, but turn 7 must not stamp turn 1's end time.
      expect(items[0].streaming).assertFalse();
      expect(items[0].turnEndedAt).assertEqual(0);
      const owned = applyEvent(items, 18, eventOf(EVENT_TURN_END));
      expect(owned[0].turnEndedAt).assertEqual(1789043241076);
    });

    it('closes earlier turns without stealing their end time', 0, () => {
      let items = applyEvent([], 8, userEventAt(8, 'run ls', 1789099041731));
      items = applyEvent(items, 17, assistantEventAt(17, 1, 1, 1789099044641, 10, 1));
      items = applyEvent(items, 26, turnEndEventAt(26, 1, 1789099046691));
      items = applyEvent(items, 30, assistantEventAt(30, 2, 1, 1789099046700, 20, 2));
      items = applyEvent(items, 33, turnEndEventAt(33, 2, 1789099066691));
      expect(items[1].turnEndedAt).assertEqual(1789099046691);
      expect(items[1].streaming).assertFalse();
      expect(items[2].turnEndedAt).assertEqual(1789099066691);
      // A turn/end for an OLDER turn must not resurrect a newer bubble's state.
      const late = applyEvent(items, 26, turnEndEventAt(26, 1, 1789099046691));
      expect(late[2].turnEndedAt).assertEqual(1789099066691);
    });

    it('decodes the captured history page', 0, () => {
      const frame = decodeFrame(HISTORY_FRAME);
      const events = asSessionEvents(frame!);
      expect(events.length > 0).assertTrue();
      expect(typeof events[0].seq).assertEqual('number');
    });

    it('rebuilds a replayed history batch into an ordered timeline', 0, () => {
      const events: WireSessionEvent[] = [
        eventAtSeq(EVENT_USER_MESSAGE, 1),
        eventAtSeq(EVENT_CHUNK_TEXT, 2),
        eventAtSeq(EVENT_CHUNK_REASONING, 3),
        eventAtSeq(EVENT_TOOL_CALL, 4),
        eventAtSeq(EVENT_TOOL_RESULT, 5),
        eventAtSeq(EVENT_ASSISTANT_MESSAGE, 6),
        eventAtSeq(EVENT_TURN_END, 7)
      ];
      const items = projectFromEvents(events);
      expect(items.length).assertEqual(2);
      expect(items[0].role).assertEqual(ConversationRole.USER);
      expect(items[1].role).assertEqual(ConversationRole.ASSISTANT);
      expect(items[1].toolCalls.length).assertEqual(1);
      expect(items[1].toolCalls[0].done).assertTrue();
      expect(items[1].streaming).assertFalse();
    });

    // ------------------------------------------------ turn timing (footer)

    it('stamps the turn start on the first visible event', 0, () => {
      const items = applyEvent([], 40, eventOf(EVENT_CHUNK_TEXT));
      expect(items[0].turn).assertEqual(1);
      expect(items[0].step).assertEqual(1);
      expect(items[0].turnStartedAt).assertEqual(1789043235066);
      expect(items[0].turnEndedAt).assertEqual(0);
    });

    it('closes the turn timing on turn/end', 0, () => {
      let items = applyEvent([], 40, eventOf(EVENT_CHUNK_TEXT));
      items = applyEvent(items, 18, eventOf(EVENT_TURN_END));
      expect(items[0].turnEndedAt).assertEqual(1789043241076);
      expect(items[0].streaming).assertFalse();
    });

    it('refines the turn start from turn/start without inventing bubbles', 0, () => {
      let items = applyEvent([], 40, eventOf(EVENT_CHUNK_TEXT));
      items = applyEvent(items, 39, rawEvent(TURN_START_EARLIER));
      expect(items.length).assertEqual(1);
      expect(items[0].turnStartedAt).assertEqual(1789043235000);
      // A replayed/late turn/start must not move the start forward.
      items = applyEvent(items, 39, rawEvent(TURN_START_LATER));
      expect(items[0].turnStartedAt).assertEqual(1789043235000);
      // No bubble of that turn yet: turn/start alone creates nothing.
      expect(applyEvent([], 39, rawEvent(TURN_START_EARLIER)).length).assertEqual(0);
    });

    it('measures the turn from its prompt, not from the tail bubble', 0, () => {
      // Measured 2026-09-11 (dsh web 3081, two-step turn): turn/start
      // 1789099041701, user/message 1789099041731, step-1 assistant/message
      // 1789099044641, step-2 assistant/message 1789099046690, turn/end
      // 1789099046691. The footer sits on the step-2 bubble, whose own
      // turnStartedAt is 1789099046690 -> 0.0s; only the turn span is truthful.
      let items = applyEvent([], 8, userEventAt(8, 'run ls', 1789099041731));
      items = applyEvent(items, 17, assistantEventAt(17, 1, 1, 1789099044641, 13525, 159));
      items = applyEvent(items, 24, assistantEventAt(24, 1, 2, 1789099046690, 293, 133));
      items = applyEvent(items, 26, turnEndEventAt(26, 1, 1789099046691));
      const span = turnTimeSpan(items, 1);
      expect(span.startedAt).assertEqual(1789099041731);
      expect(span.endedAt).assertEqual(1789099046691);
      expect(durationLabel(span.endedAt - span.startedAt)).assertEqual('5.0s');
      expect(items[2].turnStartedAt).assertEqual(1789099046690);
      expect(turnTokenTotals(items, 1).output).assertEqual(292);
      // Unknown / non-positive turns have no span at all.
      expect(turnTimeSpan(items, 0).startedAt).assertEqual(0);
      expect(turnTimeSpan(items, 9).startedAt).assertEqual(0);
    });

    it('falls back to the assistant events when the prompt is not loaded', 0, () => {
      let items = applyEvent([], 17, assistantEventAt(17, 1, 1, 1789099044641, 10, 1));
      items = applyEvent(items, 26, turnEndEventAt(26, 1, 1789099046691));
      expect(turnTimeSpan(items, 1).startedAt).assertEqual(1789099044641);
    });

    it('measures a replayed tool call against event time, not the clock', 0, () => {
      let items = applyEvent([], 42, eventOf(EVENT_TOOL_CALL));
      items = applyEvent(items, 43, eventOf(EVENT_TOOL_RESULT));
      expect(items[0].toolCalls[0].endedAt).assertEqual(1789043235069);
      expect(toolSummaryText(items[0])).assertEqual('1 个工具 · 0.0s');
    });

    // ------------------------------------------------------ token totals

    it('accumulates usage into the step that reported it', 0, () => {
      let items = applyEvent([], 40, eventOf(EVENT_CHUNK_TEXT));
      items = applyEvent(items, 44, eventOf(EVENT_CHUNK_USAGE));
      expect(items.length).assertEqual(1);
      expect(items[0].stepInputTokens).assertEqual(125);
      expect(items[0].stepOutputTokens).assertEqual(7);
    });

    it('reads the history usage shape and the wrapped totals shape', 0, () => {
      const items = projectFromEvents([rawEvent(HISTORY_RAW_ASSISTANT_MESSAGE)]);
      expect(items.length).assertEqual(1);
      expect(items[0].stepInputTokens).assertEqual(1);
      expect(items[0].stepOutputTokens).assertEqual(2);
      const wrapped = usageTotalsOf(new WrappedUsage(9, 4));
      expect(wrapped.input).assertEqual(9);
      expect(wrapped.output).assertEqual(4);
      const missing = usageTotalsOf(undefined);
      expect(missing.input).assertEqual(0);
      expect(missing.output).assertEqual(0);
    });

    it('attaches a usage frame to the last bubble when its step has none', 0, () => {
      // A usage frame with no matching bubble must not create an empty one.
      const lonely = applyEvent([], 44, eventOf(EVENT_CHUNK_USAGE));
      expect(lonely.length).assertEqual(0);
    });

    it('sums a turn across its steps', 0, () => {
      let items = applyEvent([], 40, eventOf(EVENT_CHUNK_TEXT));
      items = applyEvent(items, 44, eventOf(EVENT_CHUNK_USAGE));
      items = applyEvent(items, 45, eventOf(EVENT_CHUNK_TEXT_STEP2));
      items = applyEvent(items, 46, eventOf(EVENT_CHUNK_USAGE_STEP2));
      items = applyEvent(items, 20, rawEvent(HISTORY_RAW_ASSISTANT_MESSAGE));
      const turn1 = turnTokenTotals(items, 1);
      expect(turn1.input).assertEqual(250);
      expect(turn1.output).assertEqual(14);
      const turn7 = turnTokenTotals(items, 7);
      expect(turn7.input).assertEqual(1);
      expect(turn7.output).assertEqual(2);
      expect(turnTokenTotals(items, 0).input).assertEqual(0);
    });

    it('spreads a turn across steps but keeps the footer on its last bubble', 0, () => {
      let items = applyEvent([], 1, eventAtSeq(EVENT_CHUNK_TEXT, 1));
      items = applyEvent(items, 2, eventAtSeq(EVENT_CHUNK_TEXT_STEP2, 2));
      items = applyEvent(items, 3, eventAtSeq(EVENT_CHUNK_USAGE_STEP2, 3));
      items = applyEvent(items, 4, rawEvent(HISTORY_RAW_ASSISTANT_MESSAGE));
      items = applyEvent(items, 5, eventAtSeq(EVENT_TURN_END, 5));
      expect(items.length).assertEqual(3);
      expect(isTurnTail(items, 0)).assertFalse();
      expect(isTurnTail(items, 1)).assertTrue();
      expect(isTurnTail(items, 2)).assertTrue();
      expect(isTurnTail(items, 99)).assertFalse();
    });

    it('closes a captured tool turn rebuilt from history', 0, () => {
      const items = projectFromEvents(TOOL_TURN_EVENTS.map((raw: string) => rawEvent(raw)));
      const withCalls = items.filter((item: ConversationItem) => item.toolCalls.length > 0);
      expect(withCalls.length).assertEqual(1);
      expect(toolSummaryText(withCalls[0])).assertEqual('1 \u4e2a\u5de5\u5177 \u00b7 0.0s');
      expect(withCalls[0].streaming).assertFalse();
    });

    // ------------------------------------------------------ tool summary

    it('summarises tool calls in one line', 0, () => {
      const plain = applyEvent([], 40, eventOf(EVENT_CHUNK_TEXT));
      expect(toolSummaryText(plain[0])).assertEqual('');
      const pending = applyEvent([], 42, eventOf(EVENT_TOOL_CALL));
      expect(toolSummaryText(pending[0])).assertEqual('1 个工具 · 进行中');
      let done = applyEvent(pending, 43, eventOf(EVENT_TOOL_RESULT));
      expect(toolSummaryText(done[0])).assertEqual('1 个工具 · 0.0s');
    });

    it('stamps the tool start from the message that named it first', 0, () => {
      // Live ordering (measured 2026-09-11): the flat `assistant/message` lists the
      // requested call but carries no clock of its own; `tool/call` arrives next.
      // Left unstamped the summary measured from the epoch, which the page showed
      // as `1 个工具 · 29818317m25s`.
      let items = applyEvent([], 17, assistantEventAt(17, 1, 1, 1789099044641, 10, 1, true));
      expect(items[0].toolCalls.length).assertEqual(1);
      expect(items[0].toolCalls[0].startedAt).assertEqual(1789099044641);
      items = applyEvent(items, 42, eventOf(EVENT_TOOL_CALL));
      // The later call event must not rewrite the known start, and the fixture
      // call (same `call-1`) must not be duplicated.
      expect(items[0].toolCalls.length).assertEqual(1);
      expect(items[0].toolCalls[0].startedAt).assertEqual(1789099044641);
      items = applyEvent(items, 43, toolResultAt(43, 'call-1', 1789099044645));
      expect(items[0].toolCalls[0].done).assertTrue();
      expect(toolSummaryText(items[0])).assertEqual('1 个工具 · 0.0s');
    });

    // --------------------------------------------------- thinking indicator

    it('shows the thinking indicator until answer text streams', 0, () => {
      expect(shouldShowThinking([], false)).assertFalse();
      expect(shouldShowThinking([], true)).assertTrue();
      const reasoning = applyEvent([], 41, eventOf(EVENT_CHUNK_REASONING));
      expect(shouldShowThinking(reasoning, true)).assertTrue();
      const answering = applyEvent(reasoning, 40, eventOf(EVENT_CHUNK_TEXT));
      expect(shouldShowThinking(answering, true)).assertFalse();
      const finished = applyEvent(answering, 18, eventOf(EVENT_TURN_END));
      expect(shouldShowThinking(finished, false)).assertFalse();
      expect(shouldShowThinking(finished, true)).assertTrue();
    });

    // --------------------------------------------------- list item count

    it('counts every conversation page list item', 0, () => {
      // History header + run pill.
      expect(conversationListItemCount([], false, 0)).assertEqual(2);
      const reasoning = applyEvent([], 41, eventOf(EVENT_CHUNK_REASONING));
      // Header + message + thinking indicator + run pill; the same value is the
      // 0-based index of the first pending card.
      expect(conversationListItemCount(reasoning, true, 0)).assertEqual(4);
      // + one item per pending approval/question card.
      expect(conversationListItemCount(reasoning, true, 2)).assertEqual(6);
      const finished = applyEvent(reasoning, 18, eventOf(EVENT_TURN_END));
      expect(conversationListItemCount(finished, false, 1)).assertEqual(4);
    });
  });
}

/** `{totals:{...}}` usage shape (PROTOCOL.md §5) without a cast. */
class WrappedUsage {
  totals: WrappedTotals;

  constructor(input: number, output: number) {
    this.totals = new WrappedTotals(input, output);
  }
}

class WrappedTotals {
  inputTokens: number;
  outputTokens: number;

  constructor(input: number, output: number) {
    this.inputTokens = input;
    this.outputTokens = output;
  }
}
