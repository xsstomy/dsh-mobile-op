import { describe, expect, it } from '@ohos/hypium';
import { decodeBase64Url, encodeBase64Url, isValidBase64Url } from '../main/ets/protocol/Base64Url';
import { PairingError, PairingErrorKind, parsePairingPayload } from '../main/ets/protocol/PairingPayload';

const NOW = 1789043000000;

function withVersion(version: number): PairingOverrides {
  const overrides = new PairingOverrides();
  overrides.version = version;
  return overrides;
}

function withUrl(url: string): PairingOverrides {
  const overrides = new PairingOverrides();
  overrides.publicUrl = url;
  return overrides;
}

function withCode(code: string): PairingOverrides {
  const overrides = new PairingOverrides();
  overrides.pairingCode = code;
  return overrides;
}

function withExpiry(expiresAt: number): PairingOverrides {
  const overrides = new PairingOverrides();
  overrides.expiresAt = expiresAt;
  return overrides;
}

class PairingOverrides {
  version?: number;
  publicUrl?: string;
  pairingCode?: string;
  expiresAt?: number;
}

function payloadText(overrides: PairingOverrides): string {
  const version = overrides.version ?? 2;
  const publicUrl = overrides.publicUrl ?? 'ws://10.0.2.2:3081/ws/mobile';
  const pairingCode = overrides.pairingCode ?? 'EiIdOBwUTyeDBi_4-PkGAkTT_dv8QgkLM3i0MDY84wk';
  const expiresAt = overrides.expiresAt ?? NOW + 60000;
  const json = `{"version":${version},"publicUrl":"${publicUrl}","pairingCode":"${pairingCode}","expiresAt":${expiresAt}}`;
  return encodeBase64Url(json);
}

export default function pairingTest(): void {
  describe('pairing', () => {
    it('accepts a valid v2 payload', 0, () => {
      const parsed = parsePairingPayload(payloadText(new PairingOverrides()), NOW);
      expect(parsed.version).assertEqual(2);
      expect(parsed.publicUrl).assertEqual('ws://10.0.2.2:3081/ws/mobile');
      expect(parsed.pairingCode.length > 0).assertTrue();
    });

    it('accepts wss endpoints', 0, () => {
      const parsed = parsePairingPayload(payloadText(withUrl('wss://gw.example.com/ws/mobile')), NOW);
      expect(parsed.publicUrl).assertEqual('wss://gw.example.com/ws/mobile');
    });

    it('rejects padding and non-Base64URL characters', 0, () => {
      const encoded = payloadText(new PairingOverrides());
      expect(isValidBase64Url(`${encoded}==`)).assertFalse();
      expect(isValidBase64Url('ab+cd')).assertFalse();
      expect(isValidBase64Url('ab/cd')).assertFalse();
      expect(isValidBase64Url('ab cd')).assertFalse();
      expect(decodeBase64Url(`${encoded}=`)).assertNull();
      let raised = false;
      try {
        parsePairingPayload(`${encoded}`, NOW);
      } catch (error) {
        raised = true;
      }
      expect(raised).assertFalse();
    });

    it('rejects a payload whose Base64URL body is not JSON', 0, () => {
      let kind = '';
      try {
        parsePairingPayload(encodeBase64Url('plain text'), NOW);
      } catch (error) {
        kind = (error as PairingError).kind;
      }
      expect(kind).assertEqual(PairingErrorKind.INVALID_JSON);
    });

    it('rejects unsupported versions', 0, () => {
      let kind = '';
      try {
        parsePairingPayload(payloadText(withVersion(3)), NOW);
      } catch (error) {
        kind = (error as PairingError).kind;
      }
      expect(kind).assertEqual(PairingErrorKind.UNSUPPORTED_VERSION);
    });

    it('rejects expired payloads', 0, () => {
      let kind = '';
      try {
        parsePairingPayload(payloadText(withExpiry(NOW - 1)), NOW);
      } catch (error) {
        kind = (error as PairingError).kind;
      }
      expect(kind).assertEqual(PairingErrorKind.EXPIRED);
    });

    it('rejects non-websocket endpoints', 0, () => {
      let kind = '';
      try {
        parsePairingPayload(payloadText(withUrl('https://example.com/ws/mobile')), NOW);
      } catch (error) {
        kind = (error as PairingError).kind;
      }
      expect(kind).assertEqual(PairingErrorKind.INVALID_ENDPOINT);
    });

    it('rejects a pairing code containing a comma or whitespace', 0, () => {
      let kind = '';
      try {
        parsePairingPayload(payloadText(withCode('a,b')), NOW);
      } catch (error) {
        kind = (error as PairingError).kind;
      }
      expect(kind).assertEqual(PairingErrorKind.INVALID_CODE);

      kind = '';
      try {
        parsePairingPayload(payloadText(withCode('a b')), NOW);
      } catch (error) {
        kind = (error as PairingError).kind;
      }
      expect(kind).assertEqual(PairingErrorKind.INVALID_CODE);
    });

    it('round-trips base64url encoding', 0, () => {
      const original = '{"a":"b+c/d"}';
      expect(decodeBase64Url(encodeBase64Url(original))).assertEqual(original);
    });
  });
}
