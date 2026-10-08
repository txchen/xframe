# Metal Performance HUD：是否替换 XFrame 性能监控器

## 结论

建议 **保留 XFrame 串流监控和采样，新增可选 Apple Metal HUD 图形诊断模式**，而不是整体迁移。Apple HUD 是 Metal runtime 提供的图形诊断叠层，不是可以任意填入业务指标的通用 HUD UI 框架；它也不是 Metal Performance Shaders（MPS）。官方公开的配置接口提供内置指标选择，没有在本次查阅的文档中发现注册任意自定义串流指标或读取完整结构化实时指标的 API。[1][2]

本次为官方资料及当前代码审计，未启用 HUD、重启应用或开始游戏会话；无实测性能开销和视觉兼容性结论。当前工具没有后台代理能力，研究直接完成。

## 它能带来什么

- 本地 drawable 呈现 FPS、帧间隔曲线/直方图、GPU 时间、present delay、进程/Metal 内存、热状态、屏幕刷新率和 Game Mode 信息。[1][3]
- MetalFX 使用时可显示缩放方式、输入/输出分辨率，以及适用时的插帧状态；不能因此推断 VideoToolbox 或自研插帧也会被识别。[3]
- 当前文档支持位置、透明度、缩放、指标选择、配置导出，macOS 菜单和三击 HUD 打开配置面板。[2]
- 可记录逐帧数据；当前报告功能支持 5 秒至 30 分钟区间，包含 frame interval 分布、1% low、指标汇总等。报告不是现有串流诊断导出的等价替代。[1][4]
- 增强 encoder 计时可显示 GPU timeline 和最耗 GPU 的带标签 command buffer / encoder，有助于分析颜色转换、缩放、锐化等本地图形处理。[1][3]

## 对照我们现有功能

| 需求 | Apple HUD 能否替代 | 处理建议 |
| --- | --- | --- |
| 本地输出 FPS、frame pacing 可视化 | 有重叠，但统计口径不同 | 用于交叉验证；不要删除现有 OUT 计数 |
| GPU 时间、图形内存、图形诊断曲线 | 擅长 | 优先利用 Apple HUD，而非重复开发完整 GPU 面板 |
| STREAM 解码 FPS、接收 Mbps、HQ/SQ requested | 不提供这些串流业务指标 | 保留 |
| RTT、jitter buffer、RTP loss、NACK | 不提供 | 保留 |
| decode / frame wait / GPU queue / display wait 分段分布 | 只有部分图形侧重叠 | 保留流水线采样 |
| inbox/renderer 跳帧、drawable miss、解码错误/IDR/恢复 | 无法等价替代 | 保留 |
| 连接恢复提示、输入设备、音量、缩放 fallback | 不提供业务状态 UI | 保留 |
| 统一串流诊断导出和回归断言 | Apple 图形日志/报告覆盖不同 | 保留，按需要附加 Apple 报告 |

现有实现证据：[5][6][7]。因此，即使改变界面，也不应把 `PlaybackPerformance` 当作可删除的重复实现。

## 关键口径：它测的不是远端游戏 FPS

Apple FPS 是过去 120 帧的滚动平均；frame interval 基于相邻 drawable 的 on-glass 时间。GPU 时间依据 Metal command buffer 的 GPU 起止时间；present delay 从调用 `presentDrawable` 到画面上屏。[3]

XFrame 是接收并显示远端视频，不运行远端游戏引擎。Apple HUD 的 60 fps 不证明远端游戏有 60 张独立图像，也不说明网络稳定、解码无丢帧或输入延迟很低。Apple 的 present delay 不能改名为“串流延迟”或 controller-to-photon 延迟。这些是由指标定义和客户端架构推导出的边界。[3][5][7]

我们的 live STREAM / OUT 使用最近 2 秒事件计数，阶段统计使用最近 256 个有效样本；只有待呈现视频帧才绑定对应 `FramePresentation`。Apple 观察 layer 呈现，重绘、多个 layer、统计窗口等都可能造成数字差异。30 fps 时 120 帧约为 4 秒，不等于我们的 2 秒窗口。[5][6][7]

## 接入可行性与限制

### 已经使用 Metal，不需要渲染架构迁移

`MetalRenderer` 已实现 `MTKViewDelegate`、提交 command buffer 并 present drawable。[7] 官方支持启动时 `MTL_HUD_ENABLED=1`，也支持 Xcode Scheme → Run → Diagnostics → Show Graphics Overview。[1] 因此第一步可以零产品代码验证，不应为启用 HUD 改写 renderer。

对于正式可选开关，公开接口是 `CAMetalLayer.developerHUDProperties`。当前文档列出 `mode: default/main/disabled`、logging 和位置等配置。多 layer 时应明确播放 layer 为 main，因为部分 GPU 指标依据 main layer 的呈现区间计算。[2]

本机 SDK `QuartzCore.framework/Headers/CAMetalLayer.h` 声明该属性从 macOS 13.0 可用；项目 `Package.swift` 当前最低版本为 macOS 27.0，因此基础属性不是本项目部署门槛。不过基础属性 availability 不证明最新文档中的每个菜单、报告或配置项在所有旧系统都可用；实际支持仍需目标系统验证。

文档中的 Info.plist / UserDefaults key 在当前文章与历史官方讲解间存在大小写/拼写差异；本次建议优先采用明确的环境变量和公开 layer API，不把未经运行验证的 defaults 写法当产品方案。[1][8]

### 重要：encoder timing 与现有 counter 使用的限制

Apple 明确说明：增强 encoder GPU time tracking 仅在应用不使用 Metal counter sample buffer 时可用，并可能增加 HUD CPU 成本。[1]

XFrame MetalFX 路径已经在 render pass 的 `sampleBufferAttachments` 上绑定 counter，读取 scaler GPU span。[7][9] 因此不能保证打开 `MTL_HUD_ENCODER_TIMING_ENABLED=1` 后，两套计时可以同时工作。建议：

1. 第一轮只启用基础 HUD，不启用增强 encoder timing。
2. 如需 GPU timeline，单独实验停用自有 scaler counter 后的兼容性；不要默默丢失原有诊断。
3. 需要 Top Labeled Encoders 时，为相关 command buffer / encoder 增加有意义的 label；当前渲染路径没有这些显式 label。[7]

### 性能和产品交互都要验证

没有证据支持“换成 Apple HUD 就一定更快”。我们的 HUD 已经是 AppKit 文本叠层，hidden 跳过文本刷新，并且此前降低 UI 更新频率已经改善 frame pacing；问题不等于自绘 HUD 本身必然昂贵。[5][10]

Apple HUD 的菜单/三击交互与现有 click-through、右键设置、手柄操作不是同一套体验。[2][5] 不建议让默认用户承担两个重叠大面板；默认继续 Compact，Apple HUD 放在高级图形诊断入口，可临时隐藏自有 Detailed，但保留重要连接状态。

## 建议验证顺序（尚未实施）

1. 用已有本地视频启动基础 HUD，验证同一播放 layer 的显示、全屏、窗口缩放、位置和开关；不要用全局 defaults 影响其他 Metal 应用。
2. 同一输入、分辨率、pacing 和缩放模式下，对比 HUD 全关 / 仅 XFrame / 仅 Apple / 两者并开。
3. 记录 OUT、跳帧率、presentation p95、GPU 时间、CPU 和内存；分别覆盖 Original、Integer Scaling、MetalFX，避免把不同负载当 HUD 开销。
4. 对比 Apple 与 XFrame 计数，解释窗口及重绘差异；串流时另外核对 STREAM、网络和解码指标。
5. 再验证 layer API 的运行时开启/关闭及 encoder counter 限制。只有确认收益后，再决定削减哪些重复图形 UI；保留串流采样、导出及其测试。

**建议决策：采用为补充工具，暂不迁移现有监控器。** 如果主要诉求是更漂亮的曲线和更完整的 GPU 信息，Apple HUD 很值得加；如果诉求是诊断“云游戏为什么卡/糊/延迟高”，我们自己的监控仍然是主体。

## 来源

Apple 一手资料（本次实际读取其官方 DocC 内容）：

1. [Monitoring your Metal app’s graphics performance](https://developer.apple.com/documentation/xcode/monitoring-your-metal-apps-graphics-performance)
2. [Customizing the Metal Performance HUD](https://developer.apple.com/documentation/xcode/customizing-metal-performance-hud)
3. [Understanding the Metal Performance HUD metrics](https://developer.apple.com/documentation/xcode/understanding-metal-performance-hud-metrics)
4. [Generating performance reports with the Metal Performance HUD](https://developer.apple.com/documentation/xcode/generating-performance-reports-with-metal-performance-hud)
5. [`PerformanceHUD.swift`](../../Sources/XFrame/PerformanceHUD.swift)
6. [`PlaybackPerformance.swift`](../../Sources/XFrame/PlaybackPerformance.swift)、[`SlidingFrameRate.swift`](../../Sources/XFrame/SlidingFrameRate.swift)
7. [`MetalRenderer.swift`](../../Sources/XFrame/MetalRenderer.swift)
8. [Apple Tech Talk: Discover the Metal Performance HUD](https://developer.apple.com/videos/play/tech-talks/110339/)
9. [`SpatialUpscaler.swift`](../../Sources/XFrame/SpatialUpscaler.swift)
10. [此前 frame pacing 调查与实测](../playback-performance/issues/01-stream-output-frame-gap.md)
