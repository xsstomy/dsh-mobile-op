# DshMobile (HarmonyOS)

> 简体中文: [README.md](README.md)

A **native HarmonyOS client** (ArkTS + ArkUI, Stage model) for DeepSeek Harness, speaking the
`dsh-mobile-v1` protocol (`hello.protocol = 3`) over the third-party gateway
[`dsh-plugin-mobile-gateway`](https://github.com/Clarklevis1995/dsh-plugin-mobile-gateway).

- Protocol contract: [`docs/PROTOCOL.md`](docs/PROTOCOL.md) (upstream v0.7.2, verbatim copy)
- Upstream sibling clients (iOS / Android, KMP): [`Clarklevis1995/dsh-mobile`](https://github.com/Clarklevis1995/dsh-mobile)
- This repository is an independent HarmonyOS implementation; no upstream source is copied.
  See [`NOTICE`](NOTICE).

## Screenshots

| Home | Conversation | Settings |
|---|---|---|
| ![Home](docs/screenshots/home.jpg) | ![Conversation](docs/screenshots/conversation.jpg) | ![Settings](docs/screenshots/settings.jpg) |

## Requirements

| Item | Version (tested) |
|---|---|
| DevEco Studio | 26.0.0.821 |
| HarmonyOS SDK | API 26 (`/Applications/DevEco-Studio.app/Contents/sdk`) |
| Target | `targetSdkVersion 6.1.1(24)` / `compatibleSdkVersion 5.0.0(12)` |
| CLI | `devecocli` 1.3.0-stable (gateway side needs v0.7.2+) |

## Build & run

```bash
devecocli device list                            # start an emulator or connect a device first
devecocli emulator start "Pura 90"
devecocli signature generate --product default   # first time only (device connected + devecocli auth login)
devecocli build --build-mode debug
devecocli run --device 127.0.0.1:5555
devecocli check lint
```

Unit tests (`devecocli` has no `test` subcommand; use DevEco's bundled hvigor and run it from the
project root):

```bash
node /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw.js test
```

## Signing & distribution

This repository ships **no signing material** (`signingConfigs` has been removed from
`build-profile.json5`). Configure signing locally before the first build:

```bash
devecocli signature generate --product default   # device connected + devecocli auth login
# or in DevEco Studio: Project Structure -> Signing Configs -> auto sign
```

For local / specified-device installs (no AppGallery release), use a **debug certificate + debug
Profile**:

- `hdc install` only accepts **debug-signed** packages. A release package signed with an AGC
  **release certificate** fails locally with `INSTALL_FAILED_APP_SOURCE_NOT_TRUSTED`.
- A debug Profile is **device-bound**: to install on someone else's phone you must add that
  device's **UDID** to your debug Profile, sign manually, and hand them the HAP to `hdc install`
  (or install it via DevEco Testing).
- Quotas: at most 3 debug certificates per account; at most 100 Profiles per app.

> The least-friction option is to **distribute source only**, and let each user sign with their
> own Huawei account.

## Gateway setup (host side)

```bash
# enable the mobile gateway (the WebUI "Mobile devices" panel works too)
curl -s -X POST http://127.0.0.1:3080/mgw/gateway -H 'content-type: application/json' -d '{"enabled":true}'
# issue a one-time pairing code: Base64URL in qrPayload; payload is a JSON object; 5-min TTL, single use
curl -s -X POST http://127.0.0.1:3080/mgw/pair -H 'content-type: application/json' \
  -d '{"name":"harmony","publicUrl":"ws://10.0.2.2:3081/ws/mobile"}'
```

From the emulator the host is always at `10.0.2.2` (QEMU slirp) — **do not use `127.0.0.1`**.

## Access outside the LAN (public / remote)

Using the client outside the local network **requires no client changes**: the pairing payload's
`publicUrl` only has to be a reachable `wss://` URL (`protocol/PairingPayload.ets` validates the
scheme and authority only). Generate the QR code in the WebUI, pair with the client, and the token is
persisted per endpoint — a stable address means no re-pairing.

The recommended option is a **named Cloudflare Tunnel**: if your domain is hosted on Cloudflare it
gives you a stable `wss://<subdomain>/ws/mobile` with no VPN client on the phone and no public IP or
router port-forwarding.

### 1. Install and log in to cloudflared (on the machine running `dsh web`)

```bash
brew install cloudflared
cloudflared tunnel login        # pick the zone that owns your domain in the browser
```

### 2. Create the tunnel

```bash
cloudflared tunnel create dsh-mobile     # note the <TUNNEL-UUID> it prints
```

### 3. Write `~/.cloudflared/config.yml`

```yaml
tunnel: <TUNNEL-UUID>
credentials-file: /Users/<your-user>/.cloudflared/<TUNNEL-UUID>.json

ingress:
  - hostname: dsh.example.com          # replace with your own subdomain
    service: http://127.0.0.1:3081     # the plugin's LAN listener; WebSocket upgrades automatically
  - service: http_status:404
```

### 4. Route DNS and verify in the foreground

```bash
cloudflared tunnel route dns dsh-mobile dsh.example.com
cloudflared tunnel run dsh-mobile
```

### 5. Install as a service (prefer no sudo so it reads `~/.cloudflared/`)

```bash
cloudflared service install
```

> Known pitfall: with some versions the launch agent created by `cloudflared service install` only
> runs the bare binary without the `tunnel run` subcommand and exits immediately. If
> `launchctl list | grep cloudflare` shows no running process and the log keeps repeating
> `use 'cloudflared tunnel run'`, edit `ProgramArguments` in
> `~/Library/LaunchAgents/com.cloudflare.cloudflared.plist` to pass
> `tunnel --config <config path> --no-autoupdate run` explicitly, then reload with
> `launchctl bootout` + `launchctl bootstrap`.

### 6. WebUI and phone pairing

- Keep "Allow mobile devices" and **Device authentication** enabled.
- Set "WebSocket address" to `wss://dsh.example.com/ws/mobile`, then generate the pairing QR code.
- Pair with the phone using this client; a stable address stays valid long-term.
- The "Public access / system Helper" block targets a **Linux server with a fixed public IPv4**
  (Nginx + Certbot); with a home macOS/Windows tunnel you do **not** run its `init`.

### Notes

- **Do not put Cloudflare Access in front of this hostname**: a WebSocket client cannot complete an
  interactive login and would be blocked. Security comes from the gateway's **device authentication**;
  add a WAF rate limit if you want more.
- Cloudflare dashboard: keep Network → WebSockets on; set the SSL/TLS mode to Full.
- Large frames: Cloudflare passes proxied WebSocket traffic through, so the 1 MiB Workers limit does
  not apply; still send an image once to confirm (the client frame budget is 3.5 MB).
- Always-on prerequisites: the machine must stay awake and `dsh web` must keep running; if
  `dsh web` stops, the tunnel returns 502.
- The gateway README also documents Tailscale Serve and Cloudflare Quick Tunnel; note that HarmonyOS
  NEXT has no official Tailscale client, so the named tunnel above is the long-term recommendation.

## Protocol probe

`tools/probe.mjs` is a Node reference client (it runs the same requests as the ArkTS client and
compares `requestId` correlation and `seq` de-duplication frame by frame):

```bash
cd tools && ln -sfn ~/.dsh/profiles/web/node_modules/ws node_modules/ws
node probe.mjs pair --url ws://127.0.0.1:3080/ws/mobile --code <pairingCode>
node probe.mjs run  --url ws://127.0.0.1:3080/ws/mobile
```

## UI design

The interface follows the upstream client's design language (`dsh-mobile`'s
`Design/design-spec.md`, `DshTheme.kt`, `DshLiquidGlass.kt` and screenshots): deep navy gradient
plus a technical dot grid, sparingly used frosted glass, an ocean-blue primary action, and
tabular figures.

- Colours, layout and information architecture follow upstream; the **launcher icon** uses the
  upstream `AppIcon` whale artwork (MIT, see [`NOTICE`](NOTICE)).
- ArkUI counterparts: `common/HarnessBackground.ets` (gradient + dot grid),
  `views/MessageContent.ets` (Markdown subset renderer), `common/Format.ets` (segmenting and
  relative time; pure logic with unit tests).

## Directory layout

```
entry/src/main/ets/
├─ protocol/    protocol DTOs, wire decoding, strict Base64URL pairing payload
├─ gateway/     request lanes / RequestTracker (single receive loop) / dual-channel WebSocket client
├─ auth/        device id, long-lived token storage, preferences
├─ projection/  conversation & trajectory projections
├─ sync/        history pagination + live tail merge
├─ store/       GatewayStore (read-only UI snapshot + intents)
├─ pages/       Pairing / Workspace / Conversation / Settings
└─ views/       reusable UI components
```

## Status

The MVP is verified end-to-end on the emulator (HarmonyOS 6.1.1 / API 24): pairing → dual-channel
connection → workspace/session lists → history + live conversation → send message → new session →
credential persistence and automatic reconnect.

- Stage-0 protocol findings: `docs/spikes/2026-09-10-stage0-protocol-findings.md`
- Unit tests: `entry/src/test/` (170 cases: decoding, strict Base64URL, lanes/timeouts/dedupe,
  history merge, conversation projection, pagination, stats).

## Known constraints

- HarmonyOS NEXT only (API 12+). For HarmonyOS 4.x and below, use the upstream Android APK.
- Client JSON frame budget: 3.5 MB (measured on OHOS: 4 MB passes, 6 MB fails) — see `docs/spikes/`.
- Plain `ws://` needs no network-security configuration (official FAQ `faqs-network-16`).
