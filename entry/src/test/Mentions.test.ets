import { describe, expect, it } from '@ohos/hypium';
import { FileEntryRow } from '../main/ets/protocol/Files';
import {
  activeAtToken, activeAtTokenInDraft, applyMention, filterMentionEntries, formatFileMention, mentionTargetOf
} from '../main/ets/protocol/Mentions';

function row(name: string, isDirectory: boolean): FileEntryRow {
  return { name: name, path: name, isDirectory: isDirectory, bytes: 0, modifiedAt: 0, mediaType: '' };
}

export default function mentionsTest(): void {
  describe('mentions', () => {
    it('detects a plain @ token ending at the caret', 0, () => {
      const token = activeAtToken('@src', 4);
      expect(token !== undefined).assertTrue();
      expect(token?.prefix).assertEqual('@src');
      expect(token?.query).assertEqual('src');
      expect(token?.quoted).assertFalse();
      expect(activeAtToken('hi @', 4)?.query).assertEqual('');
      expect(activeAtToken('cmd @x', 6)?.prefix).assertEqual('@x');
    });

    it('ignores an @ inside a word (email) and whitespace-terminated tokens', 0, () => {
      expect(activeAtToken('a@b', 3) === undefined).assertTrue();
      expect(activeAtToken('@a b', 4) === undefined).assertTrue();
      expect(activeAtToken('plain text', 10) === undefined).assertTrue();
    });

    it('detects an open quoted path that may contain spaces', 0, () => {
      const token = activeAtToken('@"my dir', 8);
      expect(token !== undefined).assertTrue();
      expect(token?.quoted).assertTrue();
      expect(token?.query).assertEqual('my dir');
      expect(activeAtToken('@"done" x', 9) === undefined).assertTrue();
    });

    it('finds the token on the caret line of a multi-line draft', 0, () => {
      const draft = '第一行\n请读 @sr';
      const token = activeAtTokenInDraft(draft, draft.length);
      expect(token !== undefined).assertTrue();
      expect(token?.query).assertEqual('sr');
      // The caret on the first line must not see the second line token.
      expect(activeAtTokenInDraft(draft, 2) === undefined).assertTrue();
    });

    it('routes a multi-segment query to its parent directory', 0, () => {
      expect(mentionTargetOf('').directory).assertEqual('');
      expect(mentionTargetOf('src').prefix).assertEqual('src');
      expect(mentionTargetOf('src/').directory).assertEqual('src');
      expect(mentionTargetOf('src/').prefix).assertEqual('');
      expect(mentionTargetOf('src/comp').directory).assertEqual('src');
      expect(mentionTargetOf('src/comp').prefix).assertEqual('comp');
    });

    it('filters candidate names case-insensitively by prefix', 0, () => {
      const rows = [row('src', true), row('main.ets', false), row('SrcX', false)];
      const matched = filterMentionEntries(rows, 'sr');
      expect(matched.length).assertEqual(2);
      expect(matched[0].name).assertEqual('src');
      expect(matched[1].name).assertEqual('SrcX');
      expect(filterMentionEntries(rows, '').length).assertEqual(3);
    });

    it('formats paths with the quoted grammar when they contain spaces', 0, () => {
      expect(formatFileMention('a/b.ets', false, false)).assertEqual('@a/b.ets');
      expect(formatFileMention('src', true, false)).assertEqual('@src/');
      expect(formatFileMention('my file.txt', false, false)).assertEqual('@"my file.txt"');
      expect(formatFileMention('my dir', true, false)).assertEqual('@"my dir/');
      expect(formatFileMention('a.ets', false, true)).assertEqual('@"a.ets"');
      expect(formatFileMention('bad"name', false, false) === undefined).assertTrue();
    });

    it('splices a completion over the token and reports the new caret', 0, () => {
      // '请读 @sr' is 6 chars; the caret sits at its end.
      const token = activeAtToken('请读 @sr', 6);
      expect(token !== undefined).assertTrue();
      if (token === undefined) {
        return;
      }
      const spliced = applyMention('请读 @sr', 6, token, '@src/main.ets');
      expect(spliced.text).assertEqual('请读 @src/main.ets');
      expect(spliced.caret).assertEqual(3 + '@src/main.ets'.length);
    });
  });
}
