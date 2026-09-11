/**
 * One-time pairing payload decoding.
 *
 * Wire format (see docs/PROTOCOL.md §1): the QR/manual string is the UTF-8 JSON
 * object `{version, publicUrl, pairingCode, expiresAt}` encoded as unpadded
 * Base64URL. Validation mirrors the upstream strict parser.
 */
import { decodeBase64Url } from './Base64Url';

export enum PairingErrorKind {
  INVALID_BASE64URL = 'invalid-base64url',
  INVALID_JSON = 'invalid-json',
  UNSUPPORTED_VERSION = 'unsupported-version',
  INVALID_ENDPOINT = 'invalid-endpoint',
  INVALID_CODE = 'invalid-code',
  EXPIRED = 'expired'
}

export class PairingError extends Error {
  readonly kind: PairingErrorKind;

  constructor(kind: PairingErrorKind, message: string) {
    super(message);
    this.kind = kind;
  }
}

export interface GatewayPairingPayload {
  version: number;
  publicUrl: string;
  pairingCode: string;
  expiresAt: number;
}

function hasControlOrSpace(value: string): boolean {
  for (let index = 0; index < value.length; index += 1) {
    const code = value.charCodeAt(index);
    if (code <= 0x20 || code === 0x7f) {
      return true;
    }
  }
  return false;
}

export function isWebSocketUrl(value: string): boolean {
  const lower = value.toLowerCase();
  if (!lower.startsWith('ws://') && !lower.startsWith('wss://')) {
    return false;
  }
  const rest = lower.startsWith('wss://') ? value.substring(6) : value.substring(5);
  if (rest.length === 0) {
    return false;
  }
  const authorityEnd = rest.search(/[/?#]/);
  const authority = authorityEnd >= 0 ? rest.substring(0, authorityEnd) : rest;
  return authority.length > 0 && authority !== ':';
}

export function parsePairingPayload(rawValue: string, nowMilliseconds: number): GatewayPairingPayload {
  const trimmed = rawValue.replace(/^\s+|\s+$/g, '');
  const decoded = decodeBase64Url(trimmed);
  if (decoded === null) {
    throw new PairingError(PairingErrorKind.INVALID_BASE64URL, '配对内容不是有效的 Base64URL 字符串');
  }
  let payload: GatewayPairingPayload;
  try {
    payload = JSON.parse(decoded) as GatewayPairingPayload;
  } catch (error) {
    void error;
    throw new PairingError(PairingErrorKind.INVALID_JSON, 'Base64URL 解码后的内容不是有效的配对 JSON');
  }
  if (payload === null || typeof payload !== 'object') {
    throw new PairingError(PairingErrorKind.INVALID_JSON, 'Base64URL 解码后的内容不是有效的配对 JSON');
  }
  if (payload.version !== 2) {
    throw new PairingError(PairingErrorKind.UNSUPPORTED_VERSION, `不支持的配对协议版本 ${payload.version}`);
  }
  if (typeof payload.publicUrl !== 'string' || !isWebSocketUrl(payload.publicUrl)) {
    throw new PairingError(PairingErrorKind.INVALID_ENDPOINT, '配对内容中的 WebSocket 地址无效');
  }
  if (typeof payload.pairingCode !== 'string' || payload.pairingCode.length === 0 ||
    payload.pairingCode.indexOf(',') >= 0 || hasControlOrSpace(payload.pairingCode)) {
    throw new PairingError(PairingErrorKind.INVALID_CODE, '二维码中的一次性 pairingCode 无效');
  }
  if (typeof payload.expiresAt !== 'number' || payload.expiresAt <= nowMilliseconds) {
    throw new PairingError(PairingErrorKind.EXPIRED, '二维码配对码已经过期');
  }
  return {
    version: payload.version,
    publicUrl: payload.publicUrl,
    pairingCode: payload.pairingCode,
    expiresAt: payload.expiresAt
  };
}

/**
 * Emulator/host override: the payload advertises what the WebUI generated, but a
 * phone on the LAN (or an emulator behind QEMU slirp) may need a different host.
 */
export function overrideEndpoint(payload: GatewayPairingPayload, endpoint: string): GatewayPairingPayload {
  return {
    version: payload.version,
    publicUrl: endpoint,
    pairingCode: payload.pairingCode,
    expiresAt: payload.expiresAt
  };
}
