# 阶段 0 — 鸿蒙侧协议风险验证结论（2026-09-10 实测）

模拟器：`Pura 90`（`127.0.0.1:5555`，HarmonyOS 6.1.1 / API 24，`const.ohos.apiversion=24`）
网关：本机 `dsh-plugin-mobile-gateway` v0.7.2，LAN 监听 `ws://192.168.3.47:3081/ws/mobile`，本机 `ws://127.0.0.1:3080/ws/mobile`，日志 `/tmp/mobile-gateway.log`
探针：临时页面 `entry/src/main/ets/spike/WsSpike.ets`（已删除，源码留档 `docs/spikes/WsSpike.v2.ets.txt`，其中一次性配对码已 redact）

## 1. 端点可达性（关键结论）

模拟器网卡 `eth0=10.0.2.15/24`（QEMU slirp），**宿主通过 `10.0.2.2` 访问**。

| 端点 | 结果 |
|---|---|
| `ws://10.0.2.2:3081/ws/mobile` | ✅ 配对成功（`paired` + `hello`，`port=3081`） |
| `ws://192.168.3.47:3081/ws/mobile` | ✅ 网络可达（请求到达网关，因一次性配对码已被前一个端点消费而返回 401） |
| `ws://10.0.2.2:3080/ws/mobile` | ✅ 网络可达（同上，401） |

结论：模拟器可访问宿主；**默认端点用 `ws://10.0.2.2:3081/ws/mobile`**（局域网端点，私网校验通过：网关侧 `remote=127.0.0.1`）。

## 2. 配对与鉴权

- 子协议形式 `protocol: "dsh-mobile-v1, dsh-pair.<pairingCode>"` **可用**：OHOS 会把该字符串原样作为 `Sec-WebSocket-Protocol` 发送，网关按逗号切分并回显 `dsh-mobile-v1`。不需要 `?pairingCode=` 兼容路径。
- 请求头 `X-DSH-Device-ID: <uuid>` 生效；配对成功后网关按该 ID 复用设备记录（日志 `device=harmony-spike2`）。
- 长期 token（43 字符）走 `Authorization: Bearer <token>` + `protocol: "dsh-mobile-v1"` **可用**；`paired` 帧必须先于 `hello` 处理并落盘。
- `hello.capabilities` 实测（模拟器侧）：`split-channels, images, session-create, commands, tasks, goals, session-cancel, queue-control, session-archive, session-rename, file-downloads`，`protocol=3`，`authenticated=true`。

## 3. 双通道

- `X-DSH-Channel: control` 与 `X-DSH-Channel: conversation` 两条连接**均可建立**且各自收到 `hello`。
- control 上发 `history` 会收到 `{kind:'error', code:'wrong-channel', requestType:'history'}`——通道守卫可用，客户端必须把 `message/history/subscribe/unsubscribe` 只发 conversation。
- 顺序要求确认：control 的 `hello` 必须先到（`split-channels` 门控），再开 conversation。

## 4. 错误与关闭码分类（影响 UI 文案）

| 场景 | OHOS 观测 |
|---|---|
| 无凭证 / 错凭证（HTTP 401） | `on('error')` → `BusinessError.code = 200`，`message` 为空 |
| 网关未开启（HTTP 503） | 同上 `code = 200`（无法与 401 区分） |
| 服务端主动关闭（网关关闭） | `on('close')` → `CloseResult{code: 4004, reason: 'mobile gateway disabled'}` |

结论：**UI 不承诺区分 401 与 503**；只按「连不上（升级失败）/ 认证可能失效（可重配对）/ 网关已关闭（4004，停止自动重连）/ 鉴权被重置（4003，用 token 重连或重配对）」四类处理，其中 4003/4004 依赖 `on('close')`。

## 5. 单帧大小上限（影响图片压缩上限）

用 `{"type":"__probe_pad__","pad":"x"*N}` 探测（JSON 文本帧，UTF-8）：

| 帧大小 | 结果 |
|---|---|
| 1 MB / 2 MB / 3 MB / 4 MB | ✅ 服务端回 `unknown message type`（帧完整到达） |
| 6 MB / 7 MB / 8 MB / 32 MB | ❌ 无任何回包（本地发送失败，连接未立即关闭） |

结论：**客户端 JSON 帧预算按 ≤ 4 MB 设计，留安全余量取 3.5 MB**。
换算：Base64 膨胀约 1.37×，故**单张原图 ≤ 2.5 MB**；多图合计帧 ≤ 3.5 MB。网关侧上限（144 MiB / 图片 100 MiB）不是瓶颈，瓶颈在 OHOS 客户端。

## 6. 明文 `ws://`

`devecocli docs search` 命中 FAQ `faqs-network-16`：**Stage 模型无需任何网络安全配置即可使用 HTTP/WS 明文**；实测 `ws://` 直连成功，无需 `network_security_config`。

## 7. 对照基线（Node 探针，`tools/probe.mjs`）

同一批请求在宿主侧的往返耗时（`/tmp/dsh-probe/summary.json`）：

| 请求 | 耗时 |
|---|---|
| `workspaces` | 11 ms |
| `sessions` | 87 ms |
| `session-create` | 54 ms |
| `subscribe` | 1 ms |
| `history` | 4 ms |
| `message`（`sent` 回执） | 11 ms |
| `session-archive` | 72 ms |

> 附带结论：上游 Android v1.5.0「新建会话卡住」的根因得到二次确认——服务端 54 ms 就能建好会话，超时完全来自客户端。

## 8. 未验证 / 留待后续

- 4003（重新开启鉴权导致的无凭证连接被关闭）未单独实测，按协议文档实现；4004 已实测。
- `wss://`（Tailscale / 公网 TLS）路径与 `caPath` / `skipServerCertVerification` 未实测（需真机或公网入口，属 P2）。
- 扫码配对 `@hms.core.scan.scanBarcode` 未在模拟器验证（模拟器无相机），手动粘贴 `qrPayload` 作为默认路径；真机阶段再验。
