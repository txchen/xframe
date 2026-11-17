# Pi / Paseo MCP 接入调查

2026-11-16，只读源码调查。未添加 MCP、修改配置、启动 UI 或重启 daemon。

## 结论

本机 **Pi 1.5.2 已原生支持 stdio / streamable HTTP MCP**，Paseo 0.15.4 也已经支持把 MCP 注入 Pi。工具注册不要求先修改 Pi/Paseo，但完整 CUA 接入还需要审批和宿主生命周期桥接（见下文后续核查）。当前研究 agent 的两个 MCP 配置文件均不存在：`~/.pi/agent/mcp.json` 和其 workspace 的 `.pi/mcp.json`；工具发现为空符合“未配置”这一事实。

最小方案是新增一条 Pi MCP 配置，传入正确 CUA server 启动命令与环境，再给模型正确的 CUA 初始化/安全使用指引。但这只能解决工具注册，不证明 Codex 的 bundled CUA runtime 能在 Pi 进程里独立工作：后者的 native pipe、身份/权限和 App 运行时要求应独立验证，不应伪造或复用不属于该会话的授权材料。

## 本机源码依据

以下路径均为已安装第一方发行文件，不是网络猜测。缩写：

- `PI=/Users/hibiki/.pi/agent/install/releases/1.5.2/node_modules/@earendil-works/pi-coding-agent`
- `PASEO=/Users/hibiki/.local/share/mise/installs/node/26/lib/node_modules/@getpaseo/cli/node_modules/@getpaseo/server`

### 配置与生命周期

Pi 的 `docs/mcp.md` 明确说明读取 `~/.pi/agent/mcp.json` 和受信项目 `.pi/mcp.json`，stdio 字段支持 command/args/env/cwd，timeout 默认 60 秒；配置外部变化后在交互会话 `/reload`。可以给小型工具集 `exposure: "direct"`，避免必须猜测搜索词。默认 codemode 曝露同样能通过 searchTools/ALL_TOOLS 找到，并不构成能力缺失。

`PI/dist/extensions/mcp/runtime.js:53` 的 `createDefaultTransport` 构造 `StdioTransport`，使用配置 command、args、cwd 和解析后的 env；相对 cwd 基于会话目录。`PI/dist/extensions/mcp/index.js:972` 注册 session_start，`:1115` 注册 session_shutdown；连接生命周期属于会话，不是每次工具调用新开一个进程。因此 persistent CUA REPL 在协议上有合适的承载方式。关闭 stdio server 会终止其进程组；必须检查 CUA server 是否将共享 native service 当作可终止子进程启动。

Pi 文档中的 `pi mcp list` 会**连接每个启用 server**，并不是纯读配置；本调查没有执行它，避免意外启动 CUA或其他工具。未来验收时可显式执行。

### 图片、工具说明与 codemode

`PI/dist/extensions/mcp/tools.js:161` 的 `convertMcpResult` 将 MCP content 转换为模型可见文本和图片，完整 CallToolResult（去掉顶层 `_meta`）放入 structuredContent 给 codemode。`:187` 的 `createMcpToolDefinition` 保留工具 description、schema、annotations，并调用 client.callTool。`runtime.js:316` 保存 MCP initialize 返回的 server instructions。

注意：server instructions 不会自动附加到每个工具 description；默认 codemode 路径要通过 `describeNamespace('mcp__<server>')` 获取。截图经 codemode 必须显式 `image(result.content[i])`，不能只把图片块 JSON 返回给模型；direct 曝露可减少这一误用。Pi 的 own docs/mcp.md 同样记录了这点。

Pi 输出文本超过 20 KB 会截中间并保留完整临时文件；CUA 的初始化文档较长，需要验证完整操作说明是否可读，不能只看到工具名就当集成完成。Pi drops 顶层 `_meta`；如 CUA 依赖某项元数据须另测，现有普通图片支持不能证明每个 Codex 专有图像 hint 都保留。

### Paseo 已有注入逻辑

`PASEO/dist/server/server/agent/providers/pi/agent.js`：

- `:279 toPiMcpConfig` 将 Paseo stdio 配置转换为 command/args/env；HTTP 为 url/headers。
- `:295 toPiBuiltinMcpServers` 做 server-name 和 SSE 检查。
- `:370 createPiPaseoExtensionFile` 生成临时扩展，`:428` 遍历注入项并调用 `pi.registerMcpServer(name, config)`。
- `:2107 createSession` 调 `prepareMcpInjection`，把生成扩展路径传给真实 Pi runtime。
- `:2335 prepareMcpInjection` 探测 builtin 或 legacy pi-mcp-adapter；builtin 分支直接注册，legacy 分支才用 `createPiMcpConfigFile` 合并临时文件。
- `:2349 detectMcpSupport` 检查 /mcp 命令来源。legacy adapter 优先；Pi 文档也警告安装另一个 /mcp 扩展会替换 builtin MCP。

当前 `toPiMcpConfig` 的转换只传上述窄字段，**不转发 cwd、timeout、description、exposure/toolExposure**。因此这次优先直接用 Pi 自己的 mcp.json，保留这些字段，无需先改 Paseo。如果未来要从 Paseo 统一管理 CUA server，这里及其共享 MCP config schema 是应检查/扩展的点，不能只在调用方塞额外字段就以为生效。

`PASEO/.../agent/runtime-mcp-config.js` 的 `withRuntimePaseoMcpServer` 只注入内部 paseo 编排 server 与既有 agent config，并没有导入父 Codex 的插件配置。跨 provider 创建子 agent 不会自动取得父会话 bundled computer-use 工具。

## 建议修改层次

1. **先验证协议注册**：为单独测试会话准备 `cua_repl` MCP entry；用绝对路径、正确 timeout、自身授权下的环境。默认 hidden，只让 js/js_reset direct；不要把所有 server 工具给模型。不要先把 Codex config.toml 整个复制过去。配置本身不等于完整可用。
2. **补使用说明**：独立 skill/上下文明确第一条 CUA 初始化调用、状态刷新、图片转发、工具名称、UI 确认边界、禁止并发操控同一桌面。
3. **只有真实 CUA 初始化失败时再定位 runtime bridge**：检查 native pipe、service 启动和身份要求；没有授权的身份/pipe 就不能通过简单传环境绕过。具体瓶颈由父调查覆盖。
4. **Paseo UI 配置支持属于后续可选工程**：若希望 GUI/profile 管理任意 MCP，需要补 config schema/传递字段、配置来源展示、生命周期和工具可用性检查。不是 Opus 模型能力修改，也不是当前必要前置。

## 最小验收矩阵

- 新 Pi 会话 tools/list 中有实际 CUA 工具；能读完整 instructions。
- 初始化并仅做允许的状态读取，确认无 native pipe/权限错误。
- 读取截图，证明图片到达模型而不是只剩 base64 文本。
- 连续两次调用使用同一个 REPL binding；reset 后按初始化说明重建。
- 在授权的无副作用测试 UI 中验证一次操作及 AX 回读。
- 会话结束清理自有进程，不能杀共享 CUA service；第二会话重开可用。
- 锁屏作为显式阻塞，不尝试解锁；只暴露工具不代表屏幕可用。
- 一个时刻一个 CUA 控制者；Pi 和父 Codex 不同时发输入。

## 官方来源

- [Pi 官方 MCP 文档](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/mcp.md)：原生配置与迁移入口。已与本机 1.5.2 文档和 runtime 实现交叉验证；未来 main 可能变化。
- [Pi 官方扩展文档](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/extensions.md)：registerMcpServer 扩展入口；本机对应 docs/extensions.md。
- [Paseo Pi provider 源码](https://github.com/getpaseo/paseo/blob/main/packages/server/src/server/agent/providers/pi/agent.ts)：本机 0.15.4 发行实现的源文件归属；以上行为以已安装 JS 为准。

没有验证 bundled CUA server 在 Pi 下的实际连接，也没有修改用户配置。以上结论是支持面与接入点确认，不是集成成功声明。

## 后续核查：审批与宿主 hook 是实际需要补的代码

父调查发现 CUA runtime 会用 `nodeRepl.createElicitation` 请求审批，并带 `codex_approval_kind`、persist 等语义。因此纯通用 MCP 注册不足以实现受控 CUA。

Pi builtin MCP 的 `runtime.js:281` 构造 McpClient 时仅传 name/version/requestTimeoutMs/roots，没有声明 elicitation capability，也没装 elicitation/create handler。`@earendil-works/pi-mcp/dist/client.js:89,92` 默认只注册 ping 和 roots/list；`:323 handleRequest` 对其他方法返回 methodNotFound。库本身有公开 `setRequestHandler(method, handler)`（`:160`），所以不是协议库完全不能处理，而是上层目前未接。

建议最小完整实现为一个 **Pi CUA 专用扩展**：自己持有 CUA MCP client，声明/实现所需 elicitation；只注册 js/js_reset 两个模型工具；把 CUA 宿主工具 turn_ended 留在扩展内部。该扩展可复用 pi-mcp 客户端，也可用标准 MCP SDK；不能在 handler 中无条件 accept，必须把请求动作/目标/范围传给实际用户审批，处理拒绝、取消和超时。持久授权必须按原请求语义和范围保存，不得把“上一次允许”扩大成所有桌面访问。对未知 codex_approval_kind 应拒绝或清楚报不支持，不能默默放行。

Paseo 现有 `providers/pi/agent.js:666–704` 能把 extension UI select/input/confirm 请求映射成用户问题和 permission 请求；`:740 buildExtensionUiQuestionPermission` 建立权限请求。可考虑通过 `ctx.ui.confirm/select` 承接审批，不需要为了这一步重写整个 Paseo。但其简单 UI 能否完整表达 CUA 的审批种类和 persist 选择，必须逐项验证；普通 tool_call 的布尔确认不能替代 CUA 内部逐操作审批。

生命周期应区别 Pi 的三种事件：`turn_end` 是每轮模型/工具回合，并不表示用户任务结束；`agent_end` 后还可能重试/压缩/继续；`agent_settled` 才是最终 idle。Pi docs/extensions.md:663–665 明确这一差异。将 CUA turn_ended 接到哪个事件须依据它真实契约，优先最终 settled/取消/会话关闭，而不是每次工具调用后 reset。需要扩展自有client句柄，因为隐藏工具不能由模型或 codemode 调用，且普通 ExtensionContext 没有 ToolContext 的 ctx.executeTool。关闭时清理自有 stdio 进程，不能停掉其他会话共享的桌面service。

这使建议分成两层：**配置能让工具出现；专用扩展/宿主适配才能补齐审批、只暴露允许工具和 turn cleanup**。二者不能混为“Pi 配上 MCP 就已经会用 CUA”。
