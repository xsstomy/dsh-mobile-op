/**
 * Long-lived device token storage.
 *
 * Primary store: Asset Store Kit (system key management, never plain text on
 * disk). Fallback: preferences, used only when ASSET is unavailable on the
 * running device, so the client keeps working instead of losing the pairing.
 */
import { asset } from '@kit.AssetStoreKit';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'TokenStore';
const PREF_STORE = 'dsh_mobile_prefs';
const PREF_KEY_PREFIX = 'token:';

function encoder(): util.TextEncoder {
  return new util.TextEncoder();
}

function toBytes(value: string): Uint8Array {
  return encoder().encodeInto(value);
}

function fromBytes(value: Uint8Array): string {
  return util.TextDecoder.create('utf-8').decodeToString(value);
}

export class TokenStore {
  private fallback: preferences.Preferences | undefined;

  async attach(context: common.Context): Promise<void> {
    try {
      this.fallback = await preferences.getPreferences(context, PREF_STORE);
    } catch (error) {
      hilog.warn(0x0000, TAG, 'preferences unavailable: %{public}s', JSON.stringify(error));
    }
  }

  private aliasFor(endpoint: string): string {
    return `dsh-mobile:${endpoint}`;
  }

  async save(endpoint: string, token: string): Promise<void> {
    const attributes: asset.AssetMap = new Map<asset.Tag, asset.Value>();
    attributes.set(asset.Tag.ALIAS, toBytes(this.aliasFor(endpoint)));
    attributes.set(asset.Tag.SECRET, toBytes(token));
    attributes.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
    try {
      await asset.remove(attributes);
    } catch (error) {
      void error;
    }
    try {
      await asset.add(attributes);
      return;
    } catch (error) {
      hilog.warn(0x0000, TAG, 'asset add failed, falling back to preferences: %{public}s', JSON.stringify(error));
    }
    await this.saveFallback(endpoint, token);
  }

  async load(endpoint: string): Promise<string> {
    const query: asset.AssetMap = new Map<asset.Tag, asset.Value>();
    query.set(asset.Tag.ALIAS, toBytes(this.aliasFor(endpoint)));
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    try {
      const results: asset.AssetMap[] = await asset.query(query);
      if (results.length > 0) {
        const secret = results[0].get(asset.Tag.SECRET);
        if (secret !== undefined && typeof secret !== 'number' && typeof secret !== 'boolean') {
          const token = fromBytes(secret as Uint8Array);
          if (token.length > 0) {
            return token;
          }
        }
      }
    } catch (error) {
      void error;
    }
    return this.loadFallback(endpoint);
  }

  async clear(endpoint: string): Promise<void> {
    const attributes: asset.AssetMap = new Map<asset.Tag, asset.Value>();
    attributes.set(asset.Tag.ALIAS, toBytes(this.aliasFor(endpoint)));
    try {
      await asset.remove(attributes);
    } catch (error) {
      void error;
    }
    const store = this.fallback;
    if (store !== undefined) {
      await store.delete(`${PREF_KEY_PREFIX}${endpoint}`);
      await store.flush();
    }
  }

  private async saveFallback(endpoint: string, token: string): Promise<void> {
    const store = this.fallback;
    if (store === undefined) {
      throw new Error('无法安全保存设备 token：ASSET 与 Preferences 均不可用');
    }
    await store.put(`${PREF_KEY_PREFIX}${endpoint}`, token);
    await store.flush();
  }

  private async loadFallback(endpoint: string): Promise<string> {
    const store = this.fallback;
    if (store === undefined) {
      return '';
    }
    const value = await store.get(`${PREF_KEY_PREFIX}${endpoint}`, '');
    return typeof value === 'string' ? value : '';
  }
}
