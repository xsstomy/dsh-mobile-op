/**
 * Message body renderer: Markdown segments with the design system typography.
 *
 * Inline emphasis, code highlighting and tables are rendered with `Text` + `Span`
 * children (no StyledString controller plumbing needed).
 */
import { AppColors, AppFont, AppRadius, Glass } from '../common/Constants';
import {
  CodeSpan, InlineKind, InlineSpan, MarkdownSegment, SegmentKind, TokenKind, highlightCode, parseInline,
  segmentMarkdown
} from '../common/Format';

function textColorOf(dimmed: boolean): ResourceColor {
  return dimmed ? AppColors.INK_WEAK : AppColors.DARK_INK;
}

function inlineColor(kind: InlineKind, dimmed: boolean): ResourceColor {
  if (kind === InlineKind.CODE || kind === InlineKind.LINK) {
    return AppColors.MIST;
  }
  return textColorOf(dimmed);
}

function tokenColor(kind: TokenKind): ResourceColor {
  switch (kind) {
    case TokenKind.KEYWORD:
      return '#C792EA';
    case TokenKind.STRING:
      return '#A5E075';
    case TokenKind.COMMENT:
      return '#7A8AA5';
    case TokenKind.NUMBER:
      return '#F5A97F';
    case TokenKind.FUNCTION:
      return '#82AAFF';
    default:
      return AppColors.DARK_INK;
  }
}

/** One line of text with inline emphasis rendered as Span children. */
@Builder
function inlineText(text: string, dimmed: boolean, fontSize: number, lineHeight: number) {
  Text() {
    ForEach(parseInline(text), (span: InlineSpan, index: number) => {
      Span(span.text)
        .fontColor(inlineColor(span.kind, dimmed))
        .fontSize(span.kind === InlineKind.CODE ? AppFont.MONO : fontSize)
        .fontWeight(span.kind === InlineKind.BOLD ? FontWeight.Bold : FontWeight.Normal)
        .fontStyle(span.kind === InlineKind.ITALIC ? FontStyle.Italic : FontStyle.Normal)
        .decoration({
          type: span.kind === InlineKind.STRIKE ? TextDecorationType.LineThrough : TextDecorationType.None,
          color: AppColors.INK_WEAK
        })
    }, (span: InlineSpan, index: number) => `${index}-${span.kind}-${span.text.length}`)
  }
  .lineHeight(lineHeight)
  .width('100%')
  .textAlign(TextAlign.Start)
}

@Builder
function headingView(segment: MarkdownSegment) {
  Text(segment.text)
    .fontSize(segment.level <= 1 ? AppFont.TITLE : (segment.level === 2 ? AppFont.HEADING : AppFont.SUBTITLE))
    .fontWeight(FontWeight.Bold)
    .fontColor(AppColors.DARK_INK)
    .width('100%')
    .margin({ top: 6, bottom: 2 })
}

@Builder
function codeView(segment: MarkdownSegment) {
  Column({ space: 6 }) {
    if (segment.language.length > 0) {
      Text(segment.language.toUpperCase())
        .fontSize(10)
        .fontColor(Glass.CODE_LABEL)
        .width('100%')
    }
    Text() {
      ForEach(highlightCode(segment.text, segment.language), (token: CodeSpan, index: number) => {
        Span(token.text)
          .fontSize(AppFont.MONO)
          .fontColor(tokenColor(token.kind))
      }, (token: CodeSpan, index: number) => `${index}-${token.kind}-${token.text.length}`)
    }
    .width('100%')
    .textAlign(TextAlign.Start)
  }
  .alignItems(HorizontalAlign.Start)
  .width('100%')
  .padding({ left: 12, right: 12, top: 10, bottom: 10 })
  .backgroundColor(Glass.CODE_FILL)
  .borderRadius(AppRadius.CARD_SMALL)
  .margin({ top: 4, bottom: 4 })
}

@Builder
function tableView(segment: MarkdownSegment) {
  Column({ space: 0 }) {
    ForEach(segment.rows, (row: string[], rowIndex: number) => {
      Row({ space: 0 }) {
        ForEach(row, (cell: string, cellIndex: number) => {
          Text(cell)
            .fontSize(AppFont.CAPTION)
            .fontColor(rowIndex === 0 ? AppColors.DARK_INK : AppColors.INK_WEAK)
            .fontWeight(rowIndex === 0 ? FontWeight.Bold : FontWeight.Normal)
            .layoutWeight(1)
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .padding(6)
        }, (cell: string, cellIndex: number) => `${rowIndex}-${cellIndex}-${cell.length}`)
      }
      .width('100%')
      .border({
        width: { bottom: 1 },
        color: Glass.BORDER_SOFT
      })
    }, (row: string[], rowIndex: number) => `${rowIndex}-${row.length}`)
  }
  .width('100%')
  .padding(4)
  .backgroundColor(Glass.CODE_FILL)
  .borderRadius(AppRadius.CARD_SMALL)
  .margin({ top: 4, bottom: 4 })
}

@Builder
function quoteView(segment: MarkdownSegment) {
  Row() {
    Divider()
      .vertical(true)
      .strokeWidth(2)
      .color(AppColors.BRAND)
      .height('100%')
    Column() {
      inlineText(segment.text, true, AppFont.BODY, 24)
    }
    .layoutWeight(1)
    .padding({ left: 10 })
  }
  .width('100%')
  .alignItems(VerticalAlign.Top)
  .margin({ top: 4, bottom: 4 })
}

/** Render one message body as a stack of Markdown segments. */
@Builder
export function messageContentView(text: string, dimmed: boolean) {
  Column({ space: 6 }) {
    ForEach(segmentMarkdown(text), (segment: MarkdownSegment, index: number) => {
      if (segment.kind === SegmentKind.HEADING) {
        headingView(segment)
      } else if (segment.kind === SegmentKind.CODE) {
        codeView(segment)
      } else if (segment.kind === SegmentKind.TABLE) {
        tableView(segment)
      } else if (segment.kind === SegmentKind.RULE) {
        Divider()
          .strokeWidth(1)
          .color(Glass.BORDER_SOFT)
          .margin({ top: 8, bottom: 8 })
      } else if (segment.kind === SegmentKind.QUOTE) {
        quoteView(segment)
      } else if (segment.kind === SegmentKind.LIST) {
        Row({ space: 8 }) {
          Text('•').fontSize(AppFont.BODY).fontColor(AppColors.MIST)
          Column() {
            inlineText(segment.text, dimmed, AppFont.BODY, 24)
          }
          .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
      } else {
        inlineText(segment.text, dimmed, AppFont.BODY, 26)
      }
    }, (segment: MarkdownSegment, index: number) => `${index}-${segment.kind}-${segment.text.length}`)
  }
  .alignItems(HorizontalAlign.Start)
  .width('100%')
}
