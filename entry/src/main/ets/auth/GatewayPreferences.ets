/**
 * Non-sensitive local preferences (endpoint, stable installation id, last
 * selection). The long-lived device token never goes here — see TokenStore.
 */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';

const STORE_NAME = 'dsh_mobile_prefs';

const KEY_ENDPOINT = 'endpoint';
const KEY_DEVICE_ID = 'deviceId';
const KEY_WORKSPACE_ID = 'workspaceId';
const KEY_LAST_SESSION = 'lastSessionId';
const KEY_RECENT_ENDPOINTS = 'recentEndpoints';
const KEY_ENDPOINT_RECORDS = 'endpointRecords';
const KEY_AUTO_SWITCH = 'autoSwitch';
const KEY_THEME_MODE = 'themeMode';
const KEY_SHOW_REASONING = 'showReasoning';
const KEY_SHOW_SLASH_SHORTCUT = 'showSlashShortcut';
const KEY_SHOW_MENTION_SHORTCUT = 'showMentionShortcut';

export class GatewayPreferences {
  private static instance: GatewayPreferences | undefined;
  private store: preferences.Preferences | undefined;
  private deviceIdCache: string = '';

  static async open(context: common.Context): Promise<GatewayPreferences> {
    if (GatewayPreferences.instance !== undefined && GatewayPreferences.instance.store !== undefined) {
      return GatewayPreferences.instance;
    }
    const instance = new GatewayPreferences();
    instance.store = await preferences.getPreferences(context, STORE_NAME);
    GatewayPreferences.instance = instance;
    return instance;
  }

  static get current(): GatewayPreferences | undefined {
    return GatewayPreferences.instance;
  }

  private async getString(key: string, fallback: string): Promise<string> {
    const store = this.store;
    if (store === undefined) {
      return fallback;
    }
    const value = await store.get(key, fallback);
    return typeof value === 'string' ? value : fallback;
  }

  private async put(key: string, value: string): Promise<void> {
    const store = this.store;
    if (store === undefined) {
      return;
    }
    await store.put(key, value);
    await store.flush();
  }

  async endpoint(): Promise<string> {
    return this.getString(KEY_ENDPOINT, '');
  }

  async setEndpoint(value: string): Promise<void> {
    await this.put(KEY_ENDPOINT, value);
    const recent = await this.recentEndpoints();
    const filtered: string[] = [];
    for (const item of recent) {
      if (item !== value) {
        filtered.push(item);
      }
    }
    filtered.unshift(value);
    await this.put(KEY_RECENT_ENDPOINTS, filtered.slice(0, 5).join('\n'));
  }

  async recentEndpoints(): Promise<string[]> {
    const raw = await this.getString(KEY_RECENT_ENDPOINTS, '');
    if (raw.length === 0) {
      return [];
    }
    const result: string[] = [];
    for (const item of raw.split('\n')) {
      const trimmed = item.replace(/^\s+|\s+$/g, '');
      if (trimmed.length > 0) {
        result.push(trimmed);
      }
    }
    return result;
  }

  /**
   * Every address the device has connected through, serialized by
   * sync/Endpoints. Kept next to the active endpoint so a manual or automatic
   * switch can offer the same credential on a different listener.
   */
  async endpointRecordsRaw(): Promise<string> {
    return this.getString(KEY_ENDPOINT_RECORDS, '');
  }

  async setEndpointRecordsRaw(value: string): Promise<void> {
    await this.put(KEY_ENDPOINT_RECORDS, value);
  }

  /**
   * Whether the client may pick a better address on its own. Defaults to ON:
   * the whole point is to prefer the LAN at home without a manual tap.
   */
  async autoSwitch(): Promise<boolean> {
    return (await this.getString(KEY_AUTO_SWITCH, '1')) === '1';
  }

  async setAutoSwitch(value: boolean): Promise<void> {
    await this.put(KEY_AUTO_SWITCH, value ? '1' : '0');
  }

  /** Stable installation id: reused for re-pairing so the gateway keeps one device row. */
  async deviceId(): Promise<string> {
    if (this.deviceIdCache.length > 0) {
      return this.deviceIdCache;
    }
    const existing = await this.getString(KEY_DEVICE_ID, '');
    if (existing.length > 0) {
      this.deviceIdCache = existing;
      return existing;
    }
    const created = util.generateRandomUUID(false);
    this.deviceIdCache = created;
    await this.put(KEY_DEVICE_ID, created);
    return created;
  }

  async workspaceId(): Promise<string> {
    return this.getString(KEY_WORKSPACE_ID, '');
  }

  async setWorkspaceId(value: string): Promise<void> {
    await this.put(KEY_WORKSPACE_ID, value);
  }

  async themeMode(): Promise<string> {
    return this.getString(KEY_THEME_MODE, 'system');
  }

  async setThemeMode(value: string): Promise<void> {
    await this.put(KEY_THEME_MODE, value);
  }

  /**
   * Whether the conversation renders the agent's reasoning content. Stored as
   * `'1'`/`'0'`; anything else (missing key included) means "off" — the default
   * is to keep thinking hidden and show only the 「深度求索中」 indicator.
   */
  async showReasoning(): Promise<boolean> {
    return (await this.getString(KEY_SHOW_REASONING, '0')) === '1';
  }

  async setShowReasoning(value: boolean): Promise<void> {
    await this.put(KEY_SHOW_REASONING, value ? '1' : '0');
  }

  /**
   * Whether the composer shows its quick-insert buttons. Both default OFF: the
   * composer stays uncluttered until the user opts in from the gear panel.
   */
  async showSlashShortcut(): Promise<boolean> {
    return (await this.getString(KEY_SHOW_SLASH_SHORTCUT, '0')) === '1';
  }

  async setShowSlashShortcut(value: boolean): Promise<void> {
    await this.put(KEY_SHOW_SLASH_SHORTCUT, value ? '1' : '0');
  }

  async showMentionShortcut(): Promise<boolean> {
    return (await this.getString(KEY_SHOW_MENTION_SHORTCUT, '0')) === '1';
  }

  async setShowMentionShortcut(value: boolean): Promise<void> {
    await this.put(KEY_SHOW_MENTION_SHORTCUT, value ? '1' : '0');
  }

  async lastSessionId(): Promise<string> {
    return this.getString(KEY_LAST_SESSION, '');
  }

  async setLastSessionId(value: string): Promise<void> {
    await this.put(KEY_LAST_SESSION, value);
  }
}
