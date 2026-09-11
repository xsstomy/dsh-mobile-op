# 上游参考核对（2026-09-10）

只读克隆（**不入本仓库**）：`/tmp/dsh-mobile-ref`、`/tmp/dsh-plugin-mobile-gateway-ref`

| 仓库 | commit | LICENSE | 用法 |
|---|---|---|---|
| `Clarklevis1995/dsh-mobile` | `826fff5d4369ec260e3fa7b3797e30a8636aff4e`（2026-09-08） | MIT | 参考交互/信息架构/协议字段集与踩坑 |
| `Clarklevis1995/dsh-plugin-mobile-gateway` | `0128ece31e6492cae26be5433cf3d218263d4d7c`（v0.7.2） | MIT | 协议契约（`docs/PROTOCOL.md` 副本） |

两个上游均为 MIT，可移植与署名；本仓库不复制其源码（Kotlin/Swift → ArkTS 属重写），仅在 `NOTICE` 署名。

## 需要移植/对齐的关键实现（含本次 commit 的文件名）

| 主题 | 上游文件 | 移植要点 |
|---|---|---|
| 严格配对载荷解析 | `DeepSeekHarnessMobile/Core/PairingPayloadParser.swift` | Base64URL 严格性：非空、**不允许 `=`**、只允许字母数字与 `-`/`_`、`length % 4 != 1`；`version == 2`；`publicUrl` scheme ∈ {ws, wss} 且有 host；`pairingCode` 非空、不含 `,`、无空白/控制字符；`expiresAt > now` |
| 请求/响应关联 | `DeepSeekHarnessMobile/Core/RequestTracker.swift` | 单一接收循环 + key→generation + 独立超时任务；**迟到响应按 generation 丢弃**，超时只清该 key，不动连接 |
| WS 平台层 | `DeepSeekHarnessMobile/Core/GatewayClient.swift` | 配对只在 control；`paired` 先于 `hello`；token 立即持久化；`session-creation` 用 continuation 表兑现（Android 版在同一事件流上开第二路订阅导致丢帧，**禁止照抄**） |
| 会话创建 | `shared/src/commonMain/kotlin/com/clarklevis/dsh/shared/gateway/GatewayProtocol.kt` | `session-create` 带 `requestId`，lane 策略 `REJECT_IF_BUSY`；超时/失败**不** recycle 连接 |
| 历史分页 | `shared/.../sync/HistorySyncEngine.kt` + `HistoryReducer.kt` | `maxBytes` 预算 + `beforeSeq=nextBeforeSeq` 续页；live 尾部按 `seq` upsert 去重 |
| 对话投影 | `shared/.../projection/ConversationProjection.kt` | `assistant/chunk`（text/reasoning/tool-call delta）增量追加，`assistant/message` 终态替换流式消息 |
| 协议字段集 | `shared/.../protocol/GatewayDtos.kt`、`GatewayWireDecoder.kt` | 字段名与可空性；`kind` 判别 + 未知 kind 不崩 |
| 交易/审批 | `shared/.../facade/SharedQuestionStore.kt`、`SharedApprovalStore.kt` | 按 `rpcId` 去重与重放；`replay: true` 幂等 |
| 双通道 | `shared/.../gateway/SplitGatewayTransport.kt` | control 先 hello → `split-channels` → 再开 conversation，`X-DSH-Channel` 头 |

## 实测补充（本仓库 `docs/spikes/2026-09-10-stage0-protocol-findings.md`）

- OHOS `webSocket` 支持 `protocol`（自定义 `Sec-WebSocket-Protocol`）与 `header`，配对子协议路径可用。
- 401/503 在 OHOS 侧同为 `on('error').code = 200`，无法区分；4004 由 `on('close').code` 给出。
- 单帧上限实测：4 MB 可过、6 MB 不行 → 客户端帧预算 3.5 MB。
