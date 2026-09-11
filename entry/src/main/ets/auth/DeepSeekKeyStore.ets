/**
 * DeepSeek open-platform API key storage.
 *
 * Same policy as the gateway device token: Asset Store Kit first (system key
 * management, never plain text on disk), preferences only as a last-resort
 * fallback so the balance line keeps working where ASSET is unavailable.
 */
import { asset } from '@kit.AssetStoreKit';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'DeepSeekKeyStore';
const PREF_STORE = 'dsh_mobile_prefs';
const PREF_KEY = 'deepseek:apiKey';
const ASSET_ALIAS = 'dsh-mobile:deepseek-api-key';

function toBytes(value: string): Uint8Array {
  return new util.TextEncoder().encodeInto(value);
}

function fromBytes(value: Uint8Array): string {
  return util.TextDecoder.create('utf-8').decodeToString(value);
}

export class DeepSeekKeyStore {
  private fallback: preferences.Preferences | undefined;

  async attach(context: common.Context): Promise<void> {
    try {
      this.fallback = await preferences.getPreferences(context, PREF_STORE);
    } catch (error) {
      hilog.warn(0x0000, TAG, 'preferences unavailable: %{public}s', JSON.stringify(error));
    }
  }

  async save(secret: string): Promise<void> {
    const attributes: asset.AssetMap = new Map<asset.Tag, asset.Value>();
    attributes.set(asset.Tag.ALIAS, toBytes(ASSET_ALIAS));
    attributes.set(asset.Tag.SECRET, toBytes(secret));
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
    const store = this.fallback;
    if (store === undefined) {
      throw new Error('无法安全保存 API Key：ASSET 与 Preferences 均不可用');
    }
    await store.put(PREF_KEY, secret);
    await store.flush();
  }

  async load(): Promise<string> {
    const query: asset.AssetMap = new Map<asset.Tag, asset.Value>();
    query.set(asset.Tag.ALIAS, toBytes(ASSET_ALIAS));
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    try {
      const results: asset.AssetMap[] = await asset.query(query);
      if (results.length > 0) {
        const secret = results[0].get(asset.Tag.SECRET);
        if (secret !== undefined && typeof secret !== 'number' && typeof secret !== 'boolean') {
          const value = fromBytes(secret as Uint8Array);
          if (value.length > 0) {
            return value;
          }
        }
      }
    } catch (error) {
      void error;
    }
    const store = this.fallback;
    if (store === undefined) {
      return '';
    }
    const fallback = await store.get(PREF_KEY, '');
    return typeof fallback === 'string' ? fallback : '';
  }

  async clear(): Promise<void> {
    const attributes: asset.AssetMap = new Map<asset.Tag, asset.Value>();
    attributes.set(asset.Tag.ALIAS, toBytes(ASSET_ALIAS));
    try {
      await asset.remove(attributes);
    } catch (error) {
      void error;
    }
    const store = this.fallback;
    if (store !== undefined) {
      await store.delete(PREF_KEY);
      await store.flush();
    }
  }
}
