# Pi CUA smoke 验收记录

结果：**被阻断，未通过**。CUA 工具从未加载，所以没有调用任何 CUA，也没有截图或点击。

## 观察到的情况
- `searchTools("mcp__cua_repl__js")` 和 `ALL_TOOLS` 里都没有 `mcp__cua_repl__js` 或 `mcp__cua_repl__js_reset`，任何名称含 `cua` 的工具都没有。
- `.pi/extensions/cua.ts` 存在，是一个符号链接，指向 `../../../extension/index.ts`。
- 扩展只在 `session_start` 里通过 `pi.registerTool` 注册工具，注册的前提是 CUA MCP 能连上并返回 `js` 和 `js_reset`。连接失败时，扩展只会调用 `ctx.ui.notify("CUA unavailable: …")`。这条通知只出现在 UI 里，在 agent 这边看不到，会话 jsonl 里也没有记录。
- 依赖文件都存在：CUA 启动清单 `~/.codex/plugins/cache/openai-bundled/unified-computer-use/26.1027.51404/.mcp.json`，以及 `pi-mcp` 的 `dist/index.js`。
- `~/.pi/agent` 下没有 `trust.json`，`settings.json` 里也没有 `defaultProjectTrust`。按 Pi 的文档，项目内的 `.pi/extensions` 要等项目被信任后才会加载。

## 可能原因（未能确认）
1. 项目没有被信任，所以扩展没有加载；或者
2. 扩展加载了，但连接 CUA 失败了（例如 nativepipe 或 `BROWSER_USE_ACCESS_*` 身份问题，或者锁屏）。错误信息只在 UI 通知里。

## 本次没有做的事
- 没有调用 `cua.getState()`、`getApp`、`getScreenshot`，没有点击也没有按 Esc，所以没有截图或菜单的证据。
- 没有自己启动 CUA server 绕过扩展，没有改扩展代码，没有替用户批准信任或权限，没有改系统设置，没有用 bash、osascript 或 CGEvent 代替。

## 复查（收到 `/reload` 消息后）
- `/reload` 是以 Paseo agent 消息的形式送达的，内容是普通文本，Pi 没有把它当作斜杠命令执行。会话记录里看不到 reload 或 session_start 的迹象。
- 复查后 `ALL_TOOLS` 和 `searchTools` 仍然没有 `mcp__cua_repl__js`，状态还是被阻断。

## 需要用户做的
在 Pi UI 里查看 `CUA unavailable: …` 通知，或者是否有项目信任提示。由用户自己决定是否信任项目，然后直接在 Pi TUI 输入框里执行 `/reload`（不要通过 agent 消息发送），再重新跑这个 smoke。
