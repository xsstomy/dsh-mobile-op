/**
 * Saved connection endpoints (pure logic, unit tested).
 *
 * One paired device token works on every listener of the same gateway
 * (PROTOCOL.md §1: the LAN listener and the public reverse proxy share one
 * device registry), so the client keeps ONE credential and a LIST of addresses
 * for it. This module owns the record model, the address classification and the
 * "which address should I use right now" decision so the store and the gateway
 * adapter stay thin and the rules are testable without any system API.
 */
import { isWebSocketUrl } from '../protocol/PairingPayload';

/** Where an address can be reached from. */
export type EndpointKind = 'public' | 'lan' | 'local';

/** One address the user has connected through. */
export interface SavedEndpoint {
  url: string;
  kind: EndpointKind;
  addedAt: number;
  lastUsedAt: number;
}

/**
 * What the phone's current network looks like. Produced by the NetworkKit
 * adapter; plain data so the selection rule below stays pure.
 */
export interface NetworkHint {
  /** A default network with INTERNET capability exists. */
  available: boolean;
  /** Default network is Wi-Fi or Ethernet (i.e. it can carry a private source). */
  privateCapable: boolean;
  /** The phone's own private IPv4 on the default network ('' when none). */
  privateIpv4: string;
  /** Prefix length of that IPv4 (24 for a /24). */
  prefixLength: number;
}

export const DEFAULT_LAN_PORT = 3081;
export const DEFAULT_WS_PATH = '/ws/mobile';

export function emptyNetworkHint(): NetworkHint {
  return { available: false, privateCapable: false, privateIpv4: '', prefixLength: 0 };
}

/** Authority host of a ws/wss URL, without brackets and without the port. */
export function hostOf(url: string): string {
  const lower = url.toLowerCase();
  let rest = '';
  if (lower.startsWith('ws://')) {
    rest = url.substring(5);
  } else if (lower.startsWith('wss://')) {
    rest = url.substring(6);
  } else {
    return '';
  }
  const authorityEnd = rest.search(/[/?#]/);
  const authority = authorityEnd >= 0 ? rest.substring(0, authorityEnd) : rest;
  if (authority.length === 0) {
    return '';
  }
  if (authority.startsWith('[')) {
    // IPv6 literal: keep everything inside the brackets.
    const close = authority.indexOf(']');
    return close >= 0 ? authority.substring(1, close) : '';
  }
  const colon = authority.lastIndexOf(':');
  return colon >= 0 ? authority.substring(0, colon) : authority;
}

export function isIpv4(host: string): boolean {
  const parts = host.split('.');
  if (parts.length !== 4) {
    return false;
  }
  for (const part of parts) {
    if (part.length === 0 || part.length > 3) {
      return false;
    }
    for (let index = 0; index < part.length; index += 1) {
      const code = part.charCodeAt(index);
      if (code < 0x30 || code > 0x39) {
        return false;
      }
    }
    const value = Number(part);
    if (value < 0 || value > 255) {
      return false;
    }
  }
  return true;
}

/**
 * RFC1918 + link-local, matching the gateway's own isPrivateNetworkHostname
 * (lib/index.mjs): 10/8, 172.16/12, 192.168/16, 169.254/16.
 */
export function isPrivateIpv4(host: string): boolean {
  if (!isIpv4(host)) {
    return false;
  }
  const octets = host.split('.').map((part: string) => Number(part));
  if (octets[0] === 10) {
    return true;
  }
  if (octets[0] === 172 && octets[1] >= 16 && octets[1] <= 31) {
    return true;
  }
  if (octets[0] === 192 && octets[1] === 168) {
    return true;
  }
  return octets[0] === 169 && octets[1] === 254;
}

export function isLoopbackHost(host: string): boolean {
  const lower = host.toLowerCase();
  if (lower === 'localhost' || lower === '::1') {
    return true;
  }
  return lower.startsWith('127.');
}

export function classifyEndpoint(url: string): EndpointKind {
  const host = hostOf(url);
  if (isLoopbackHost(host)) {
    return 'local';
  }
  if (isPrivateIpv4(host)) {
    return 'lan';
  }
  return 'public';
}

export function endpointKindLabel(kind: EndpointKind): string {
  if (kind === 'lan') {
    return '局域网';
  }
  if (kind === 'local') {
    return '本机';
  }
  return '公网';
}

function ipv4ToInt(host: string): number {
  const parts = host.split('.');
  if (parts.length !== 4) {
    return -1;
  }
  let value = 0;
  for (const part of parts) {
    const octet = Number(part);
    if (octet < 0 || octet > 255) {
      return -1;
    }
    value = value * 256 + octet;
  }
  return value >>> 0;
}

/** True when `other` sits in the same IPv4 subnet as `host`/`prefixLength`. */
export function isSameSubnet(host: string, prefixLength: number, other: string): boolean {
  if (!isIpv4(host) || !isIpv4(other) || prefixLength < 0 || prefixLength > 32) {
    return false;
  }
  const mask = prefixLength === 0 ? 0 : (0xffffffff << (32 - prefixLength)) >>> 0;
  const left = ipv4ToInt(host);
  const right = ipv4ToInt(other);
  if (left < 0 || right < 0) {
    return false;
  }
  return ((left & mask) >>> 0) === ((right & mask) >>> 0);
}

function numberField(record: Record<string, Object>, key: string): number {
  const value = record[key];
  return typeof value === 'number' && value >= 0 ? value : 0;
}

/** Parse the persisted JSON; malformed rows are dropped, never fatal. */
export function parseSavedEndpoints(raw: string): SavedEndpoint[] {
  if (raw.length === 0) {
    return [];
  }
  let parsed: Object;
  try {
    parsed = JSON.parse(raw) as Object;
  } catch (error) {
    void error;
    return [];
  }
  if (!Array.isArray(parsed)) {
    return [];
  }
  const result: SavedEndpoint[] = [];
  const list = parsed as Object[];
  for (const entry of list) {
    if (entry === null || typeof entry !== 'object' || Array.isArray(entry)) {
      continue;
    }
    const record = entry as Record<string, Object>;
    const rawUrl = record['url'];
    const url = typeof rawUrl === 'string' ? rawUrl.replace(/^\s+|\s+$/g, '') : '';
    if (url.length === 0 || !isWebSocketUrl(url)) {
      continue;
    }
    // The kind is always derived from the address, never trusted from disk: a
    // record written by an older build cannot keep calling a public host 局域网.
    result.push({
      url,
      kind: classifyEndpoint(url),
      addedAt: numberField(record, 'addedAt'),
      lastUsedAt: numberField(record, 'lastUsedAt')
    });
  }
  return result;
}

export function serializeSavedEndpoints(list: SavedEndpoint[]): string {
  return JSON.stringify(list);
}

/** Newest first, at most `limit` rows. */
function sortByRecency(list: SavedEndpoint[], limit: number): SavedEndpoint[] {
  const copy: SavedEndpoint[] = [];
  for (const item of list) {
    copy.push(item);
  }
  copy.sort((left: SavedEndpoint, right: SavedEndpoint) => right.lastUsedAt - left.lastUsedAt);
  return copy.length > limit ? copy.slice(0, limit) : copy;
}

/**
 * Add or refresh an address. The same URL is never stored twice; a new entry
 * goes to the front and the list is capped so Preferences cannot grow forever.
 */
export function upsertSavedEndpoint(list: SavedEndpoint[], url: string, now: number, limit: number): SavedEndpoint[] {
  const trimmed = url.replace(/^\s+|\s+$/g, '');
  if (trimmed.length === 0 || !isWebSocketUrl(trimmed)) {
    return list;
  }
  const kind = classifyEndpoint(trimmed);
  const next: SavedEndpoint[] = [];
  let previous: SavedEndpoint | undefined = undefined;
  for (const item of list) {
    if (item.url === trimmed) {
      previous = item;
    } else {
      next.push(item);
    }
  }
  const addedAt = previous === undefined ? now : previous.addedAt;
  next.unshift({ url: trimmed, kind, addedAt, lastUsedAt: now });
  return sortByRecency(next, limit);
}

export function removeSavedEndpoint(list: SavedEndpoint[], url: string): SavedEndpoint[] {
  const next: SavedEndpoint[] = [];
  for (const item of list) {
    if (item.url !== url) {
      next.push(item);
    }
  }
  return next;
}

export function markEndpointUsed(list: SavedEndpoint[], url: string, now: number, limit: number): SavedEndpoint[] {
  return upsertSavedEndpoint(list, url, now, limit);
}

/**
 * The address to try first for the current network:
 *  - on a private-capable network with a private source IP, a LAN address in
 *    the same subnet wins (that is what makes the LAN listener accept us);
 *  - otherwise the most recently used public address;
 *  - and if there is nothing but LAN records, the most recent of those.
 * Returns '' when there is nothing to choose.
 */
export function preferredEndpoint(list: SavedEndpoint[], hint: NetworkHint): string {
  if (list.length === 0) {
    return '';
  }
  if (hint.available && hint.privateCapable && hint.privateIpv4.length > 0) {
    let best = '';
    let bestAt = -1;
    for (const item of list) {
      if (item.kind !== 'lan') {
        continue;
      }
      if (!isSameSubnet(hint.privateIpv4, hint.prefixLength, hostOf(item.url))) {
        continue;
      }
      if (item.lastUsedAt > bestAt) {
        bestAt = item.lastUsedAt;
        best = item.url;
      }
    }
    if (best.length > 0) {
      return best;
    }
  }
  let publicBest = '';
  let publicAt = -1;
  let anyBest = '';
  let anyAt = -1;
  for (const item of list) {
    if (item.lastUsedAt > anyAt) {
      anyAt = item.lastUsedAt;
      anyBest = item.url;
    }
    if (item.kind === 'public' && item.lastUsedAt > publicAt) {
      publicAt = item.lastUsedAt;
      publicBest = item.url;
    }
  }
  return publicBest.length > 0 ? publicBest : anyBest;
}

/**
 * Probe addresses for the LAN discovery scan. The gateway's LAN listener only
 * accepts private-network clients, so this is only meaningful from a Wi-Fi or
 * Ethernet address. The subnet is always enumerated as its /24 so a wide prefix
 * (a /16 office network) cannot turn into a 65k-host scan.
 */
export function subnetProbeHosts(selfIp: string, prefixLength: number, limit: number): string[] {
  void prefixLength;
  if (!isIpv4(selfIp)) {
    return [];
  }
  const octets = selfIp.split('.');
  const base = `${octets[0]}.${octets[1]}.${octets[2]}`;
  const result: string[] = [];
  for (let host = 1; host <= 254 && result.length < limit; host += 1) {
    const candidate = `${base}.${host}`;
    if (candidate !== selfIp) {
      result.push(candidate);
    }
  }
  return result;
}

/** The default LAN WebSocket URL for a discovered host. */
export function lanUrlFor(host: string): string {
  return `ws://${host}:${DEFAULT_LAN_PORT}${DEFAULT_WS_PATH}`;
}

/**
 * Turn what the user typed into a WebSocket URL. Accepts a full ws/wss URL or a
 * bare host / host:port ("192.168.1.5"), which fills in the LAN defaults
 * (ws://<host>:3081/ws/mobile). Returns '' when it cannot form a valid URL.
 */
export function normalizeEndpointInput(text: string): string {
  const trimmed = text.replace(/^\s+|\s+$/g, '');
  if (trimmed.length === 0) {
    return '';
  }
  const lower = trimmed.toLowerCase();
  if (lower.startsWith('ws://') || lower.startsWith('wss://')) {
    return isWebSocketUrl(trimmed) ? trimmed : '';
  }
  const withoutSlash = trimmed.replace(/\/+$/, '');
  const pathIndex = withoutSlash.indexOf('/');
  const authority = pathIndex >= 0 ? withoutSlash.substring(0, pathIndex) : withoutSlash;
  if (authority.length === 0) {
    return '';
  }
  const path = pathIndex >= 0 ? withoutSlash.substring(pathIndex) : '';
  const hasPort = authority.startsWith('[') ? authority.indexOf(']:') >= 0 : authority.indexOf(':') >= 0;
  const candidate = 'ws://' + authority + (hasPort ? '' : ':' + DEFAULT_LAN_PORT) +
    (path.length > 0 ? path : DEFAULT_WS_PATH);
  return isWebSocketUrl(candidate) ? candidate : '';
}
