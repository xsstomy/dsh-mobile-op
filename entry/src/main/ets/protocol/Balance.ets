/**
 * DeepSeek official balance decoding and route gating (pure logic, unit tested).
 *
 * The client queries `GET https://api.deepseek.com/user/balance` directly with a
 * user-supplied API key. Only the official open-platform route exposes a
 * balance, so the composer line is gated on the session running on it — other
 * providers (e.g. an OpenCode route) serve DeepSeek models but have no balance
 * API.
 */
import { ModelGroupRow } from './Settings';

export interface BalanceInfoRow {
  currency: string;
  totalBalance: string;
  grantedBalance: string;
  toppedUpBalance: string;
}

export interface BalanceSnapshot {
  isAvailable: boolean;
  infos: BalanceInfoRow[];
}

function stringField(record: Record<string, Object>, key: string): string {
  const value = record[key];
  return typeof value === 'string' ? value : '';
}

/** Null when the body is not the expected JSON object (HTTP error page, HTML...). */
export function parseBalanceSnapshot(body: string): BalanceSnapshot | null {
  let value: Object;
  try {
    value = JSON.parse(body) as Object;
  } catch (error) {
    void error;
    return null;
  }
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    return null;
  }
  const record = value as Record<string, Object>;
  const infos: BalanceInfoRow[] = [];
  const rawInfos = record['balance_infos'];
  if (Array.isArray(rawInfos)) {
    const list = rawInfos as Object[];
    for (let index = 0; index < list.length; index += 1) {
      const item = list[index];
      if (item === null || typeof item !== 'object' || Array.isArray(item)) {
        continue;
      }
      const info = item as Record<string, Object>;
      infos.push({
        currency: stringField(info, 'currency'),
        totalBalance: stringField(info, 'total_balance'),
        grantedBalance: stringField(info, 'granted_balance'),
        toppedUpBalance: stringField(info, 'topped_up_balance')
      });
    }
  }
  const availability = record['is_available'];
  const isAvailable = typeof availability === 'boolean' ? availability : false;
  return { isAvailable: isAvailable, infos: infos };
}

export function currencySymbol(currency: string): string {
  const upper = currency.toUpperCase();
  if (upper === 'CNY') {
    return '¥';
  }
  if (upper === 'USD') {
    return '$';
  }
  return `${upper} `;
}

/** The first balance entry formatted for the composer, or '' when unusable. */
export function formatBalance(snapshot: BalanceSnapshot | null): string {
  if (snapshot === null || !snapshot.isAvailable || snapshot.infos.length === 0) {
    return '';
  }
  const info = snapshot.infos[0];
  if (info.totalBalance.length === 0) {
    return '';
  }
  return `${currencySymbol(info.currency)}${info.totalBalance}`;
}

/** True when the session's route is the official DeepSeek provider. */
export function isOfficialDeepSeekRoute(provider: string, groups: ModelGroupRow[]): boolean {
  const id = provider.trim().toLowerCase();
  if (id === 'deepseek-official' || id === 'deepseek') {
    return true;
  }
  for (let index = 0; index < groups.length; index += 1) {
    const group = groups[index];
    if (group.id.trim().toLowerCase() === id) {
      return group.name.trim().toLowerCase() === 'deepseek';
    }
  }
  return false;
}
