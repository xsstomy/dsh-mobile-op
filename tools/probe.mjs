#!/usr/bin/env node
/**
 * dsh-mobile gateway protocol probe (Node reference client).
 *
 * Used as the behavioural baseline for the HarmonyOS (ArkTS) client:
 *  - captures real response frames -> entry/src/test/fixtures/*.ets
 *  - measures request/response round-trips
 *  - exercises pairing, token auth, split channels, close-code classification
 *
 * Usage:
 *   node probe.mjs pair   --url ws://127.0.0.1:3080/ws/mobile --code <pairingCode> [--out dir]
 *   node probe.mjs run    --url ws://127.0.0.1:3080/ws/mobile [--token <t>] [--message]
 */
import WebSocket from 'ws';
import { randomUUID, createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

function parseArgs(argv) {
  const [command, ...rest] = argv;
  const flags = {};
  for (let i = 0; i < rest.length; i += 1) {
    const token = rest[i];
    if (!token.startsWith('--')) continue;
    const key = token.slice(2);
    const next = rest[i + 1];
    if (next === undefined || next.startsWith('--')) flags[key] = true;
    else { flags[key] = next; i += 1; }
  }
  return { command, flags };
}

function outDir(flags) {
  const dir = typeof flags.out === 'string' ? flags.out : '/tmp/dsh-probe';
  fs.mkdirSync(dir, { recursive: true });
  return dir;
}

function deviceId(dir) {
  const file = path.join(dir, 'device-id.txt');
  if (fs.existsSync(file)) return fs.readFileSync(file, 'utf8').trim();
  const value = randomUUID();
  fs.writeFileSync(file, value);
  return value;
}

function tokenFile(dir) {
  return path.join(dir, 'token.txt');
}

function connect({ url, protocols, headers }) {
  const socket = new WebSocket(url, protocols, { headers, handshakeTimeout: 15000 });
  return socket;
}

function waitFor(socket, predicate, { timeoutMs = 15000, label = 'frame' } = {}) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      cleanup();
      reject(new Error(`timeout waiting for ${label}`));
    }, timeoutMs);
    const onMessage = (data) => {
      let frame;
      try { frame = JSON.parse(data.toString()); } catch { return; }
      if (!predicate(frame)) return;
      cleanup();
      resolve(frame);
    };
    const onError = (error) => { cleanup(); reject(error); };
    const onClose = (code, reason) => {
      cleanup();
      reject(new Error(`closed before ${label}: code=${code} reason=${reason.toString()}`));
    };
    function cleanup() {
      clearTimeout(timer);
      socket.off('message', onMessage);
      socket.off('error', onError);
      socket.off('close', onClose);
    }
    socket.on('message', onMessage);
    socket.on('error', onError);
    socket.on('close', onClose);
  });
}

function send(socket, payload) {
  socket.send(JSON.stringify(payload));
}

function normalizeForFixture(frame) {
  // Replace volatile identity fields so fixtures stay stable across runs.
  const clone = JSON.parse(JSON.stringify(frame));
  const replace = (obj, keys, replacement) => {
    if (!obj || typeof obj !== 'object') return;
    for (const key of Object.keys(obj)) {
      if (keys.includes(key) && typeof obj[key] === 'string') obj[key] = replacement;
      else replace(obj[key], keys, replacement);
    }
  };
  replace(clone, ['sessionId', 'requestId', 'rpcId', 'approvalId', 'transferId', 'attachmentId', 'workspaceId', 'id', 'callId', 'commandId'], '<id>');
  replace(clone, ['path', 'cwd', 'title', 'name', 'query', 'text', 'line', 'objective'], '<value>');
  return clone;
}

async function runPair({ flags }) {
  const dir = outDir(flags);
  const id = deviceId(dir);
  const url = flags.url ?? 'ws://127.0.0.1:3080/ws/mobile';
  const code = flags.code;
  if (typeof code !== 'string' || !code) throw new Error('pair requires --code <pairingCode>');
  const headers = { 'X-DSH-Device-ID': id };
  const socket = connect({ url, protocols: ['dsh-mobile-v1', `dsh-pair.${code}`], headers });
  socket.on('error', (error) => console.log('[error]', error.message));
  const paired = await waitFor(socket, (f) => f.kind === 'paired', { label: 'paired', timeoutMs: 15000 });
  fs.writeFileSync(tokenFile(dir), paired.token);
  const hello = await waitFor(socket, (f) => f.kind === 'hello', { label: 'hello', timeoutMs: 15000 });
  console.log(JSON.stringify({ deviceId: id, device: paired.device, hello }, null, 2));
  socket.close();
}

async function runSuite({ flags }) {
  const dir = outDir(flags);
  const id = deviceId(dir);
  const url = flags.url ?? 'ws://127.0.0.1:3080/ws/mobile';
  const token = typeof flags.token === 'string' ? flags.token : fs.readFileSync(tokenFile(dir), 'utf8').trim();
  const headers = { 'X-DSH-Device-ID': id, authorization: `Bearer ${token}` };
  const frames = [];
  const timings = [];
  const socket = connect({ url, protocols: ['dsh-mobile-v1'], headers });
  socket.on('message', (data) => {
    try { frames.push(JSON.parse(data.toString())); } catch { /* ignore */ }
  });
  const hello = await waitFor(socket, (f) => f.kind === 'hello', { label: 'hello' });
  console.log('capabilities:', hello.capabilities.join(','));

  const exchange = async (payload, expectKind, label) => {
    const started = Date.now();
    send(socket, payload);
    const frame = await waitFor(socket, (f) => f.kind === expectKind || f.kind === 'error', { label, timeoutMs: 40000 });
    const ms = Date.now() - started;
    timings.push({ request: payload.type, kind: frame.kind, ms });
    console.log(`  ${label}: kind=${frame.kind} ${ms}ms${frame.code ? ` code=${frame.code}` : ''}`);
    return frame;
  };

  const workspaces = await exchange({ type: 'workspaces' }, 'workspaces', 'workspaces');
  const sessions = await exchange({ type: 'sessions' }, 'sessions', 'sessions');
  console.log(`  workspaces=${(workspaces.workspaces ?? []).length} sessions=${(sessions.items ?? sessions.sessions ?? []).length}`);

  const requestId = randomUUID();
  const created = await exchange({ type: 'session-create', requestId }, 'session-created', 'session-create');
  const sessionId = created.sessionId;
  console.log(`  created ${sessionId} in ${timings[timings.length - 1].ms}ms`);

  await exchange({ type: 'subscribe', sessionId }, 'subscribed', 'subscribe');
  await exchange({ type: 'history', sessionId, maxMessages: 20, view: 'conversation' }, 'history', 'history');

  if (flags.message) {
    await exchange({ type: 'message', sessionId, text: '只回复 ok，不要调用任何工具。', mode: 'queue', clientTimeZone: 'Asia/Shanghai' }, 'sent', 'message');
    // Wait for the turn to finish so the fixtures contain a complete event sequence.
    await new Promise((resolve) => {
      const timer = setTimeout(resolve, 90000);
      const onMessage = (data) => {
        let frame;
        try { frame = JSON.parse(data.toString()); } catch { return; }
        if (frame.kind === 'event' && frame.event?.type === 'turn/end') {
          clearTimeout(timer);
          socket.off('message', onMessage);
          resolve();
        }
      };
      socket.on('message', onMessage);
    });
  }

  await exchange({ type: 'session-archive', sessionId }, 'session-archived', 'session-archive');

  // Split-channel validation.
  let split = { control: null, conversation: null };
  if (hello.capabilities.includes('split-channels')) {
    const control = connect({ url, protocols: ['dsh-mobile-v1'], headers: { ...headers, 'X-DSH-Channel': 'control' } });
    const conversation = connect({ url, protocols: ['dsh-mobile-v1'], headers: { ...headers, 'X-DSH-Channel': 'conversation' } });
    const controlHello = await waitFor(control, (f) => f.kind === 'hello', { label: 'control hello' });
    const conversationHello = await waitFor(conversation, (f) => f.kind === 'hello', { label: 'conversation hello' });
    split = { control: controlHello.capabilities.length, conversation: conversationHello.capabilities.length };
    control.close();
    conversation.close();
  }

  const summary = {
    url,
    capabilities: hello.capabilities,
    timings,
    frameKinds: [...new Set(frames.map((f) => f.kind))],
  };
  const dump = {
    capturedAt: new Date().toISOString(),
    source: { url, protocol: hello.protocol, capabilities: hello.capabilities },
    frames: frames.map(normalizeForFixture),
  };
  fs.writeFileSync(path.join(dir, 'frames.json'), JSON.stringify(dump, null, 2));
  fs.writeFileSync(path.join(dir, 'summary.json'), JSON.stringify(summary, null, 2));
  console.log(JSON.stringify(summary, null, 2));
  socket.close();
}

async function main() {
  const { command, flags } = parseArgs(process.argv.slice(2));
  if (command === 'pair') return runPair({ flags });
  if (command === 'run') return runSuite({ flags });
  console.error('usage: node probe.mjs pair --url <ws-url> --code <pairingCode> | run --url <ws-url> [--token <t>] [--message]');
  process.exit(2);
}

main().catch((error) => {
  console.error('[probe] failed:', error.message);
  process.exit(1);
});
