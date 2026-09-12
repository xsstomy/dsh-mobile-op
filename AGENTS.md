# AGENTS.md — DshMobile (HarmonyOS)

DeepSeek Harness 的 HarmonyOS 原生客户端。bundleName `com.dshmobile.app`，ArkTS + ArkUI（Stage 模型）。

## 1. 资料查询：统一使用 devecocli

实现任何系统能力（权限、网络、存储、后台任务、路由、组件）之前，**先查文档再写代码**，不要凭记忆写 API：

```bash
devecocli docs search <关键词>            # 例：devecocli docs search webSocket 明文
devecocli docs read "<documentId>"       # 读全文
devecocli docs catalog                   # 目录
devecocli check lint                     # 静态检查
devecocli build --build-mode debug       # 构建
devecocli run --device <serial>          # 装到设备：优先真机，无真机再用模拟器
devecocli ui screenshot --device <serial> --path <out.png>  # 截图（--path 必填，不能覆盖已有文件）
devecocli log --level E --bundle-name com.dshmobile.app --tail 200
```

工具链不在 PATH：`hvigorw` / `ohpm` / `hdc` 用绝对路径
（`/Applications/DevEco-Studio.app/Contents/tools/{hvigor/bin/hvigorw.js,ohpm/bin/ohpm}`、
`/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc`）。

### 调试目标：优先真机

- 先看当前有哪些设备：`hdc list targets`（`hdc` 用上面的绝对路径）。
- **连接了真机就在真机上调试**，用真机的 serial 传给 `--device`；
  **只有没有真机时才用模拟器**（`127.0.0.1:5555`）。
- 真机和模拟器同时在线时默认选真机，不要图省事用模拟器。
- 布局、交互、键盘、状态栏、字体、网络等差异在两者间很大，UI 相关问题必须在真机上复现和验收。
- 模拟器访问宿主用 `10.0.2.2`；真机在局域网用宿主私有 IP（见 §4）。

## 2. 协议契约

- `docs/PROTOCOL.md` 是上游网关协议（v0.7.2，MIT）的**原样副本**，是唯一权威；不要凭记忆改字段。
- 服务端能力以连接后的 `hello.capabilities` 为准，用能力门控（如 `session-create` / `split-channels` / `file-downloads`），
  能力缺失时必须走 fallback，不得直接假设。
- 上游是**第三方仓库**：需要改网关时走 fork + PR，禁止只改本机 `node_modules`。

## 3. 架构约定（勿破坏）

- **事件流只能有一个消费者**：`GatewayClient` 的 socket 接收循环是唯一消费者，通过 `RequestTracker`（key→Promise）兑现请求，
  对 UI 只暴露**广播式订阅**。禁止在同一个事件流上再开第二路订阅。
- **请求超时/失败不得断开连接**：只清理该请求的 pending 并报错；只有传输层失败（close/error/网络变化）才重连。
- **迟到响应必须按 generation/requestId 丢弃**，不得覆盖新状态。
- 纯逻辑（协议解码、分道、分页、投影、去重）放在 `protocol/ gateway/ projection/ sync/`，不依赖系统 API，必须可单测。
- 系统 API（webSocket、Preferences、Asset、文件、图片、后台任务）只在 `gateway/GatewayClient.ets`、`auth/`、`store/` 的平台适配层出现。
- UI 只读 `GatewayStore` 快照、只调 Intent 方法；不在页面里写协议逻辑。

## 4. 硬性事实（已实测，别推翻）

- 模拟器访问宿主用 `10.0.2.2`（QEMU slirp），不要用 `127.0.0.1`。
- 客户端单帧 JSON 上限按 **3.5 MB** 设计（实测 4 MB 可过、6 MB 失败）→ 单图原图 ≤ 2.5 MB。
- `on('error')` 只有 `BusinessError.code = 200`，**区分不了 401/503**；`4004`（网关关闭）走 `on('close').code`。
- `devecocli` 无 `test` 子命令；Local Test 不支持系统 API，fixtures 必须是 `.ets` 常量模块。

## 5. 约定

- 每次修改完成代码后必须 `git push`。
- 本地工作笔记（`docs/plans/`、`docs/evidence/` 等）不入库，见 `.gitignore`。
- 新增色值/字号/圆角先落到 `common/Constants.ets` 再使用。
