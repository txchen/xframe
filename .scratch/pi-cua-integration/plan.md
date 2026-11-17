# Pi 使用现有 CUA：接入研究与修改方案

日期：2026-11-16。范围：这台 M1 上的 Pi 1.5.2、Paseo 0.15.4、ChatGPT/Codex 附带 CUA runtime。只读调查及独立 MCP 握手；没有修改运行配置或授予桌面访问权限。

## 结论

无需改 Opus 模型，也不必重写截图/点击实现。Pi 已经有 stdio MCP 和图片工具结果支持；现成的 `@oai/cua-repl` 可以作为 MCP server 复用。真正缺口包括：Pi 会话没有注册这个 server；Pi 的内置 MCP runtime 没有接 CUA 所需的服务端授权请求；Codex 的工具暴露和结束回调语义不会自动迁移。

因此「复制一份 MCP 配置」能解决发现问题，但不能当作完整接入成功。推荐先做一个小型 Pi CUA extension，以官方 runtime 为子进程、保留审批和图像通道；不改 XFrame，不直接修改已安装的 Pi/Paseo bundle。长期可将通用 elicitation 支持提交给 Pi 上游。

## 已确认的事实

1. 实际 Opus agent 配置为 `pi / anthropic/claude-opus-5-5 / high`。精确工具发现及 ALL_TOOLS 均没有 CUA，不是模型不会调用。
2. Pi 官方本机文档支持 `~/.pi/agent/mcp.json`、受信项目 `.pi/mcp.json`、stdio/HTTP MCP、`pi.registerMcpServer`、`toolExposure`、`direct` 工具及 image content。参考 [本机 MCP 文档](/Users/hibiki/.pi/agent/install/releases/1.5.2/node_modules/@earendil-works/pi-coding-agent/docs/mcp.md) 与 [Pi 源码仓库](https://github.com/earendil-works/pi)。
3. 本机 Codex 的 `unified-computer-use` 插件通过官方 Node 启动 `@oai/cua-repl/bin/cua-repl.mjs`，后者启动持久 NodeREPL，默认导入 `@oai/cua/tinyskyAlt`，提供 `cua` API。参考 [packaged README](/Applications/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/@oai/cua-repl/README.md) 及 [实际 MCP manifest](/Users/hibiki/.codex/plugins/cache/openai-bundled/unified-computer-use/26.1027.51404/.mcp.json)。这是本机实现依据，不是承诺跨客户端受官方支持。
4. 独立启动同一官方进程，仅做 `initialize` 和 `tools/list`，成功返回 `js`、`js_reset`、`js_add_node_module_dir`、`turn_ended`。结果保存于 `mcp-discovery.json`。未调用 `js`、未枚举应用、未读取桌面或截图。这只证明协议发现兼容，不证明原生控制可用。
5. Sky macOS policy 明确要求 `nodeRepl.createElicitation`，会提交应用身份、风险和授权持久化元数据。参考 [computer-use-policy.js](/Applications/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/@oai/sky/dist/project/cua/sky_js/src/targets/mac/computer-use-policy.js)。MCP 将这类请求定义为 [elicitation/create](https://modelcontextprotocol.io/specification/2025-06-18/client/elicitation)，支持 accept、decline、cancel；客户端必须声明支持。
6. Pi 内置 MCP runtime 创建 `McpClient` 时只配置 name/version/timeout/roots；未注册 elicitation handler。底层 client 提供 `setRequestHandler`，默认只处理 ping/roots，未处理的请求返回 method-not-found。参考 [runtime.js:281](/Users/hibiki/.pi/agent/install/releases/1.5.2/node_modules/@earendil-works/pi-coding-agent/dist/extensions/mcp/runtime.js:281)、[client.js:160](/Users/hibiki/.pi/agent/install/releases/1.5.2/node_modules/@earendil-works/pi-mcp/dist/client.js:160)、[client.js:327](/Users/hibiki/.pi/agent/install/releases/1.5.2/node_modules/@earendil-works/pi-mcp/dist/client.js:327)。
7. CUA native pipe 依赖可信 NodeREPL 的 nativePipe / launchServices 和已安装 Sky 服务，部分路径还依赖 desktop host service。不能用普通 Node import 就假定可用。参考 [native-pipe.js](/Applications/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/@oai/sky/dist/project/cua/sky_js/src/targets/mac/native-pipe.js)。原生服务的签名和系统权限是否允许该运行组合，仍需专门验收。

## 推荐修改

### A. 一个明确、版本可检查的 CUA 启动配置

- 复用 `/Applications/ChatGPT.app/Contents/Resources/cua_node/bin/node`、对应 `@oai/cua-repl/bin/cua-repl.mjs` 和 `node_repl`，不要下载不明替代实现。
- 首期只设置 `CUA_REPL_ENABLED_SURFACES=computer`。XFrame 是原生应用，不需要引入 Chrome/IAB 的额外授权及 session 路由。
- 从本机 manifest 映射必须的 runtime/module/service 路径。不要复制其他 agent 的 executor ID、身份或 pipe token，不依赖父 agent 生命周期。
- Codex 的 `env_vars`、`enabled_tools`、`omit_tools_from`、`startup_timeout_sec` 等不能原样当成 Pi 字段。Pi 使用自己的 `env`、`timeout`、`exposure` 和 `toolExposure`。
- 只给模型直接暴露 `js`、`js_reset`；其他默认隐藏。尤其 `turn_ended` 是宿主生命周期调用，不应让模型随意传会话 ID；`js_add_node_module_dir` 没有本任务需求。

### B. 补齐审批，而不是自动批准

推荐 extension 自己持有 `McpClient`，注册所需 elicitation capability 和 handler，再注册 CUA 工具。单独调用 `registerMcpServer` 会进入当前缺 handler 的内置 runtime，不能独自解决此问题。

- 将请求发给真实用户 UI，显示请求服务、目标应用、操作及持久化范围。
- 保留 accept/decline/cancel；关闭窗口、取消 agent、超时均不得变成接受。
- 返回符合 requestedSchema 的结果，正确处理 CUA 自定义 metadata/persist 字段。首期只支持明确的当前会话授权；不得伪造「始终允许」。
- Pi/Paseo 的普通工具 permission gate 与 MCP 调用中途的 elicitation 是两层，不能拿前者替代后者。
- Paseo 已有 Pi extension UI 桥接，可评估复用 confirm/select/input；如当前 RPC 模式不能可靠展示该请求，须补对应 adapter/UI 层，或保持拒绝并报告不支持。
- 不改 Sky 签名要求，不注入别人的授权，不通过 AppleScript/CGEvent 自写绕过实现。

### C. 生命周期、图片和使用说明

- 每个 Pi session 独立 REPL，连续 `js` 调用保留绑定；reset 才清空。不要把两个 agent 接到同一个持久 REPL。
- CUA `turn_ended` 应对应真正结束/空闲的 agent 回合。Pi 的 `turn_end` 是每个模型工具轮，不能直接绑定；`agent_end` 之后还可能重试，优先评估 `agent_settled`，取消/关闭路径按实际契约另行处理。session shutdown 回收自己的 server/process group。要处理 abort、超时和断线。
- 传递完整 MCP image content 给模型和 Paseo UI，不能 JSON.stringify 截图后只返回文字，也不能丢掉 tool/server instructions。
- 保留官方首次调用/读取文档/新 AX 状态后再操作的要求。可以附简短 Pi 使用说明：先 `cua.getState()` 或 `cua.getApp()`，然后使用工具返回的 API，禁止猜测方法。
- 多 agent 同时操作同一桌面必须协调；先单 agent 验收，不让两个会话抢焦点。

### D. 隔离验证后才启用在研究 agent

不直接修改全局 `~/.pi/agent/mcp.json` 让所有 agent 自动获得桌面控制。先在隔离测试会话加载 extension；确认授权流程后再明确启用目标会话。现有 agent 应在安全回合边界重载或重建，不能靠补一句提示就获得工具。

## 验收顺序

1. mock MCP 测试：初始化 capability、请求/响应 schema、允许/拒绝/取消、并发请求、超时/中止均正确。
2. 官方 runtime 工具发现：已验证。后续验证 Pi 实际能看到直接工具及说明。
3. 在屏幕解锁且用户批准相应应用访问后：`cua.getState()` / `getApp('XFrame')` 可取 AX；如果原生身份、TCC 或宿主服务拒绝，原样报告，不绕过。
4. 截图以图片进入 Opus 的上下文与 Paseo 页面，而不是只有文字或 base64。
5. 一次无破坏性 UI 操作，例如打开并关闭 XFrame View 菜单，操作后读取新的 AX 状态。
6. 同一 session 跨工具调用保留变量；reset 后旧变量失效；turn/session 结束能正常清理；拒绝授权后没有隐藏操作。
7. 最后由原研究 agent 完成一个最短真实串流操作，才能称为 Pi CUA 端到端接通。列出工具、构建通过或模型会写 JS 都不够。

## 未改动与待确认

目前没有启用 Pi CUA，没有修改 Pi/Paseo/Codex 配置、系统权限或正在运行的研究 agent。屏幕锁定是另一个运行条件问题，MCP 接通不能解锁机器。需要实施时，优先本地 extension 路线；只有发现现有 Pi UI/RPC 无法传递审批时才扩大到 Paseo adapter 修改。详细 Pi/Paseo 接入点见同目录 `pi-paseo-bridge.md`。
