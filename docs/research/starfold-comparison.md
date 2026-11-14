# Starfold 对照研究

研究日期：2026-11-14。Starfold 固定提交 `cbc7e96d414173735f9e1f46ef88d07a8edbbfae`；xframe `810cb02f1973036da26acd18e9459ebe9e54481d`。源码静态研究，没有运行 Starfold、连接 Xbox 或进行延迟 A/B；不能从实现推断性能胜负。未改产品代码。

## 优先借鉴

### 1. 认证刷新作为请求层能力

Starfold [GSSVClient.swift](https://github.com/JarvanSun/Starfold/blob/cbc7e96d414173735f9e1f46ef88d07a8edbbfae/Packages/XboxKit/Sources/XboxKit/Streaming/GSSVClient.swift) 的 send 在 401/403 后要求刷新一次，再失败即返回错误；[XboxAccount.swift](https://github.com/JarvanSun/Starfold/blob/cbc7e96d414173735f9e1f46ef88d07a8edbbfae/Packages/XboxKit/Sources/XboxKit/Auth/XboxAccount.swift) 用 actor 管理账号，并以 refreshTask 合并同时发生的 Microsoft token 刷新。home/cloud token 分开管理。

xframe `Sources/XFrame/Cloud/CloudService.swift:78` 保存固定 token，request 在过期时抛 expired，没有该请求层刷新闭环。建议引入异步 token provider，并发共享刷新；保留 xframe 的可信 URL 校验、凭证轮转落盘失败传播、清理语义。不要机械地把每个 403 当成过期，也不要给不确定是否成功的创建会话请求添加无条件重试。Starfold 的 save 会记录并吞掉持久化错误，这部分不值得照搬。

验证：并发过期只刷新一次；第二次拒绝及时结束；取消和登出不会让旧账号结果回写；轮转落盘失败可见。

### 2. 更快发现信令就绪

[PollingBackoff.swift](https://github.com/JarvanSun/Starfold/blob/cbc7e96d414173735f9e1f46ef88d07a8edbbfae/Packages/XboxKit/Sources/XboxKit/Streaming/PollingBackoff.swift) 使用 100/250/500/1000ms 分段间隔；[GSSVSession.swift](https://github.com/JarvanSun/Starfold/blob/cbc7e96d414173735f9e1f46ef88d07a8edbbfae/Packages/XboxKit/Sources/XboxKit/Streaming/GSSVSession.swift) 以 ContinuousClock 限制等待，并区分排队、准备、失败。xframe `Sources/XFrame/Streaming/CloudSignaling.swift:57` 固定每秒轮询，共 30 次。可先只改 SDP/ICE 轮询策略，独立测量按下连接到首帧的分段耗时。潜在收益是减少等待下一次轮询的时间，不是降低稳态串流延迟。更频繁请求的负担必须计入；不要把这些常量当成普遍最优值。

### 3. 信令解析与失败分类

[SignalingAnswerParser.swift](https://github.com/JarvanSun/Starfold/blob/cbc7e96d414173735f9e1f46ef88d07a8edbbfae/Packages/XboxKit/Sources/XboxKit/Streaming/SignalingAnswerParser.swift) 同时接受字符串和对象形式 exchangeResponse，并处理外层 errorDetails、内层 status、协商 channel versions。xframe 目前只处理字符串 exchangeResponse，SDP 只返回 sdp。建议独立解析模块，先补响应形状和错误分类，再审计协商版本实际用途；仅记录版本不等于支持该版本。

[StreamFailureAdvice.swift](https://github.com/JarvanSun/Starfold/blob/cbc7e96d414173735f9e1f46ef88d07a8edbbfae/Packages/StarfoldShared/Sources/StarfoldShared/Features/Stream/Model/StreamFailureAdvice.swift) 把主机离线、未启用远程游玩、上次流尚未结束等转成行动提示，值得借鉴。但 HTTP 400 => needsGamePass 的映射过宽，不应移植。保留 xframe 对错误码长度、字符及敏感响应的限制。

### 4. 可注入 HTTP 和时间

[HTTPClient.swift](https://github.com/JarvanSun/Starfold/blob/cbc7e96d414173735f9e1f46ef88d07a8edbbfae/Packages/XboxKit/Sources/XboxKit/HTTP/HTTPClient.swift) 的 Transport 闭包和 XboxAccount 的 now 参数使授权失败、刷新、取消等可以离线验证。[GSSVClientTests.swift](https://github.com/JarvanSun/Starfold/blob/cbc7e96d414173735f9e1f46ef88d07a8edbbfae/Packages/XboxKit/Tests/XboxKitTests/Streaming/GSSVClientTests.swift) 包含 token 被拒绝后刷新并仅重试一次的测试。借鉴这类真实边界场景，不必为了相同目录结构而拆大量文件。

### 5. 多账号与平台扩展，按需求采用

[AccountStore.swift](https://github.com/JarvanSun/Starfold/blob/cbc7e96d414173735f9e1f46ef88d07a8edbbfae/Packages/XboxKit/Sources/XboxKit/Auth/AccountStore.swift) 按 xuid 保存账号，SecretStoring 隔离存储后端。适合未来多账号，不是当前必须做的重构；无需因此替换 xframe 当前文件凭证方案。Starfold 把 XboxKit、StreamKit、StarfoldShared 与平台入口分开，未来 iOS/tvOS 扩展时有参考价值。现在优先抽稳定的认证、解析和协议边界，避免整仓搬迁。

## 应保留 xframe 的边界

- xframe 的 `docs/adr/0002-require-local-console-media-path.md` 明确只允许可验证的 LAN 媒体/输入路径。通用 Remote Play 的连通性目标不能替代这个条件。
- Starfold GSSVSession.stop 在 macOS 用 try? 吞 DELETE 失败；xframe `CloudService.end` 只把 404/410 当作已结束，其他失败向上传递。保留后者及 CONTEXT.md 的远端清理确认要求。
- 功能存在不代表优于现有实现；MetalFX、锐化、统计、手柄都必须先对照已有能力。
- 直接复用源码时查看仓库 LICENSE 和 THIRD_PARTY_NOTICES 并保留适用声明；本次没有复制产品源码。

## 音视频专项

见 [音视频与输入审读](starfold-media.md)，其中补充具体实现和取舍。
