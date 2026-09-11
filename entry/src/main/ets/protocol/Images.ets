/**
 * Image message helpers (pure logic, unit tested).
 *
 * OHOS measured limits (docs/spikes/2026-09-10-stage0-protocol-findings.md):
 * a JSON text frame above ~4 MB fails to send, so the client budget is 3.5 MB.
 * Base64 expands by ~4/3, and the host default caps a single image at ~3.5 MiB.
 */

export class ImageLimits {
  /** Frame budget for one outgoing JSON text frame. */
  frameBytes: number = 3.5 * 1024 * 1024;
  /** Raw bytes allowed for one image. */
  singleImageBytes: number = 2.5 * 1024 * 1024;
  maxImages: number = 8;
  /** Longest edge after downscaling. */
  maxEdge: number = 2048;
}

export const DEFAULT_IMAGE_LIMITS: ImageLimits = new ImageLimits();

export interface OutgoingImagePayload {
  mediaType: string;
  data: string;
  name: string;
}

export interface PreparedImageRow {
  name: string;
  mediaType: string;
  bytes: number;
  base64: string;
  sourceUri: string;
}

export function mediaTypeOfName(name: string): string {
  const lower = name.toLowerCase();
  if (lower.endsWith('.png')) {
    return 'image/png';
  }
  if (lower.endsWith('.webp')) {
    return 'image/webp';
  }
  if (lower.endsWith('.gif')) {
    return 'image/gif';
  }
  if (lower.endsWith('.bmp')) {
    return 'image/bmp';
  }
  return 'image/jpeg';
}

export function isSupportedMediaType(mediaType: string): boolean {
  return mediaType === 'image/png' || mediaType === 'image/jpeg' || mediaType === 'image/webp' ||
    mediaType === 'image/gif';
}

/** Bytes represented by a standard Base64 string (ignoring padding). */
export function base64ByteLength(base64: string): number {
  if (base64.length === 0) {
    return 0;
  }
  let padding = 0;
  if (base64.endsWith('==')) {
    padding = 2;
  } else if (base64.endsWith('=')) {
    padding = 1;
  }
  return Math.floor(base64.length / 4) * 3 - padding;
}

/** The frame that will be sent: JSON envelope + text + image payloads. */
export function outgoingFrameBytes(images: PreparedImageRow[], text: string): number {
  let total = text.length + 256;
  for (const image of images) {
    total += image.base64.length + image.name.length + image.mediaType.length + 64;
  }
  return total;
}

/** True when the message fits both the frame budget and the per-image limits. */
export function fitsImageBudget(images: PreparedImageRow[], text: string, limits: ImageLimits): boolean {
  if (images.length > limits.maxImages) {
    return false;
  }
  for (const image of images) {
    if (image.bytes > limits.singleImageBytes) {
      return false;
    }
    if (!isSupportedMediaType(image.mediaType)) {
      return false;
    }
  }
  return outgoingFrameBytes(images, text) <= limits.frameBytes;
}

export interface CompressTarget {
  width: number;
  height: number;
  quality: number;
}

/**
 * Downscale + quality target for the selected picture: keeps the longest edge
 * within `maxEdge` and lowers the JPEG quality until the estimate fits.
 */
export function compressTarget(width: number, height: number, limits: ImageLimits): CompressTarget {
  const longest = Math.max(width, height);
  let scale = 1;
  if (longest > limits.maxEdge && longest > 0) {
    scale = limits.maxEdge / longest;
  }
  const targetWidth = Math.max(1, Math.round(width * scale));
  const targetHeight = Math.max(1, Math.round(height * scale));
  // Rough JPEG estimate: 0.35 bytes per pixel at q=80, reduced by quality steps.
  const pixels = targetWidth * targetHeight;
  let quality = 80;
  while (quality > 40 && pixels * 0.35 * (quality / 80) > limits.singleImageBytes) {
    quality -= 10;
  }
  return { width: targetWidth, height: targetHeight, quality: quality };
}

/** Strip a `data:image/...;base64,` prefix when a caller passes one. */
export function stripDataUrl(value: string): string {
  const marker = 'base64,';
  const index = value.indexOf(marker);
  if (value.startsWith('data:') && index >= 0) {
    return value.substring(index + marker.length);
  }
  return value;
}
