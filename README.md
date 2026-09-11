# DshMobile (HarmonyOS)

DeepSeek Harness 的 **HarmonyOS 原生客户端**（ArkTS + ArkUI，Stage 模型），通过第三方网关
[`dsh-plugin-mobile-gateway`](https://github.com/Clarklevis1995/dsh-plugin-mobile-gateway) 的
`dsh-mobile-v1` 协议（`hello.protocol = 3`）连接本机/自建的 DeepSeek Harness。

- 协议契约：[`docs/PROTOCOL.md`](docs/PROTOCOL.md)（上游 v0.7.2 原样收录）
- 上游同类客户端（iOS / Android，KMP）：[`Clarklevis1995/dsh-mobile`](https://github.com/Clarklevis1995/dsh-mobile)
- 本仓库是独立的 HarmonyOS 实现，不复用上游源码，署名见 [`NOTICE`](NOTICE)

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
