import { describe, expect, it } from '@ohos/hypium';
import {
  InlineKind, InlineSpan, MarkdownSegment, SegmentKind, TokenKind, CodeSpan, highlightCode, parseInline,
  previewOf, relativeTime, segmentMarkdown, clockTimeOf, durationLabel, tokenLabel, turnFooterText
} from '../main/ets/common/Format';

const NOW = 1789045000000;

export default function formatTest(): void {
  describe('format', () => {
    it('formats relative time buckets', 0, () => {
      expect(relativeTime(NOW - 5 * 1000, NOW)).assertEqual('刚刚');
      expect(relativeTime(NOW - 40 * 60 * 1000, NOW)).assertEqual('40 分钟前');
      expect(relativeTime(NOW - 3 * 60 * 60 * 1000, NOW)).assertEqual('3 小时前');
      expect(relativeTime(NOW - 30 * 60 * 60 * 1000, NOW)).assertEqual('昨天');
      expect(relativeTime(NOW - 5 * 24 * 60 * 60 * 1000, NOW)).assertEqual('5 天前');
      expect(relativeTime(0, NOW)).assertEqual('');
    });

    it('segments headings, code fences, rules, quotes, lists and paragraphs', 0, () => {
      const text = [
        '# 验证',
        '',
        '普通段落第一行',
        '第二行',
        '',
        '```bash',
        'dsh --profile web --dump-config',
        '```',
        '',
        '---',
        '',
        '> 引用内容',
        '',
        '- 列表项一',
        '- 列表项二',
        '',
        '## 小节',
        '结尾'
      ].join('\n');
      const segments: MarkdownSegment[] = segmentMarkdown(text);
      const kinds: string[] = [];
      for (const segment of segments) {
        kinds.push(segment.kind);
      }
      expect(kinds.length).assertEqual(9);
      expect(kinds[0]).assertEqual('heading');
      expect(kinds[1]).assertEqual('paragraph');
      expect(kinds[2]).assertEqual('code');
      expect(kinds[3]).assertEqual('rule');
      expect(kinds[4]).assertEqual('quote');
      expect(kinds[5]).assertEqual('list');
      expect(kinds[6]).assertEqual('list');
      expect(kinds[7]).assertEqual('heading');
      expect(kinds[8]).assertEqual('paragraph');
      expect(segments[0].level).assertEqual(1);
      expect(segments[0].text).assertEqual('验证');
      expect(segments[1].text).assertEqual('普通段落第一行\n第二行');
      expect(segments[2].language).assertEqual('bash');
      expect(segments[2].text).assertEqual('dsh --profile web --dump-config');
      expect(segments[5].text).assertEqual('列表项一');
      expect(segments[7].level).assertEqual(2);
    });

    it('keeps an unterminated code fence as a code segment', 0, () => {
      const segments = segmentMarkdown('```ts\nconst a = 1;');
      expect(segments.length).assertEqual(1);
      expect(segments[0].kind).assertEqual(SegmentKind.CODE);
      expect(segments[0].language).assertEqual('ts');
      expect(segments[0].text).assertEqual('const a = 1;');
    });

    it('does not treat a hash without a space as a heading', 0, () => {
      const segments = segmentMarkdown('#NotAHeading');
      expect(segments.length).assertEqual(1);
      expect(segments[0].kind).assertEqual(SegmentKind.PARAGRAPH);
    });

    it('handles numbered lists and asterisk rules', 0, () => {
      const segments = segmentMarkdown('1. 第一步\n2. 第二步\n***\n结束');
      const kinds: string[] = [];
      for (const segment of segments) {
        kinds.push(segment.kind);
      }
      expect(kinds.join(',')).assertEqual('list,list,rule,paragraph');
      expect(segments[0].text).assertEqual('第一步');
    });

    it('parses a markdown table into rows', 0, () => {
      const segments = segmentMarkdown('| 名称 | 值 |\n| --- | --- |\n| 轮次 | 7 |\n| 步骤 | 53 |');
      expect(segments.length).assertEqual(1);
      expect(segments[0].kind).assertEqual(SegmentKind.TABLE);
      expect(segments[0].rows.length).assertEqual(3);
      expect(segments[0].rows[0].join('|')).assertEqual('名称|值');
      expect(segments[0].rows[2][1]).assertEqual('53');
    });

    it('does not treat a lone pipe line as a table', 0, () => {
      const segments = segmentMarkdown('a | b');
      expect(segments.length).assertEqual(1);
      expect(segments[0].kind).assertEqual(SegmentKind.PARAGRAPH);
    });

    it('parses inline bold, italic, code, strike and links', 0, () => {
      const spans: InlineSpan[] = parseInline('看 **这段** 和 `代码` 以及 [链接](https://a.b) ~~删~~ *斜*');
      expect(spans.length).assertEqual(10);
      expect(spans[0].kind).assertEqual(InlineKind.PLAIN);
      expect(spans[0].text).assertEqual('看 ');
      expect(spans[1].kind).assertEqual(InlineKind.BOLD);
      expect(spans[1].text).assertEqual('这段');
      expect(spans[2].kind).assertEqual(InlineKind.PLAIN);
      expect(spans[2].text).assertEqual(' 和 ');
      expect(spans[3].kind).assertEqual(InlineKind.CODE);
      expect(spans[3].text).assertEqual('代码');
      expect(spans[4].kind).assertEqual(InlineKind.PLAIN);
      expect(spans[4].text).assertEqual(' 以及 ');
      expect(spans[5].kind).assertEqual(InlineKind.LINK);
      expect(spans[5].text).assertEqual('链接');
      expect(spans[6].kind).assertEqual(InlineKind.PLAIN);
      expect(spans[6].text).assertEqual(' ');
      expect(spans[7].kind).assertEqual(InlineKind.STRIKE);
      expect(spans[7].text).assertEqual('删');
      expect(spans[8].kind).assertEqual(InlineKind.PLAIN);
      expect(spans[8].text).assertEqual(' ');
      expect(spans[9].kind).assertEqual(InlineKind.ITALIC);
      expect(spans[9].text).assertEqual('斜');
    });

    it('keeps an unterminated marker as plain text', 0, () => {
      const spans = parseInline('a **b');
      expect(spans.length).assertEqual(1);
      expect(spans[0].kind).assertEqual(InlineKind.PLAIN);
      expect(spans[0].text).assertEqual('a **b');
    });

    it('highlights comments, strings, numbers and keywords', 0, () => {
      const spans: CodeSpan[] = highlightCode('# 注释\nconst a = 42\necho "hi"', 'bash');
      const rendered: string[] = [];
      for (const span of spans) {
        rendered.push(`${span.kind}:${span.text}`);
      }
      const joined = rendered.join('|');
      expect(joined.indexOf('comment:# 注释') >= 0).assertTrue();
      expect(joined.indexOf('keyword:const') >= 0).assertTrue();
      expect(joined.indexOf('number:42') >= 0).assertTrue();
      expect(joined.indexOf('string:"hi"') >= 0).assertTrue();
    });

    it('marks called identifiers as functions', 0, () => {
      const spans = highlightCode('buildThing(1)', 'ts');
      let functions = 0;
      for (const span of spans) {
        if (span.kind === TokenKind.FUNCTION) {
          functions += 1;
        }
      }
      expect(functions).assertEqual(1);
    });

    it('returns nothing for empty text', 0, () => {
      expect(segmentMarkdown('').length).assertEqual(0);
    });

    it('builds a single-line preview', 0, () => {
      expect(previewOf('# 标题\n\n正文**内容**', 20)).assertEqual('标题 正文内容');
      expect(previewOf('1234567890', 5)).assertEqual('12345…');
    });

    it('labels elapsed durations, or nothing when unknown', 0, () => {
      expect(durationLabel(12300)).assertEqual('12.3s');
      expect(durationLabel(80000)).assertEqual('1m20s');
      expect(durationLabel(0)).assertEqual('');
      expect(durationLabel(-5)).assertEqual('');
    });

    it('formats the answer clock time for today and earlier days', 0, () => {
      const today = clockTimeOf(NOW, NOW);
      expect(today.length).assertEqual(5);
      expect(today.indexOf(':')).assertEqual(2);
      // 3 days back (same instant of day, never crossing a month by accident).
      const older = clockTimeOf(NOW - 3 * 24 * 60 * 60 * 1000, NOW);
      expect(older.length).assertEqual(11);
      expect(clockTimeOf(0, NOW)).assertEqual('');
      expect(clockTimeOf(NOW, 0)).assertEqual(today);
    });

    it('builds the turn footer and drops the segments without data', 0, () => {
      const full = turnFooterText(1200, NOW - 12300, NOW, NOW);
      expect(full.substring(full.indexOf(' · ') + 3, full.lastIndexOf(' · '))).assertEqual('用时 12.3s');
      expect(full.indexOf('1.2k tokens')).assertEqual(0);
      expect(full.indexOf(clockTimeOf(NOW, NOW)) > 0).assertTrue();
      // Tokens only: no duration, no clock (turn still running).
      expect(turnFooterText(1200, 0, 0, NOW)).assertEqual('1.2k tokens');
      // Nothing known at all: the footer must not render a bare separator.
      expect(turnFooterText(0, 0, 0, NOW)).assertEqual('');
      // Clock only, with a start time that makes the duration meaningless.
      expect(turnFooterText(0, NOW, NOW, NOW).length > 0).assertTrue();
      expect(turnFooterText(0, NOW, NOW, NOW).indexOf('用时')).assertEqual(-1);
      expect(tokenLabel(999)).assertEqual('999');
      expect(tokenLabel(1500000)).assertEqual('1.5M');
    });
  });
}
