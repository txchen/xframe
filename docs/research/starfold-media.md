# Starfold 音视频与输入源码对照

审读版本：Starfold `cbc7e96d414173735f9e1f46ef88d07a8edbbfae`；对照当前 xframe 工作树。仅静态源码审查，未构建、运行或实测延迟、画质、音频声道。以下优先级是工程判断，不是性能测量。

## 最值得借鉴：输入恢复时必须先释放旧动作

Starfold 的 `GatedGamepadPolicy` 在播放开关切换时保存当前按住的输入，先向所有来源输出中立状态、清除待发送输入；恢复后，被保存的按钮、摇杆、扳机必须各自回到释放区才允许重新输入。摇杆和扳机阈值为 0.1。这解决“按着 A 关闭菜单，A 同时打到游戏里”和恢复焦点时旧摇杆继续生效的问题。[实现](https://github.com/JarvanSun/Starfold/blob/cbc7e96d414173735f9e1f46ef88d07a8edbbfae/Packages/StreamKit/Sources/StreamKit/Input/GatedGamepadPolicy.swift#L26-L112)

xframe `Sources/XFrame/Streaming/InputOwnership.swift:9` 已有重置和新活动抢占机制，`CloudVideoConnection.swift:65` 会释放输入并重置 ownership；但所有权切换与逐键等待释放是不同问题。尤其 `CloudVideoConnection.swift:79` 在禁用键盘时可以直接继续处理手柄。建议先复现菜单关闭、焦点恢复、手柄重连时的旧输入，再引入独立的 release barrier，并借鉴 Starfold 的 `GatedGamepadPolicyTests.swift` 行为测试。不应因此重写 xframe 已有的所有权模型。

## 可实验：根据 RTP 时间和到达抖动调节展示时间

`FramePacer` 用 90 kHz RTP 时钟恢复相对采集时间、处理 UInt32 回绕；十秒滚动最小 transit 估计基线，最近数秒每秒最坏迟到值决定展示缓冲，增加快、下降慢。低延迟模式限制为 4–40 ms，标准为 8–120 ms。这些是代码配置，不能解释成实测端到端延迟。[实现](https://github.com/JarvanSun/Starfold/blob/cbc7e96d414173735f9e1f46ef88d07a8edbbfae/Packages/StreamKit/Sources/StreamKit/Rendering/FramePacer.swift#L8-L161)

xframe `Sources/XFrame/PlaybackPacing.swift:4` 的 balanced/lowLatency 主要区分容量 2/1，适合低积压，但不等于主动按 RTP 时间均匀显示。可以借鉴纯函数算法和 `FramePacerTests.swift`，做独立可开关实验。必须以真实网络突发抖动下的帧间隔、晚帧数和操作延迟共同评估；额外缓冲可能让画面更平稳却让操作更迟。

## 平台展示与画中画架构可参考，不宜整套替换

Starfold 用 `AVSampleBufferDisplayLayer` / `AVSampleBufferVideoRenderer`，以 host clock timebase 和显式 PTS 展示。不开增强时直接交给系统；开 MetalFX、锐化或 HDR 输出时先处理到 pixel buffer，再交给同一 presenter。适合统一正常播放与系统视频展示集成。[SystemVideoPresenter](https://github.com/JarvanSun/Starfold/blob/cbc7e96d414173735f9e1f46ef88d07a8edbbfae/Packages/StreamKit/Sources/StreamKit/Rendering/SystemVideoPresenter.swift#L23-L111)、[StreamRenderer](https://github.com/JarvanSun/Starfold/blob/cbc7e96d414173735f9e1f46ef88d07a8edbbfae/Packages/StreamKit/Sources/StreamKit/Rendering/StreamRenderer.swift#L154-L198)

但其增强路径同步 `commands.waitUntilCompleted()`，待处理队列允许六帧。不能凭“native”或“系统 presenter”就判定比我们的 Metal drawable 路径更低延迟。[GPU 等待](https://github.com/JarvanSun/Starfold/blob/cbc7e96d414173735f9e1f46ef88d07a8edbbfae/Packages/StreamKit/Sources/StreamKit/Rendering/FrameEnhancer.swift#L115-L116)、[队列](https://github.com/JarvanSun/Starfold/blob/cbc7e96d414173735f9e1f46ef88d07a8edbbfae/Packages/StreamKit/Sources/StreamKit/Rendering/StreamRenderer.swift#L111-L127)。xframe `MetalRenderer.swift:239` 用 drawable 实际 presented handler 记时；Starfold `StreamRenderer.swift:172` 把计划 presentAt 用来计算 displayLatency，属于预计展示延迟，不是屏幕实际呈现测量。应保留我们的测量边界。

## 色彩格式扩展值得学，但 HDR 功能名需要谨慎理解

Starfold 的 `VideoColorConversion` 根据 pixel buffer 格式和附件处理 full/video range、8/10 bit、BT.601/709/2020，并有独立色彩测试。xframe `MetalRenderer.swift:274` 当前明确限定 video-range NV12 和 SDR BT.601/709。这是未来扩展输入格式时可以借鉴的可测试模块，不是当前已证明的画质缺陷。[色彩转换](https://github.com/JarvanSun/Starfold/blob/cbc7e96d414173735f9e1f46ef88d07a8edbbfae/Packages/StreamKit/Sources/StreamKit/Rendering/VideoColorConversion.swift#L21-L99)

它的 `streamToneMapPQFragment` 把输入 RGB 以 2.4 gamma 转线性，按亮度人为提高高光，再编码 BT.2020/PQ。该路径是 SDR 风格输入到 HDR 输出的增强，不能称为恢复原始游戏 HDR 信息；也不能仅从色彩模块支持 10-bit 就宣称整个串流已支持真实 HDR。[shader](https://github.com/JarvanSun/Starfold/blob/cbc7e96d414173735f9e1f46ef88d07a8edbbfae/Packages/StreamKit/Sources/StreamKit/Rendering/StreamShaders.metal#L48-L66)

## 音频：有明确需求后再引入自定义设备

Starfold `StereoPlayout` 从 LiveKit WebRTC playout block 拉取 48 kHz、交错 Int16 双声道，接到 AVAudioSourceNode，同时记录音频 meter。xframe `CloudAudioPlayback.swift:19` 则把解码、jitter buffer 和原生输出交给 WebRTC，只管音量/静音/生命周期。前者适合需要明确控制声道、路由或音频统计的场景；后者代码少、维护面小。没有声道或设备切换问题证据时，不建议为了对齐功能而替换音频后端。[StereoPlayout](https://github.com/JarvanSun/Starfold/blob/cbc7e96d414173735f9e1f46ef88d07a8edbbfae/Packages/StreamKit/Sources/StreamKit/Audio/StereoPlayout.swift#L11-L54)

建议顺序：输入释放屏障的复现与小范围补强 → RTP pacing 可控实验 → 有产品需求时做系统 presenter/PiP → 实际需要新格式时扩展色彩 → 音频路由按问题驱动。MetalFX、锐化和现有手柄所有权本身不是 xframe 缺少的新能力。
