/**
 * Strict Base64URL codec.
 *
 * Mirrors the upstream clients (PairingPayloadParser.swift /
 * GatewayPairingPayloadParser): only `A-Z a-z 0-9 - _`, no padding, and a
 * length of `% 4 != 1`. Anything else is rejected instead of being "repaired".
 */
import { buffer } from '@kit.ArkTS';

export function isBase64UrlCharacter(code: number): boolean {
  if (code >= 65 && code <= 90) {
    return true;
  }
  if (code >= 97 && code <= 122) {
    return true;
  }
  if (code >= 48 && code <= 57) {
    return true;
  }
  return code === 45 || code === 95;
}

export function isValidBase64Url(value: string): boolean {
  if (value.length === 0 || value.indexOf('=') >= 0 || value.length % 4 === 1) {
    return false;
  }
  for (let index = 0; index < value.length; index += 1) {
    if (!isBase64UrlCharacter(value.charCodeAt(index))) {
      return false;
    }
  }
  return true;
}

/** Decode strictly; returns null when the input is not valid Base64URL. */
export function decodeBase64Url(value: string): string | null {
  if (!isValidBase64Url(value)) {
    return null;
  }
  let normalized = value.replace(/-/g, '+').replace(/_/g, '/');
  while (normalized.length % 4 !== 0) {
    normalized += '=';
  }
  try {
    return buffer.from(normalized, 'base64').toString('utf8');
  } catch (error) {
    void error;
    return null;
  }
}

export function encodeBase64Url(value: string): string {
  const encoded = buffer.from(value, 'utf8').toString('base64');
  return encoded.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}
