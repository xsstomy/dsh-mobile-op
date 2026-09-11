import { describe, expect, it } from '@ohos/hypium';
import {
  FileEntryRow, PreviewKind, expectedNextOffset, fileRowsFrom, formatBytes, isTextPreview, joinPath,
  previewKindOf, sha256Matches, sortEntries
} from '../main/ets/protocol/Files';
import { WireDirectoryEntry } from '../main/ets/protocol/Types';

function row(name: string, isDirectory: boolean): FileEntryRow {
  return { name: name, path: name, isDirectory: isDirectory, bytes: 1, modifiedAt: 0, mediaType: '' };
}

export default function filesTest(): void {
  describe('files', () => {
    it('picks a preview kind from the extension', 0, () => {
      expect(previewKindOf('README.md')).assertEqual(PreviewKind.MARKDOWN);
      expect(previewKindOf('data.json')).assertEqual(PreviewKind.JSON);
      expect(previewKindOf('index.html')).assertEqual(PreviewKind.HTML);
      expect(previewKindOf('shot.PNG')).assertEqual(PreviewKind.IMAGE);
      expect(previewKindOf('app.ets')).assertEqual(PreviewKind.CODE);
      expect(previewKindOf('archive.zip')).assertEqual(PreviewKind.NONE);
      expect(previewKindOf('Makefile')).assertEqual(PreviewKind.NONE);
    });

    it('knows which kinds are text previews', 0, () => {
      expect(isTextPreview(PreviewKind.CODE)).assertTrue();
      expect(isTextPreview(PreviewKind.MARKDOWN)).assertTrue();
      expect(isTextPreview(PreviewKind.IMAGE)).assertFalse();
      expect(isTextPreview(PreviewKind.NONE)).assertFalse();
    });

    it('sorts directories first, hidden last, case-insensitively', 0, () => {
      const sorted = sortEntries([
        row('zebra.txt', false),
        row('.git', true),
        row('src', true),
        row('Apple.md', false)
      ]);
      const names: string[] = [];
      for (const entry of sorted) {
        names.push(entry.name);
      }
      expect(names.join(',')).assertEqual('src,Apple.md,zebra.txt,.git');
    });

    it('maps wire entries and formats sizes', 0, () => {
      const entries: WireDirectoryEntry[] = [
        { name: 'src', path: 'src', kind: 'directory' },
        { name: 'a.txt', path: 'a.txt', kind: 'file', bytes: 2048, modifiedAt: 1 }
      ];
      const rows = fileRowsFrom(entries);
      expect(rows.length).assertEqual(2);
      expect(rows[0].isDirectory).assertTrue();
      expect(rows[1].bytes).assertEqual(2048);
      expect(formatBytes(2048)).assertEqual('2.0 KB');
      expect(formatBytes(0)).assertEqual('0 B');
      expect(formatBytes(3 * 1024 * 1024)).assertEqual('3.0 MB');
    });

    it('follows the server chunk offsets when the base64 decodes shorter', 0, () => {
      // 96 base64 chars decode to 72 bytes; the next offset is server-provided.
      expect(expectedNextOffset(0, 72)).assertEqual(72);
      expect(expectedNextOffset(524288, 0)).assertEqual(524288);
    });

    it('compares sha256 digests case-insensitively and skips empty expectations', 0, () => {
      expect(sha256Matches('EADB', 'eadb')).assertTrue();
      expect(sha256Matches('eadb', 'dead')).assertFalse();
      expect(sha256Matches('', 'anything')).assertTrue();
    });

    it('joins directory paths', 0, () => {
      expect(joinPath('/home/user', 'work')).assertEqual('/home/user/work');
      expect(joinPath('/', 'Users')).assertEqual('/Users');
      expect(joinPath('/a/', 'b')).assertEqual('/a/b');
    });
  });
}
