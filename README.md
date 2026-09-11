# DshMobile (HarmonyOS)

> English version: [README_EN.md](README_EN.md)

DeepSeek Harness 的 **HarmonyOS 原生客户端**（ArkTS + ArkUI，Stage 模型），通过第三方网关
[`dsh-plugin-mobile-gateway`](https://github.com/Clarklevis1995/dsh-plugin-mobile-gateway) 的
`dsh-mobile-v1` 协议（`hello.protocol = 3`）连接本机/自建的 DeepSeek Harness。

- 协议契约：[`docs/PROTOCOL.md`](docs/PROTOCOL.md)（上游 v0.7.2 原样收录）
- 上游同类客户端（iOS / Android，KMP）：[`Clarklevis1995/dsh-mobile`](https://github.com/Clarklevis1995/dsh-mobile)
- 本仓库是独立的 HarmonyOS 实现，不复用上游源码，署名见 [`NOTICE`](NOTICE)

## 界面

| 首页 | 对话 | 设置 |
|---|---|---|
| ![首页](docs/screenshots/home.jpg) | ![对话](docs/screenshots/conversation.jpg) | ![设置](docs/screenshots/settings.jpg) |

## 环境要求

| 项 | 版本（本机实测） |
|---|---|
| DevEco Studio | 26.0.0.821 |
| HarmonyOS SDK | API 26（`/Applications/DevEco-Studio.app/Contents/sdk`） |
| 目标设备 | `targetSdkVersion 6.1.1(24)` / `compatibleSdkVersion 5.0.0(12)` |
| 命令行工具 | `devecocli` 1.3.0-stable（`dsh` 侧需网关 v0.7.2+） |

## 构建与运行

```bash
devecocli device list                       # 需要先起模拟器或连真机
devecocli emulator start "Pura 90"
devecocli signature generate --product default   # 首次需要（需已连接设备 + devecocli auth login）
devecocli build --build-mode debug
devecocli run --device 127.0.0.1:5555
devecocli check lint
```

单元测试（`devecocli` 没有 `test` 子命令，用 DevEco 自带 hvigor，**必须在工程根目录**执行）：

```bash
node /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw.js test
```

## 签名与分发

仓库**不包含签名材料**（`build-profile.json5` 里的 `signingConfigs` 已移除）。首次构建前先本地配置签名：

```bash
devecocli signature generate --product default   # 需已连接设备 + devecocli auth login
# 或在 DevEco Studio：Project Structure → Signing Configs → 自动签名
```

不上架、只在本机/指定设备安装时，用**调试证书 + 调试 Profile**：

- `hdc install` 只能安装**调试签名**的包；AGC **发布证书**签的 release 包本地安装会报
  `INSTALL_FAILED_APP_SOURCE_NOT_TRUSTED`。
- 调试 Profile **绑定设备**：要给别人的手机装，需把对方设备的 **UDID** 加进调试 Profile 后手动签名，
  再把 HAP 发给他 `hdc install`（或 DevEco Testing 安装）。
- 每个开发者账号最多 3 个调试证书；每个应用最多 100 个 Profile。

> 不想折腾设备白名单，最省事的方式是**只分发源码**，每个人用自己的华为账号签名。

## 本机网关侧的准备

```bash
# 开启移动网关（WebUI「移动设备」也可以）
curl -s -X POST http://127.0.0.1:3080/mgw/gateway -H 'content-type: application/json' -d '{"enabled":true}'
# 生成一次性配对码：Base64URL 在 qrPayload；payload 是 JSON 对象；TTL 5 分钟、一次性
curl -s -X POST http://127.0.0.1:3080/mgw/pair -H 'content-type: application/json' \
  -d '{"name":"harmony","publicUrl":"ws://10.0.2.2:3081/ws/mobile"}'
```

模拟器访问宿主固定用 `10.0.2.2`（QEMU slirp），**不要用 `127.0.0.1`**。

## 非局域网访问（公网 / 远程）

同一局域网之外使用**不需要改客户端**：配对载荷里的 `publicUrl` 只要是一个可达的 `wss://` 地址即可
（`protocol/PairingPayload.ets` 只校验 scheme 与 authority）。在 WebUI 生成二维码后用客户端扫码配对，
token 按 endpoint 持久化，地址稳定就不用重复配对。

推荐 **Cloudflare 命名隧道**：域名已托管在 Cloudflare 时，它能给出长期稳定的
`wss://<子域名>/ws/mobile`，手机端无需安装任何 VPN 客户端，也不需要公网 IP 或路由器端口转发。

### 1. 安装并登录 cloudflared（在运行 `dsh web` 的电脑上）

```bash
brew install cloudflared
cloudflared tunnel login        # 浏览器里选中域名所在的 zone
```

### 2. 创建隧道

```bash
cloudflared tunnel create dsh-mobile     # 记下输出的 <TUNNEL-UUID>
```

### 3. 写 `~/.cloudflared/config.yml`

```yaml
tunnel: <TUNNEL-UUID>
credentials-file: /Users/<你的用户名>/.cloudflared/<TUNNEL-UUID>.json

ingress:
  - hostname: dsh.example.com          # 替换成你自己的子域名
    service: http://127.0.0.1:3081     # 指向插件局域网监听；WebSocket 会自动升级
  - service: http_status:404
```

### 4. 绑定 DNS 并前台验证

```bash
cloudflared tunnel route dns dsh-mobile dsh.example.com
cloudflared tunnel run dsh-mobile
```

### 5. 装成常驻服务（建议不加 sudo，这样它读 `~/.cloudflared/`）

```bash
cloudflared service install
```

> 已知坑：某些版本的 `cloudflared service install` 生成的 launch agent 只写了裸二进制、缺少
> `tunnel run` 子命令，启动即退出。若 `launchctl list | grep cloudflare` 看不到运行中的进程、
> 日志里反复出现 `use 'cloudflared tunnel run'`，就把
> `~/Library/LaunchAgents/com.cloudflare.cloudflared.plist` 的 `ProgramArguments` 改成显式带
> `tunnel --config <config 路径> --no-autoupdate run`，再 `launchctl bootout` + `launchctl bootstrap` 重载。

### 6. WebUI 与手机配对

- 保持「允许移动设备连接」与「**设备鉴权**」开启。
- 「WebSocket 地址」填 `wss://dsh.example.com/ws/mobile`，再「生成配对二维码」。
- 手机用本客户端扫码即可；地址稳定后长期有效。
- 「公网接入 / 系统 Helper」那一块是给**固定公网 IP 的 Linux 服务器**（Nginx + Certbot）用的；
  家用 macOS / Windows 走隧道时**不要**执行它的 `init`。

### 注意事项

- **不要在该子域名前启用 Cloudflare Access**：WebSocket 客户端无法完成交互式登录，会被直接挡死；
  安全由网关的**设备鉴权**负责，需要时另加 WAF 限速。
- Cloudflare 面板：Network → WebSockets 保持开启；SSL/TLS 模式设为 Full。
- 大帧：Cloudflare 对代理型 WebSocket 是透传，Workers 的 1 MiB 限制不适用；仍建议首次发一张图实测
  （客户端单帧预算 3.5 MB）。
- 常驻前提：电脑保持不休眠、`dsh web` 持续运行；`dsh web` 停了隧道会返回 502。
- 网关 README 还记录过 Tailscale Serve 与 Cloudflare Quick Tunnel；注意 HarmonyOS NEXT 目前没有官方
  Tailscale 客户端，长期使用推荐本文的命名隧道。

## 协议对照探针

`tools/probe.mjs` 是 Node 参考实现（与 ArkTS 客户端跑同一批请求，用于逐帧比对 `requestId` 关联与 `seq` 去重）：

```bash
cd tools && ln -sfn ~/.dsh/profiles/web/node_modules/ws node_modules/ws
node probe.mjs pair --url ws://127.0.0.1:3080/ws/mobile --code <pairingCode>
node probe.mjs run  --url ws://127.0.0.1:3080/ws/mobile
```

## UI 设计

界面参考上游客户端的设计语言（`dsh-mobile` 的 `Design/design-spec.md`、`DshTheme.kt`、`DshLiquidGlass.kt` 与截图）：深海军蓝渐变 + 技术点阵、选择性使用的磨砂玻璃、海洋蓝主行动、等宽数字。

- 配色/版式/信息架构参考上游；**启动图标**使用上游 `AppIcon` 的鲸鱼素材（MIT，署名见 `NOTICE`）
- ArkUI 对应实现：`common/HarnessBackground.ets`（渐变更点阵）、`views/MessageContent.ets`（Markdown 子集渲染）、`common/Format.ets`（分段与相对时间，纯逻辑有单测）

## 目录结构

```
entry/src/main/ets/
├─ protocol/    协议 DTO、wire 解码、严格 Base64URL 配对载荷
├─ gateway/     请求分道 / RequestTracker（唯一接收循环兑现）/ WebSocket 双通道客户端
├─ auth/        设备 ID、长期 token 安全存储、偏好
├─ projection/  对话与轨迹投影
├─ sync/        历史分页 + live 尾部合并
├─ store/       GatewayStore（UI 只读快照 + Intent）
├─ pages/       Pairing / Workspace / Conversation / Settings
└─ views/       可复用 UI 组件
```

## 当前进度（2026-09-10）

MVP 已在模拟器（HarmonyOS 6.1.1 / API 24）端到端跑通：配对 → 双通道连接 → 工作区/会话列表 → 历史 + 实时对话 → 发送消息 → 新建会话 → 凭据持久化与自动重连。

- 阶段 0 协议实测：`docs/spikes/2026-09-10-stage0-protocol-findings.md`
- 单元测试：`entry/src/test/`（170 例：解码、严格 Base64URL、请求分道/超时/去重、历史合并、对话投影、分页、统计口径等）

## 已知约束

- 只支持 HarmonyOS NEXT（API 12+）；HarmonyOS 4.x 及以下请使用上游 Android APK。
- 客户端 JSON 帧预算 3.5 MB（OHOS 实测 4 MB 可过 / 6 MB 失败），见 `docs/spikes/`。
- 明文 `ws://` 无需网络安全配置（官方 FAQ `faqs-network-16`）。
