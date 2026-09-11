/*
 * Golden protocol fixtures.
 *  - live `event` frames: captured with tools/probe.mjs against dsh-plugin-mobile-gateway v0.7.2
 *  - raw history payloads: captured from `{"type":"history"}` (scheme A, unprojected)
 *  - synthesised frames: marked below; the captured turn answered without streaming chunks
 * Volatile identities (ids, paths, titles) are redacted.
 */

export const HELLO_FRAME: string = '{"kind":"hello","protocol":3,"capabilities":["split-channels","images","session-create","commands","tasks","goals","session-cancel","queue-control","session-archive","session-rename","file-downloads"],"port":3080,"clients":1,"authenticated":true,"device":{"id":"<id>","name":"<value>"}}';

export const SESSION_CREATED_FRAME: string = '{"kind":"session-created","sessionId":"<id>","agentPreset":"ptc","requestId":"<id>"}';

export const WORKSPACES_FRAME: string = '{"kind":"workspaces","items":[{"workspaceId":"<id>","path":"<value>","title":"<value>","sessionIds":["session-603d459c-81c3-460d-b2ad-9a03d8ad24cf","session-00ae8c19-5459-40f6-b435-27c62fb2e38c"],"createdAt":"2026-09-08T11:29:40.932Z","updatedAt":"2026-09-09T12:40:12.319Z"},{"workspaceId":"<id>","path":"<value>","title":"<value>","sessionIds":["session-3e7312ca-e519-4296-95bb-d9a88a8c8e1d","session-8277f36e-07f4-4d06-90db-b303aa729689","session-16d3ae0c-2778-47ae-bcc8-12dba7b64eee","session-2b199490-bd1a-40c5-bc10-c8ef7d352e8c","session-ed199e1d-91e1-4589-9e4d-a55f70e1c866","session-555f7e38-f9dc-4266-8357-f3f3aa5fb4d4"],"createdAt":"2026-09-05T02:40:06.189Z","updatedAt":"2026-09-09T12:31:00.939Z"}],"archivedSessionIds":["session-33e0c223-c506-462d-b679-4d59f14ac137","session-1a750d5a-55c1-4ef9-bc75-90b52cdc2068","session-a18b121f-6c49-4db2-9a4d-0c6efeb58651"]}';

export const SESSIONS_FRAME: string = '{"kind":"sessions","items":[{"sessionId":"<id>","updatedAt":1789043235035,"running":false,"blank":true,"cwd":"<value>","projections":{"asOfSeq":2,"values":{"title":null,"goal":null,"tokenUsage":{"uncachedInputTokens":0,"outputTokens":0,"cacheReadTokens":0,"cacheWriteTokens":0},"contextPressure":{},"contextBreakdown":{"systemTokens":0,"toolsTokens":0,"messageTokens":0},"sessionStats":{"turns":0,"steps":0,"llmMs":0,"toolMs":0,"ttftMs":0,"ttftSteps":0,"decodeMs":0,"decodeTokens":0},"turnOutline":[],"agentPreset":"ptc","subagentCatalog":[],"subagentTiming":{"settledMs":0},"subagent":null,"permissions":{"options":[{"value":"read-only","name":"<value>"},{"value":"workspace-write","name":"<value>"},{"value":"danger-full-access","name":"<value>"}],"currentValue":"danger-full-access"},"modelSelection":{"lastUsed":null,"next":null},"sessionListMetadata":{"blank":true,"lastPromptAt":null},"imageLimits":{"maxImageBytes":20971520,"maxImagesPerMessage":20,"maxMessageImageBytes":209715200,"maxImagePixels":64000000,"maxImageDimension":8192,"mediaTypes":["image/png","image/jpeg","image/webp","image/gif"]},"todos":null,"plan":{"active":false,"pending":false},"inbox":{"next-turn":[],"next-step":[]}}}},{"sessionId":"<id>","updatedAt":1789043217304,"running":false,"blank":true,"cwd":"<value>","projections":{"asOfSeq":2,"values":{"title":null,"goal":null,"tokenUsage":{"uncachedInputTokens":0,"outputTokens":0,"cacheReadTokens":0,"cacheWriteTokens":0},"contextPressure":{},"contextBreakdown":{"systemTokens":0,"toolsTokens":0,"messageTokens":0},"sessionStats":{"turns":0,"steps":0,"llmMs":0,"toolMs":0,"ttftMs":0,"ttftSteps":0,"decodeMs":0,"decodeTokens":0},"turnOutline":[],"agentPreset":"ptc","subagentCatalog":[],"subagentTiming":{"settledMs":0},"subagent":null,"permissions":{"options":[{"value":"read-only","name":"<value>"},{"value":"workspace-write","name":"<value>"},{"value":"danger-full-access","name":"<value>"}],"currentValue":"danger-full-access"},"modelSelection":{"lastUsed":null,"next":null},"sessionListMetadata":{"blank":true,"lastPromptAt":null},"imageLimits":{"maxImageBytes":20971520,"maxImagesPerMessage":20,"maxMessageImageBytes":209715200,"maxImagePixels":64000000,"maxImageDimension":8192,"mediaTypes":["image/png","image/jpeg","image/webp","image/gif"]},"todos":null,"plan":{"active":false,"pending":false},"inbox":{"next-turn":[],"next-step":[]}}}}]}';

export const HISTORY_FRAME: string = '{"kind":"history","events":[{"type":"permission/preset","seq":0,"time":1789043238582,"data":{"preset":"danger-full-access"}},{"type":"sandbox/mode","seq":1,"time":1789043238582,"data":{"mode":"danger-full-access"}},{"type":"approval/policy","seq":2,"time":1789043238582,"data":{"policy":"never"}}],"hasMore":false,"projections":{"asOfSeq":2,"values":{"title":null,"goal":null,"tokenUsage":{"uncachedInputTokens":0,"outputTokens":0,"cacheReadTokens":0,"cacheWriteTokens":0},"contextPressure":{},"contextBreakdown":{"systemTokens":0,"toolsTokens":0,"messageTokens":0},"sessionStats":{"turns":0,"steps":0,"llmMs":0,"toolMs":0,"ttftMs":0,"ttftSteps":0,"decodeMs":0,"decodeTokens":0},"turnOutline":[],"agentPreset":"ptc","subagentCatalog":[],"subagentTiming":{"settledMs":0},"subagent":null,"permissions":{"options":[{"value":"read-only","name":"<value>"},{"value":"workspace-write","name":"<value>"},{"value":"danger-full-access","name":"<value>"}],"currentValue":"danger-full-access"},"modelSelection":{"lastUsed":null,"next":null},"sessionListMetadata":{"blank":true,"lastPromptAt":null},"imageLimits":{"maxImageBytes":20971520,"maxImagesPerMessage":20,"maxMessageImageBytes":209715200,"maxImagePixels":64000000,"maxImageDimension":8192,"mediaTypes":["image/png","image/jpeg","image/webp","image/gif"]},"todos":null,"plan":{"active":false,"pending":false},"inbox":{"next-turn":[],"next-step":[]}}},"sessionId":"<id>","bytes":266,"view":"conversation"}';

export const SESSION_ARCHIVES_FRAME: string = '{"kind":"session-archives","archivedSessionIds":["session-33e0c223-c506-462d-b679-4d59f14ac137","session-1a750d5a-55c1-4ef9-bc75-90b52cdc2068","session-a18b121f-6c49-4db2-9a4d-0c6efeb58651"]}';

export const SESSION_QUEUES_FRAME: string = '{"kind":"session-queues","queues":{"session-603d459c-81c3-460d-b2ad-9a03d8ad24cf":[],"session-a7e96ab0-3a11-45ac-8732-010243d046b5":[]}}';

export const SESSION_QUEUE_FRAME: string = '{"kind":"session-queue","sessionId":"<id>","items":[{"id":"<id>","placement":"queued","rpcId":"<id>","message":{"id":"<id>","content":[{"type":"text","text":"<value>"}]}}]}';

export const SESSION_TITLE_CHANGED_FRAME: string = '{"kind":"session-title-changed","sessionId":"<id>","title":"<value>","seq":14,"time":1789043238656,"source":{"kind":"fallback"}}';

export const SUBSCRIBED_FRAME: string = '{"kind":"subscribed","sessionId":"<id>"}';

export const SENT_FRAME: string = '{"kind":"sent","sessionId":"<id>","mode":"queue"}';

export const EVENT_USER_MESSAGE: string = '{"kind":"event","sessionId":"<id>","seq":8,"time":1789043238651,"event":{"type":"user/message","text":"<value>","source":"user"}}';

export const EVENT_ASSISTANT_MESSAGE: string = '{"kind":"event","sessionId":"<id>","seq":16,"time":1789043241075,"event":{"type":"assistant/message","turn":1,"step":1,"text":"<value>","reasoning":"","toolCalls":[]}}';

export const EVENT_TURN_END: string = '{"kind":"event","sessionId":"<id>","seq":18,"time":1789043241076,"event":{"type":"turn/end","turn":1,"reason":"completed"}}';

export const WRONG_CHANNEL_ERROR: string = '{"kind":"error","code":"wrong-channel","requestType":"history","message":"Request belongs to the other mobile channel"}';

/* Synthesised from docs/PROTOCOL.md §13. */
export const EVENT_CHUNK_TEXT: string = '{"kind":"event","sessionId":"session-redacted","seq":40,"time":1789043235066,"event":{"type":"assistant/chunk","turn":1,"step":1,"chunkType":"text-delta","text":"ok"}}';

export const EVENT_CHUNK_REASONING: string = '{"kind":"event","sessionId":"session-redacted","seq":41,"time":1789043235067,"event":{"type":"assistant/chunk","turn":1,"step":1,"chunkType":"reasoning-delta","text":"thinking"}}';

export const EVENT_TOOL_CALL: string = '{"kind":"event","sessionId":"session-redacted","seq":42,"time":1789043235068,"event":{"type":"tool/call","turn":1,"step":1,"callId":"call-1","name":"bash","arguments":{"command":"ls"}}}';

export const EVENT_TOOL_RESULT: string = '{"kind":"event","sessionId":"session-redacted","seq":43,"time":1789043235069,"event":{"type":"tool/result","turn":1,"step":1,"callId":"call-1","isError":false,"preview":"a\\nb"}}';

/**
 * Usage chunk. Not captured: built from the flat usage shape the live gateway
 * sends (PROTOCOL.md §5). `turn`/`step` mirror {@link EVENT_CHUNK_TEXT} so it
 * can be folded into the same step.
 */
export const EVENT_CHUNK_USAGE: string = '{"kind":"event","sessionId":"session-redacted","seq":44,"time":1789043235070,"event":{"type":"assistant/chunk","turn":1,"step":1,"chunkType":"usage","usage":{"uncachedInputTokens":100,"cacheReadTokens":20,"cacheWriteTokens":5,"outputTokens":7}}}';

/**
 * Second step of turn 1 (text + its usage). Not captured; used to prove that a
 * turn's footer sums the usage of every step and that a new step gets its own
 * bubble instead of rewriting the previous one.
 */
export const EVENT_CHUNK_TEXT_STEP2: string = '{"kind":"event","sessionId":"session-redacted","seq":45,"time":1789043235078,"event":{"type":"assistant/chunk","turn":1,"step":2,"chunkType":"text-delta","text":"more"}}';

export const EVENT_CHUNK_USAGE_STEP2: string = '{"kind":"event","sessionId":"session-redacted","seq":46,"time":1789043235080,"event":{"type":"assistant/chunk","turn":1,"step":2,"chunkType":"usage","usage":{"uncachedInputTokens":125,"outputTokens":7}}}';

/**
 * `turn/start` payloads around {@link EVENT_CHUNK_TEXT}'s time (1789043235066) in
 * the raw session-event shape (`{type,seq,time,data}` — the same shape history
 * replay hands to the reducer). The live gateway was never captured emitting one,
 * so both are built from the documented shape: EARLIER refines the start when it
 * arrives after the first chunk, LATER proves a replayed frame cannot move the
 * start forward.
 */
export const TURN_START_EARLIER: string = '{"type":"turn/start","seq":39,"time":1789043235000,"data":{"turn":1}}';

export const TURN_START_LATER: string = '{"type":"turn/start","seq":39,"time":1789043240000,"data":{"turn":1}}';

/* Raw history payloads (unprojected SessionEvents). */
export const HISTORY_RAW_USER_MESSAGE: string = '{"type":"user/message","seq":519,"time":1789045241848,"data":{"content":[{"type":"text","text":"只回复ok不要调用工具"}],"source":{"kind":"user","rpcId":"3cb8dd67-0d49-42d4-ae5a-6b410b83ac33","clientTimeZone":"Asia/Shanghai"},"role":"user","id":"83a591b7-ce4d-4770-b0b0-a918d534c7fb"},"surfaceOp":"append"}';

export const HISTORY_RAW_ASSISTANT_MESSAGE: string = '{"type":"assistant/message","seq":520,"time":1789045245530,"data":{"turn":7,"step":1,"message":{"role":"assistant","content":[{"type":"text","text":"ok"}]},"usage":{"inputTokens":1,"outputTokens":2}}}';

export const HISTORY_RAW_TURN_END: string = '{"type":"turn/end","seq":522,"time":1789045245531,"data":{"turn":7,"reason":{"kind":"completed"}}}';

export const HISTORY_RAW_TOOL_CALL: string = '{"type":"tool/call","seq":86,"time":1789037666899,"data":{"turn":6,"step":1,"callId":"call_00_VBbio2yqj5Whvb5pI7vu7806|498766ac-a55b-4399-a969-b895b002c270","name":"run_code","arguments":"{\\"description\\":\\"Search for market cap and turnover rendering in frontend\\",\\"code\\":\\"\\\\nconst patterns = [\\\\n  \\\\\\"市值\\\\\\",\\\\n  \\\\\\"成交额\\\\\\",\\\\n  \\\\\\"交易金额\\\\\\",\\\\n  \\\\\\"200\\\\\\",\\\\n  \\\\\\"亿\\\\\\",\\\\n];\\\\nconst results: Record<string, unknown> = {};\\\\nfor (const p of patterns) {\\\\n  const r = await tools.grep({ pattern: p, path: \\\\\\"frontend\\\\\\", include: \\\\\\"*.js\\\\\\" });\\\\n  results[p] = r.matches.slice(0, 30).map(m => `${m.path}:${m.lineNumber}: ${m.line.trim().slice(0,160)}`);\\\\n}\\\\nconsole.log(JSON.stringify(results, null, 1));\\\\n\\"}"}}';

export const HISTORY_RAW_TOOL_RESULT: string = '{"type":"tool/result","seq":97,"time":1789037667107,"data":{"turn":6,"step":1,"message":{"source":{"kind":"tool","callId":"call_00_VBbio2yqj5Whvb5pI7vu7806|498766ac-a55b-4399-a969-b895b002c270"},"content":[{"type":"tool-result","toolCallId":"call_00_VBbio2yqj5Whvb5pI7vu7806|498766ac-a55b-4399-a969-b895b002c270","content":[{"type":"text","text":"{\\n \\"200\\": [\\n  \\"frontend/vendor/html2canv"}],"isError":false}],"role":"user","id":"28156f71-c2cb-4c4e-9bb6-df0f84f31d15"}},"sourceEventSeqs":[86],"surfaceOp":"append"}';


/* Settings / command catalogue frames captured from the gateway (2026-09-10).
 * Note: permission-options uses {value,name,currentValue}, not the documented {id,label}. */
export const MODELS_FRAME: string = '{"kind":"models","current":{"provider":"opencode-go-live","model":"deepseek-flash"},"routable":true,"groups":[{"id":"opencode-go-live","name":"opencode-go-live","models":[{"id":"deepseek-v4-pro","name":"deepseek-v4-pro"},{"id":"deepseek-v4-flash","name":"deepseek-v4-flash"}]},{"id":"deepseek-official","name":"DeepSeek","models":[{"id":"deepseek-flash","name":"DeepSeek-V41-Flash","reasoning":{"efforts":[{"id":"off","name":"Off","description":"Use for simple tasks that do not need reasoning."},{"id":"low","name":"Low","description":"Prefer for routine or latency-sensitive tasks."},{"id":"high","name":"High","description":"The default balance for most tasks."},{"id":"max","name":"Max","description":"Reserve for the hardest quality-first tasks."}],"defaultEffort":"high"}},{"id":"deepseek-v4-flash","name":"DeepSeek-V4-Flash","description":"Fast, efficient, and economical; suited to focused, routine, or parallel tasks.","reasoning":{"efforts":[{"id":"off","name":"Off","description":"Use for simple tasks that do not need reasoning."},{"id":"low","name":"Low","description":"Prefer for routine or latency-sensitive tasks."},{"id":"high","name":"High","description":"The default balance for most tasks."},{"id":"max","name":"Max","description":"Reserve for the hardest quality-first tasks."}],"defaultEffort":"high"}}]}],"failures":[]}';

export const PERMISSION_OPTIONS_FRAME: string = '{"kind":"permission-options","namespace":{"ns":"permission","schema":{"uid":887,"refs":{"882":{"type":"const","meta":{},"value":"read-only"},"883":{"type":"const","meta":{},"value":"workspace-write"},"884":{"type":"const","meta":{},"value":"danger-full-access"},"886":{"type":"union","meta":{"required":true},"list":[882,883,884]},"887":{"type":"object","meta":{"default":{}},"dict":{"defaultPreset":886}}}},"value":{"defaultPreset":"danger-full-access"},"base":{"defaultPreset":"workspace-write"},"user":{"defaultPreset":"danger-full-access"},"applies":"live","secrets":[],"revision":0},"sessionPermissions":{"options":[{"value":"read-only","name":"read-only"},{"value":"workspace-write","name":"workspace-write"},{"value":"danger-full-access","name":"danger-full-access"}],"currentValue":"danger-full-access"}}';

export const AGENT_PRESETS_FRAME: string = '{"kind":"agent-presets","presets":[{"id":"standard","trust":"system","isDefault":false,"name":"标准模式","description":"功能完整的编码 Agent，支持文件编辑、Shell、文件与网页检索、Skills、计划、目标、子代理和工作流。"},{"id":"ptc","trust":"system","isDefault":true,"name":"PTC 模式","description":"功能完整的编码 Agent，但默认不提供 workflow 工具；其他工具通过 PTC 模式 SDK 呈现，让模型用一个 TypeScript 程序组合多步操作。"},{"id":"minimal","trust":"system","isDefault":false,"name":"极简模式","description":"仅提供持久 shell 的单工具编码 Agent。"},{"id":"cordis","trust":"system","isDefault":false,"name":"创造模式","description":"用于创建自定义 Agent preset：具备标准模式的全部能力，并提供运行时检查、插件实验和 preset 创作指导。"}],"authorable":true}';

export const DEFAULTS_FRAME: string = '{"kind":"defaults","agentPresetDefault":"ptc","permissionDefault":"danger-full-access"}';

export const DEFAULT_MODEL_FRAME: string = '{"kind":"default-model","selection":{"provider":"opencode-go-live","model":"deepseek-flash"}}';

export const COMMANDS_FRAME: string = '{"kind":"commands","sessionId":"session-603d459c-81c3-460d-b2ad-9a03d8ad24cf","locale":"zh-CN","groups":[{"id":"commands","title":"命令","items":[{"id":"command:compact","name":"compact","description":"Compact older conversation history","source":"host","action":"execute","ui":{"kind":"immediate","submitRequest":"command-execute","submitText":"/compact"}},{"id":"command:export","name":"export","description":"Download this Session log as a ZIP archive","source":"host","action":"execute","ui":{"kind":"immediate","submitRequest":"command-execute","submitText":"/export"}},{"id":"command:feedback","name":"feedback","description":"record feedback about this session","source":"host","action":"execute","ui":{"kind":"input","insertText":"/feedback ","hint":"<text>","images":false,"submitRequest":"command-execute"},"input":{"hint":"<text>"}},{"id":"command:goal","name":"goal","description":"set or view the goal for a long-running task","source":"host","action":"execute","ui":{"kind":"input","insertText":"/goal ","hint":"[<objective>|clear|edit <objective>|pause|resume]","displayHint":"输入目标，智能体将持续执行","images":false,"submitRequest":"command-execute"},"input":{"hint":"[<objective>|clear|edit <objective>|pause|resume]"}}]},{"id":"skills","title":"技能","items":[{"id":"skill:eval","name":"eval","description":"仅在用户明确调用 eval（如 `$eval`、`/eval` 或“使用 eval”）时启用。让彼此隔离的外部用户通过真实入口使用指定目标，留下可追溯行为证据；视觉创作成品另加独立开放式设计评审。按用户授权停在反馈，或修改并持续复验。一般性的评审、测试或优化请求不得自动触发。","source":"skill","action":"insert","modelInvocable":true,"ui":{"kind":"input","insertText":"/eval ","images":true,"submitRequest":"message"}},{"id":"skill:eval-new","name":"eval-new","description":"仅在用户明确调用（如 `$eval-new`、`/eval-new` 或\\"用 eval-new 评一下\\"）时启用。把当前工作交给几个互不知情、各有性格的仿真用户真实使用（宿主托管的真浏览器/安卓模拟器），拿回第一人称结论；可对任何一个人追问、追加任务、调取客观轨迹。一般性的评审、测试或优化请求不得自动触发。","source":"skill","action":"insert","modelInvocable":true,"ui":{"kind":"input","insertText":"/eval-new ","images":true,"submitRequest":"message"}},{"id":"skill:openspec-apply-change","name":"openspec-apply-change","description":"Implement tasks from an OpenSpec change. Use when the user wants to start implementing, continue implementation, or work through tasks.","source":"skill","action":"insert","modelInvocable":true,"ui":{"kind":"input","insertText":"/openspec-apply-change ","images":true,"submitRequest":"message"}},{"id":"skill:openspec-archive-change","name":"openspec-archive-change","description":"Archive a completed change in the experimental workflow. Use when the user wants to finalize and archive a change after implementation is complete.","source":"skill","action":"insert","modelInvocable":true,"ui":{"kind":"input","insertText":"/openspec-archive-change ","images":true,"submitRequest":"message"}}]}]}';

