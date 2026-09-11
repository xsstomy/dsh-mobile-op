/**
 * Directory / workspace-file helpers (pure logic, unit tested).
 *
 * Wire shapes (measured 2026-09-10):
 *   directories -> {path, home, crumbs:[{name,path,hidden}], entries:[{name,path,hidden}]}
 *   file-list   -> {requestId, sessionId, path, entries:[{name,path,kind,bytes,modifiedAt,mediaType}]}
 *   file-download-opened -> {transferId, name, mediaType, size, chunkBytes}
 *   file-download-chunk  -> {transferId, offset, data, eof, sha256?}
 */
import { WireDirectoryEntry } from './Types';

export enum PreviewKind {
  NONE = 'none',
  CODE = 'code',
  MARKDOWN = 'markdown',
  JSON = 'json',
  HTML = 'html',
  TEXT = 'text',
  IMAGE = 'image'
}

export interface FileEntryRow {
  name: string;
  path: string;
  isDirectory: boolean;
  bytes: number;
  modifiedAt: number;
  mediaType: string;
}

export interface CrumbRow {
  name: string;
  path: string;
}

function extensionOf(name: string): string {
  const dot = name.lastIndexOf('.');
  if (dot < 0 || dot === name.length - 1) {
    return '';
  }
  return name.substring(dot + 1).toLowerCase();
}

/** Which preview the client can render for this path (extension driven). */
export function previewKindOf(name: string): PreviewKind {
  const extension = extensionOf(name);
  if (extension === 'md' || extension === 'markdown') {
    return PreviewKind.MARKDOWN;
  }
  if (extension === 'json' || extension === 'json5') {
    return PreviewKind.JSON;
  }
  if (extension === 'html' || extension === 'htm') {
    return PreviewKind.HTML;
  }
  if (extension === 'png' || extension === 'jpg' || extension === 'jpeg' || extension === 'gif' ||
    extension === 'webp' || extension === 'bmp') {
    return PreviewKind.IMAGE;
  }
  const codeExtensions: string[] = [
    'ets', 'ts', 'tsx', 'js', 'jsx', 'mjs', 'cjs', 'kt', 'kts', 'swift', 'java', 'py', 'rb', 'go', 'rs',
    'c', 'h', 'cc', 'cpp', 'hpp', 'cs', 'sh', 'bash', 'zsh', 'ps1', 'sql', 'css', 'scss', 'less',
    'yaml', 'yml', 'toml', 'ini', 'conf', 'xml', 'gradle', 'properties', 'txt', 'log'
  ];
  if (codeExtensions.indexOf(extension) >= 0) {
    return PreviewKind.CODE;
  }
  return PreviewKind.NONE;
}

export function isTextPreview(kind: PreviewKind): boolean {
  return kind === PreviewKind.CODE || kind === PreviewKind.MARKDOWN || kind === PreviewKind.JSON ||
    kind === PreviewKind.HTML || kind === PreviewKind.TEXT;
}

/** Directories first, then files; hidden entries last; case-insensitive by name. */
export function sortEntries(entries: FileEntryRow[]): FileEntryRow[] {
  const sorted: FileEntryRow[] = [];
  for (const entry of entries) {
    sorted.push(entry);
  }
  sorted.sort((left: FileEntryRow, right: FileEntryRow) => {
    const leftHidden = left.name.startsWith('.');
    const rightHidden = right.name.startsWith('.');
    if (leftHidden !== rightHidden) {
      return leftHidden ? 1 : -1;
    }
    if (left.isDirectory !== right.isDirectory) {
      return left.isDirectory ? -1 : 1;
    }
    return left.name.toLowerCase() < right.name.toLowerCase() ? -1 : 1;
  });
  return sorted;
}

export function fileRowsFrom(entries: WireDirectoryEntry[]): FileEntryRow[] {
  const rows: FileEntryRow[] = [];
  for (const entry of entries) {
    rows.push({
      name: entry.name ?? '',
      path: entry.path ?? '',
      isDirectory: (entry.kind ?? '') === 'directory',
      bytes: typeof entry.bytes === 'number' ? entry.bytes : 0,
      modifiedAt: typeof entry.modifiedAt === 'number' ? entry.modifiedAt : 0,
      mediaType: entry.mediaType ?? ''
    });
  }
  return rows;
}

export function formatBytes(bytes: number): string {
  if (bytes <= 0) {
    return '0 B';
  }
  if (bytes < 1024) {
    return `${bytes} B`;
  }
  if (bytes < 1024 * 1024) {
    return `${(bytes / 1024).toFixed(1)} KB`;
  }
  if (bytes < 1024 * 1024 * 1024) {
    return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
  }
  return `${(bytes / 1024 / 1024 / 1024).toFixed(2)} GB`;
}

/** Next chunk offset must follow the server's instructions exactly. */
export function expectedNextOffset(chunkOffset: number, decodedBytes: number): number {
  return chunkOffset + decodedBytes;
}

export function sha256Matches(expected: string, actual: string): boolean {
  if (expected.length === 0) {
    return true;
  }
  return expected.toLowerCase() === actual.toLowerCase();
}

/** Join a directory path with a child name for the workspace-ish case. */
export function joinPath(base: string, name: string): string {
  if (base.length === 0 || base === '/') {
    return `/${name}`;
  }
  return base.endsWith('/') ? `${base}${name}` : `${base}/${name}`;
}
