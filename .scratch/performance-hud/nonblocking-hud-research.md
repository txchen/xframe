# 不让 HUD 拖慢视频：线程、锁与显示路径研究

## 结论

**可以做得更好，而且应优先消除诊断对播放的同步依赖，而不是继续用降低 HUD 刷新频率来掩盖耦合。** 推荐两步：

1. 统计汇总、格式化和 HUD 更新完全移出视频绘制回调；缩短采样锁，避免后台统计反过来阻塞视频队列。
2. 原型验证独立渲染线程，以 `CAMetalLayer` + 绑定独立 RunLoop 的 `CAMetalDisplayLink` 驱动。主线程负责 AppKit UI，渲染线程负责视频帧消费、Metal 编码与提交。

HUD 可以继续使用小型 AppKit 叠层。不是所有 UI 都必须离开主线程，而是**视频不应等待 HUD 的计算、排版或主线程回调**。Apple HUD 是可选图形诊断工具，不是线程隔离的替代方案。

不能承诺物理上的零开销：CPU、GPU、内存带宽和系统合成仍共享。可以明确要求“无同步 HUD 依赖、工作量有上限、过载优先丢弃诊断更新，并通过开关 HUD 的配对实测证明没有有意义的播放退化”。这是建议的工程目标，不是已经达成的结论。

本次完成代码审计、Apple 官方文档及示例源码研究；未修改产品代码、运行性能实验或重启应用。当前工具没有后台代理能力，研究直接完成。

## 1. 当前代码中的具体耦合

### A. HUD 工作直接在绘制回调前半段执行

`MetalRenderer` 整体标注 `@MainActor`。`draw(in:)` 每秒先执行：

```text
draw(in:)
  → source.snapshot()
  → report?(stats)
      → AppDelegate 中的 diagnostics.update(...)
      → PerformanceHUDView.refresh()
      → 格式化统计 / NSTextField.stringValue 更新
  → nextFrame(at:)
  → drawable 获取 / 编码 / 提交
```

因此统计、字符串生成及触发 UI 更新，直接处在该次视频提交之前。即使文字实际布局稍后执行，它也共享主线程。`scalingReport` 同样从绘制路径同步更新 HUD 和设置面板。来源：[C1][C2][C3]。

### B. Hidden 并未关闭统计汇总

`PerformanceHUDView.refresh()` 在 Hidden 时跳过格式化与文本更新，但 `draw(in:)` 依然每秒调用 `source.snapshot()`。不能将“面板隐藏”当作“没有 HUD 汇总开销”的基线。[C1][C3]

采样与导出可以独立于显示保留；这里应关闭的是不必要的展示汇总，不是为了让 Hidden 数字好看而关闭所有诊断。

### C. 排序发生在媒体使用的锁内

`PlaybackPerformance.snapshot()` 持有自己的 `NSLock`，对多个最多 256 个样本的数组排序、求和并构造分布。

更关键的是，`LiveVideo.snapshot()` 在持有视频帧队列的锁时调用上述函数；`LocalVideo.snapshot()` 在持有生产/消费使用的 `NSCondition` 时调用它。其他帧到达、取帧、present 回调和采样也需要相关锁。[C4][C5][C6][C7]

**只把 `snapshot()` 丢进后台 Task 不够**：后台汇总仍可能持有视频需要的锁，造成阻塞或优先级反转。当前审计证明存在这条等待路径，但没有新实测量化它的毫秒数，不能将其说成已确认的现存卡顿主因。

### D. 既往问题和当前风险要分开

此前的严重掉帧有手柄计数引发游戏库 SwiftUI 更新的证据。组合修复后，三个 HUD 模式的短时实验已没有原先约 7 skips/s 的严重退化。不能声称当前每次开 HUD 都在严重掉帧；也不能用那些短窗口结果证明当前架构没有争用。[C8]

## 2. Apple 官方支持什么实现

### 独立线程渲染是明确可行的方案

Apple 的 **Achieving smooth frame rates with a Metal display link** 示例包含 `RENDER_ON_MAIN_THREAD` 编译开关。下载源码中：

- `Shared/GameConfig.h` 说明关闭此选项后渲染发生在后台线程；示例默认值仍是 1。
- `Shared/GameView.m` 创建专用 `NSThread`，在 `runThread` 中运行独立 RunLoop。
- `startMetalLink` 将 `CAMetalDisplayLink` 加入 **currentRunLoop**；后台选项下回调就在渲染线程执行。
- resize 与 render 需要同步，示例使用 `@synchronized(_metalLayer)`。

这证明 Apple 提供此架构示例，不是必须把所有绘制留在主线程。[A1][A2]

但不要机械照搬示例的锁和默认参数：它在 resize 与整段 render 外围共享锁，不能据此宣称完全无 UI 等待；示例的 120 Hz 和 `preferredFrameLatency = 2` 也不是 XFrame 应照抄的低延迟配置。我们需要明确资源所有权、缩短跨线程临界区，并单独验证 resize/fullscreen。

### Metal 呈现可以不绑定 UI transaction

`CAMetalLayer.presentsWithTransaction` 默认是 false，Metal 呈现异步于 Core Animation transaction。设为 true 则要求同步 transaction 的特殊提交顺序。[A3]

因此诊断文字与视频没有逐帧原子同步需求时，不应为了让它们同帧更新而把视频绑到 UI transaction；诊断内容晚一点更新是可以接受的。窗口尺寸变化等几何同步另行处理。

`nextDrawable()` 可能等待可用 drawable，官方描述默认可能等至一秒后超时。[A4] 这也是避免在 UI 主线程进行阻塞式 drawable 获取的理由之一；独立线程不意味着 drawable 等待消失。

### 不应把现有 MTKView delegate 简单扔进 Task.detached

当前 renderer 直接读取 `MTKView`、窗口全屏状态，持有可变 source、纹理、scaler 等资源，并在设置回调里被直接修改。[C1][C2] 去掉 `@MainActor` 或添加 `@unchecked Sendable` 不等于建立了安全的线程模型。建议把 AppKit view 留在主线程，剥离不依赖 view 的渲染实现，并给它不可变的尺寸/配置快照。

## 3. 推荐的具体实现

```text
解码/网络线程 ── 有界视频队列 ──→ 专用渲染线程 ──→ Metal / 呈现
      │                              │
      └──── 有界、短临界区采样 ───────┘
                        ↓
                诊断后台队列
         复制样本 → 解锁 → 汇总/格式化
                        ↓
                仅保留最新显示快照
                        ↓
               主线程固定布局 HUD
```

### 第一阶段：独立诊断模块，不改变当前显示驱动

外部 Interface 保持小：接入/结束一次 source 会话、选择显示模式、获取或订阅最新快照。内部隐藏采样窗口、汇总调度、合并更新和取消逻辑，不让 renderer 知道 HUD 的布局或文本。

- 从 `draw(in:)` 移除周期 `snapshot()` / `report` 和 HUD 更新；保留廉价、明确的终止状态读取或生命周期通知。不能把原本靠 stats.state 暂停绘制的行为一起删掉。
- source 锁下只复制媒体计数/队列状态，释放后再取得计时快照；不嵌套持有媒体锁做统计。
- performance 锁下只复制有界原始数据，释放后排序、计算 p95。注意 Swift Array 写时复制：浅拷贝可能将复制成本转移给下次写入；实施时评估固定容量存储或明确的有界复制，不假定 copy 自动免费。
- 单个后台汇总任务运行，最多一个待应用快照。慢时合并并覆盖旧快照，不创建无限 Task/主线程回调队列；界面卡住后不补播旧的 HUD 更新。
- generation 标识阻止旧 source 的延迟汇总覆盖新会话。停止和 source 切换不等待 HUD 完成。
- Compact 只取需要的数据，不为几行 FPS/Mbps 计算所有阶段的 p95；Detailed 才汇总完整分布。Hidden 停止展示专用汇总，必要的基础采样/故障诊断仍按独立策略保留。
- HUD 用固定行数/预留宽度减少尺寸变化，数值不变不赋值。只让 HUD 自身更新，不向游戏库可观察状态广播遥测。
- 更新频率是体验参数，不是隔离措施。可先实验文字 4 Hz；曲线按时间戳采样、独立更新，不能用插值伪造新的测量。是否采用更高频率须按预算验收。

此阶段能消除最直接的耦合和持锁重计算，但 **仍不能隔离任意主线程 UI 卡顿对当前 renderer 的影响**。

### 第二阶段：专用渲染线程原型

- 主线程拥有 NSView/NSWindow、输入和 UI；专用渲染线程独占纹理 cache、render pass、scaler 和 command submission。
- 使用独立 RunLoop 驱动的 `CAMetalDisplayLink` 与 `CAMetalLayer`；不要将回调重新 dispatch 到主线程，不要让主线程逐帧向 renderer 派任务。
- 跨线程只传有限的配置/尺寸/可见性快照和有界视频帧；安全安排 layer 修改及 resize 时序，不将 AppKit 对象任意跨线程读取。
- 渲染线程不等待 HUD、字符串生成或 UI 回调；状态变化异步、合并报告。诊断拥塞丢诊断更新，不反压视频。
- 保留当前非阻塞 in-flight 限制、实际 presented-time 计数、纹理/scaler 生命周期、两帧队列及 freshness 策略，避免一次改变多个延迟变量。
- 启停、跨屏、全屏、resize、occlusion、sleep/wake 和旧 GPU 回调必须测试；独立线程的停止要显式唤醒 RunLoop，不能依赖主线程每帧协助退出。

**重要历史约束：** 本项目之前 CAMetalDisplayLink 实验曾把 local presentation mean 增至约 57–73 ms，已被拒绝。[C9] 那不是所有独立线程实现都失败的证明，但足以禁止“换 API 就会更快”的假设。新原型必须与当前实现配对比较，而且同时检查输出帧率和延迟；增大缓冲来掩盖抖动不是成功。

## 4. 要不要自己用 Metal 画 HUD

| 路径 | 判断 |
| --- | --- |
| 只降低 NSTextField 刷新频率 | 短期止痛，不消除依赖，不作为最终方案 |
| 后台汇总 + 主线程轻量 HUD | 推荐第一步，投入小；配合独立渲染线程后可隔离主线程排版 |
| 后台栅格化 HUD，发布缓存图像给叠层 | 文本布局仍有实测成本时再做；减少主线程工作，但仍有合成/上传成本 |
| HUD 绘成纹理或字形，在视频 pass 末尾叠加 | 能消除 AppKit 文本排版依赖，但把 GPU 开销直接加入视频帧；必须仅使用已就绪纹理，绝不等待新 HUD，且增加字体、DPI、可访问性等维护成本。不是优先项 |
| 独立 Metal HUD surface / 独立进程 | 仍共享 GPU/系统合成，增加同步/窗口/IPC 复杂度；目前没有需要此复杂度的证据 |
| 全换成 Apple HUD | 不能显示全部业务指标，也无已查到的零开销/线程隔离保证；不解决我们自身 renderer 的主线程依赖。[C10] |

推荐先让渲染和诊断的调度正确，再决定 HUD 绘制技术。不要为了“使用 GPU”而把文字生成变成视频必须等待的 GPU 工作。

## 5. 怎么证明没有因为看 HUD 而卡

### 逻辑测试

- 人为阻塞汇总器 100–500 ms：视频队列消费与呈现路径不得等汇总器结束。
- HUD 接收者停止消费：待更新数量不增长，恢复后只拿最新快照。
- 确认排序/格式化不在媒体或采样锁内；增加并发生产/取帧/快照测试，测试通过不等于实时性能已经达标。
- Hidden 无展示汇总；Compact 不计算无用的 Detailed 分布。
- 停止/切换 source 后旧快照和回调不污染新会话；原有 EOF、失败暂停、GPU/present 顺序测试保留。

### 实机性能实验

1. 先固定本地 30/60 fps 素材、输出分辨率、刷新率、pacing、缩放模式。重复并交错测试 Hidden / Compact / Detailed；Apple HUD 单独作为可选对照，不和待测变量混为一组。
2. 分开做两个对照：相同基础采样下仅开关显示；相同显示下比较不同统计实现。避免把 Hidden 关闭所有采样造成的差距误认为文本开销。
3. 通过不依赖屏幕读数的有界数据记录 presented intervals、>1.5 刷新周期的间隔、skips、arrival-to-present 的 p50/p95/p99、汇总耗时与锁等待、CPU/GPU 时间。p99 需足够长区间，不能将当前 256 样本 p95 假装成长期 p99。
4. Time Profiler / System Trace 验证线程与等待关系；用 signpost 标注 snapshot、format、apply、render；验证后去掉或关闭高开销临时追踪。
5. 开 Detailed 时持续滚动游戏库、快速改变 HUD 数值、切换预设；独立线程原型中人工短暂停顿主线程，核对渲染回调/提交是否持续，并测实际呈现。提交持续不等于系统合成保证上屏。
6. 覆盖 Original / Integer Scaling / MetalFX、60/120 Hz、窗口/全屏、resize/跨屏和长时间运行。最后再测真实串流与手柄，不把网络波动当 HUD 成本。

**建议预先约定的候选验收预算（不是既有实测结果）：** 稳态每种配置至少 3 次交错的 120 秒区间；Detailed 对 Hidden 的额外 skip rate 不超过 0.1/s、presentation p95 增量不超过 1 ms，同时检查长尾间隔分布和可见卡顿。如基线波动大于预算，应延长并改进配对实验，不得直接宣布通过。此前 <=1 skip/s 的绝对门槛不足以单独证明 HUD 无退化。

失败时降低/丢弃 HUD 更新、缩减统计，绝不降低视频目标 FPS、手柄发送频率，或扩大视频缓冲来达到表面通过。

## 来源

### Apple 一手资料

- [A1] [Achieving smooth frame rates with a Metal display link](https://developer.apple.com/documentation/metal/achieving-smooth-frame-rates-with-a-metal-display-link)，本次读取[官方示例 ZIP](https://docs-assets.developer.apple.com/published/37aa0e2a751f/AchievingSmoothFrameRatesWithMetalsDisplayLink.zip) 的 `Shared/GameConfig.h`、`Shared/GameView.m`。研究临时副本位于 `/tmp/xframe-displaylink-research/`，不是仓库运行依赖。
- [A2] [CAMetalDisplayLink](https://developer.apple.com/documentation/quartzcore/cametaldisplaylink)、[add(to:forMode:)](https://developer.apple.com/documentation/quartzcore/cametaldisplaylink/add(to:formode:))。
- [A3] [CAMetalLayer.presentsWithTransaction](https://developer.apple.com/documentation/quartzcore/cametallayer/presentswithtransaction)。
- [A4] [CAMetalLayer.nextDrawable()](https://developer.apple.com/documentation/quartzcore/cametallayer/nextdrawable())。
- [A5] [Creating a custom Metal view](https://developer.apple.com/documentation/metal/creating-a-custom-metal-view)：较早示例同样提供主/后台渲染选择，但包含历史 CVDisplayLink 时代说明，不据此判断现代 macOS API 的可用性。

### 本仓库证据

- [C1] [`MetalRenderer.swift`](../../Sources/XFrame/MetalRenderer.swift)：`@MainActor`、`draw(in:)`、同步 report/scalingReport。
- [C2] [`XFrameApp.swift`](../../Sources/XFrame/XFrameApp.swift)：report closures、HUD 约束、设置与 renderer 的直接交互。
- [C3] [`PerformanceHUD.swift`](../../Sources/XFrame/PerformanceHUD.swift)：refresh、Hidden guard、文本格式化。
- [C4] [`PlaybackPerformance.swift`](../../Sources/XFrame/PlaybackPerformance.swift)：锁内 Window.summary 排序。
- [C5] [`LiveVideo.swift`](../../Sources/XFrame/Streaming/LiveVideo.swift)：snapshot/nextFrame/renderFrame 共享锁。
- [C6] [`LocalVideo.swift`](../../Sources/XFrame/LocalVideo.swift)：snapshot/nextFrame 共享 condition。
- [C7] [`FramePresentation.swift`](../../Sources/XFrame/FramePresentation.swift)：GPU 和呈现回调的采样。
- [C8] [既往 pacing 调查](../playback-performance/pacing-investigation.md)。
- [C9] [既往显示驱动实验与被拒绝方案](../playback-performance/latency-optimization-validation.md)。
- [C10] [Metal HUD 能力与限制研究](metal-hud-research.md)，含 Apple 原始文档链接。
