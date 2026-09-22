# macOS 视频补帧技术研究

研究日期：2026-09-22。用途：XFrame 后续选型和原型验收参考，不代表已决定实现某一后端。

证据边界：本次重新核对第一方 API、上游源码与作者文档，没有构建第三方项目、下载模型或执行补帧性能测试。下文明确区分 API 能力、作者测量和 XFrame 设计建议。在线 `main` 文档会变化；正式 PoC 必须固定 commit、模型版本、系统版本与参数。

目标设备包括已有能力查询记录的 Apple M1，以及用户本轮补充的 **M5 MacBook Air**。后者尚未探测系统配置或测速；不能把 M5 Max 的作者结果当作 M5 Air 结果，也不能仅根据新一代 GPU 能力承诺持续实时性能。两台机器应分别记录可用配置、稳态耗时和持续运行表现。M5 神经网络相关能力及限制见 [OpenDLSS-NR / Metal 专题](opendlss-nr-metal-research.md)。

## 结论与推荐顺序

1. **先验证 VideoToolbox 低延迟补帧**：原生视频输入和接收端场景最匹配，接入工作较少。必须先验证实际会话、支持尺寸/格式和相位限制；系统称其低延迟不等于 xCloud 游戏已达标。[Apple 介绍](https://developer.apple.com/videos/play/wwdc2025/300/)
2. **RifeMetal 与 MLX-DLSS 视频补帧作为独立比较后端**：两者都有原生 Apple GPU 实现，已经超出“理论上能移植”的阶段；M1 上的实时吞吐、资源共享和操作延迟仍未验证。[RifeMetal](https://github.com/cinemore/rife-metal)、[MLX-DLSS FG](https://github.com/iamwavecut/MLX-DLSS/blob/main/docs/frame-generation.md)
3. **VideoToolbox 高质量帧率转换**用于相位灵活性和质量对照。**MetalFX、FSR/XeSS 游戏补帧**先作为适配研究，不先承担自建光流、深度近似、GPU 后端和调度器全部工作。[VT FRC](https://developer.apple.com/documentation/videotoolbox/vtframerateconversionconfiguration)、[MetalFX](https://developer.apple.com/videos/play/wwdc2025/211/)

该排序是工程成本判断，不是已测出的画质或速度排名。DLSS 神经渲染 NR 是画质增强，FG 才是补帧；移植一个不自动完成另一个。OpenDLSS-NR 的 Metal 可行性属于独立研究。

## 候选技术与实际可用程度

| 路线 | 算法与输入 | macOS 实现证据 | 尚未解决的 XFrame 问题 |
| --- | --- | --- | --- |
| VideoToolbox 低延迟补帧 | Apple 提供的 ML 视频处理；前一帧、当前帧、所需相位与输出像素缓冲 | macOS 26 起的原生 `VTLowLatencyFrameInterpolationConfiguration` | M1 实际耗时、离散相位、压缩游戏视频/HUD 质量、尺寸与格式支持 |
| VideoToolbox 帧率转换 | 两帧、相位数组，可由框架生成或外部提供光流；可选质量优先级 | macOS 15.4 起的原生 `VTFrameRateConversionConfiguration` | Apple 定位高质量视频编辑；实时交互成本须独立测量 |
| RIFE / RifeMetal | 学习式中间光流估计与图像合成；两幅图像与时间位置 | Swift 包，MPSGraph 网络和自定义 Metal warp；当前打包 Practical-RIFE v4.26 权重 | API 的图像拷贝成本、纹理互操作、数值一致性、M1 吞吐 |
| MLX-DLSS FG | 从 NVIDIA 库恢复的纯视频推理路径；两帧和相位；网络预测流并 warp/blend | 原生 Swift、MLX、Metal 实验性实现 | 外部权重、模型一致性、纹理互操作、M1 速度；并非完整游戏引擎版 DLSS SDK |
| MetalFX Frame Interpolation | 两帧、运动矢量、深度；官方游戏渲染集成还处理 UI | Apple 原生接口 | xCloud 没有真实引擎深度/运动；近似输入效果未知；与现有 Spatial scaler 是不同功能 |
| FSR FG | 光流、引擎运动/深度等输入驱动的帧插值和呈现调度 | 有 Mac Wine/GPTK 运行案例，未确认可直接接入 XFrame 的原生 Metal FG 库 | 需要原生算法/资源/调度适配，不能只接 Windows DLL |
| XeSS FG | 学习式补帧，官方要求运动、深度、帧常量等 | 当前官方接口是 D3D12 代理 swapchain；本次未确认原生 Mac 移植 | 输入和平台接口均不匹配现有纯视频客户端 |
| 光流 + 自建 Metal 合成 | 估计运动后双向 warp、遮挡处理、融合和可信度判断 | Apple Vision / VT 有光流接口；AMD/GPU DIS 有参考源码 | 光流不是完整补帧，需要自己负责合成、遮挡、切场与调度 |

表格来源：[Apple VT 讲解及代码](https://developer.apple.com/videos/play/wwdc2025/300/)、[低延迟 API](https://developer.apple.com/documentation/videotoolbox/vtlowlatencyframeinterpolationconfiguration)、[RifeMetal](https://github.com/cinemore/rife-metal)、[RIFE 原始项目](https://github.com/hzwer/ECCV2022-RIFE)、[MLX-DLSS FG](https://github.com/iamwavecut/MLX-DLSS/blob/main/docs/frame-generation.md)、[MetalFX 集成](https://developer.apple.com/videos/play/wwdc2025/211/)、[AMD FG API](https://gpuopen.com/manuals/fsr_sdk/techniques/frame-interpolation-api/)、[Metal FSR 4](https://github.com/Alien4042x/metal-fsr-4)、[XeSS FG guide](https://github.com/intel/xess/blob/main/doc/xess_fg_developer_guide_english.md)、[Vision optical flow](https://developer.apple.com/documentation/vision/vngenerateopticalflowrequest)。

## 关键实现细节和容易误读的证据

### VideoToolbox：支持检测、相位和空间放大是不同问题

Apple 的低延迟路径面向接收端实时视频；普通帧率转换强调编辑质量。两者都需要配置并启动 `VTFrameProcessor` 会话，以及按配置的像素缓冲属性分配输入/输出，不能仅凭类存在判断可处理任意帧。[Apple 接入示例](https://developer.apple.com/videos/play/wwdc2025/300/)

本机 macOS 27 SDK 的 `VideoToolbox.framework/Headers/VTFrameProcessor_LowLatencyFrameInterpolation.h` 明确记载：配置请求值为 1 时提供相位 0.5；值为 2 时提供 0.25、0.5、0.75；更高配置可提高时间位置分辨率，也增加延迟。这里的配置值不能直接当作输出帧数。组合空间放大模式仅支持 2 倍空间放大与单个 0.5 中点。后续应对实际 SDK 和运行时重新验证相位集合。[对应 API](https://developer.apple.com/documentation/videotoolbox/vtlowlatencyframeinterpolationconfiguration)

已有本地探针 `.build/interpolation-support.swift` / `.build/interpolation-support.log` 曾在 Apple M1、macOS 27 上报告 VT 两类补帧、VT 光流和 MetalFX interpolator 支持。它只是能力查询，没有证明会话可启动、某种分辨率可处理或可实时运行；`.build` 文件也可能被清理。现有证据不足以给所有 M1/M2/M3 机器划一条支持边界。

### RIFE：已有原生移植，但不要把算法名字中的 Real-Time 当性能保证

RifeMetal 当前使用 MPSGraph 和自定义 Metal warp，有 SwiftPM 包与 CLI，携带 Practical-RIFE v4.26 权重。它与通过 Vulkan/MoltenVK 的 [rife-ncnn-vulkan](https://github.com/nihui/rife-ncnn-vulkan) 是两条不同部署路线。后者提供 macOS 包也不代表前者的性能。原始 RIFE 项目的 NVIDIA GPU 性能不能直接转写为 M1 数据。[RifeMetal README](https://github.com/cinemore/rife-metal)、[原始 RIFE](https://github.com/hzwer/ECCV2022-RIFE)

原型需检查使用的入口是否发生 `CVPixelBuffer → CGImage → CPU array → GPU` 往返，不能只测网络执行。低分辨率光流/网络加全分辨率 warp 可以作为独立质量档实验，但须记录真实处理尺寸，不把输出 1080p 当作全网络 1080p 推理。

### MLX-DLSS：真正存在的 Apple GPU 视频路径，仍然有范围限制

上游恢复的是 DLSS SDK 310.7.0 库的纯视频路径：以零引擎运动、平面深度提供视频输入，在这种条件下移除无效的引擎运动/深度处理步骤，保留学习式光流、图像变形和融合。它不是只重复原帧，也不是完整重现有真实深度、引擎运动和 HUD 分离的游戏管线。用户需要自己提供所需权重；项目代码许可不自动覆盖权重。[恢复范围与验证](https://github.com/iamwavecut/MLX-DLSS/blob/main/docs/frame-generation.md)、[项目说明](https://github.com/iamwavecut/MLX-DLSS)

作者报告 M2 Max 上，最新 fused output head 的 1920×1080 单张生成帧 GPU graph 约 **12.10 ms**。这是固定输入、已预热的特定图测量，不能包含解码、编码、模型加载、输入等待，也不能作为 M1 结果。文档另外列有约 **21.15–21.52 ms** 的 1080p、单对、2 倍 uint8 pipe 路径，包含输入准备及管道往返；两组测量版本和边界不同，不能相减推导集成成本或直接比较。[作者基准及方法](https://github.com/iamwavecut/MLX-DLSS/blob/main/docs/frame-generation.md)

### FSR / XeSS / 光流：区分原生移植与兼容层运行

[Metal FSR 4](https://github.com/Alien4042x/metal-fsr-4) 的原生 Metal 部分是 FSR 4.0.2 **超分**；其补帧使用 AMD 3.1.6 provider 和 3.1.7 interpolation swapchain，经 Wine/GPTK 集成。作者报告游戏运行案例，同时说明构建仍依赖私有基线；不是从新 checkout 就能构建的原生视频 FG 库。[FSR3Unity](https://github.com/ndepoel/FSR3Unity) 同样是超分移植，不能用来证明 Mac FG 已完成。

XeSS FG 的官方指南绑定 D3D12 swapchain、运动/深度资源和 XeLL。其跨厂商 PC GPU 能力不等于 Apple GPU 原生支持。本次未找到已验证的原生 Mac FG 移植，不等于证明任何移植都不存在。[Intel guide](https://github.com/intel/xess/blob/main/doc/xess_fg_developer_guide_english.md)

AMD FidelityFX optical flow 与 Veyra GPU DIS 的源码可供算法移植参考，但 D3D12/HLSL 资源、同步和 shader 工作仍需改写；Vision/VT 光流也只解决运动估计。NVIDIA NVOF 则访问 NVIDIA 专用光流硬件，不能直接搬到 M1，必须替换实现。[AMD 源码](https://github.com/GPUOpen-LibrariesAndSDKs/FidelityFX-SDK/blob/main/Kits/FidelityFX/framegeneration/fsr3/internal/ffx_opticalflow.cpp)、[Veyra GPU DIS](https://github.com/Likely7/Veyra-NRVideo/blob/main/src/guidance/GpuDisOpticalFlow.cpp)、[NVOF 官方说明](https://developer.nvidia.com/optical-flow-sdk)

## 动态 40–60 fps：先按时间调度，再决定生成多少帧

项目已记录用户在 Palworld 中观察到复杂场景约 40 fps、简单场景约 60 fps；见 [spec.md](spec.md)。这是一项输入约束和待测场景，不是本次新增的网络/解码测量。还要区分服务器视频帧、客户端到达/解码帧，以及实际改变的游戏内容：60 fps 容器可能包含重复画面，静止画面也不能据此判成低帧率。

**以下为 XFrame 设计建议：**

- 将媒体 PTS、接收时间、解码完成、GPU 完成和目标呈现时间分别保留。输入 FPS 的滚动平均只用于诊断，不用它重新发明输入时间戳。
- 对目标呈现网格中的时间 `T`，找到围住它的真实帧时间 `A < T < B`，计算 `alpha = (T - A) / (B - A)`。这才是所需插值相位；不要对每对输入一律生成一个中点。
- 稳定 40 fps 间距为 25 ms，60 Hz 网格间距约 16.67 ms：相位对齐时会需要约 1/3 或 2/3 的插值位置。只有中点的后端不能精确完成此重采样；需明确采用近邻相位、重复/丢弃，还是换支持所需相位的算法，并测量运动不匀。
- 输出固定 60 Hz 的时间网格未必能逐一显示全部 40 fps 输入原帧，因为时间点不全重合。需要事先选择“均匀重采样”还是“优先保留真实帧并允许不匀间隔”，不能同时承诺两者。
- 60→40→60 时只生成目标时间网格真正缺的画面；稳定 60 输入不要继续无意义地 2 倍生成再丢弃。插值时需要未来帧，输出时间轴要有明确的 look-ahead 策略。
- 网络抖动不能靠无限缓存解决；错过 deadline 时使用最新有效真实帧/保留帧，记录 fallback，不展示过时生成帧来增加 FPS 计数。切场、重连、尺寸变化和 PTS 不连续需清理对应历史。

## 延迟：16.7 ms 的含义和限制

这是时序推导，不是后端基准。稳定 30 fps 时相邻真实帧 A、B 相隔约 33.3 ms；中间帧对应 16.7 ms 的场景时刻，必须等到 B 可用后才能做双向插值。因此中点相对其理想时间已有 **至少约 16.7 ms 的因果等待**，另有处理、排队和呈现等待。

不能因此承诺开启补帧只增加固定 16.7 ms。若要保持 A→中点→B 顺序并均匀呈现，要延迟真实帧、安排整条播放时间轴；常见按整帧缓冲的策略会使用约一个源帧间隔（30 fps 时 33.3 ms），再加处理余量。更激进的调度可能减少部分等待，但需实测原帧延迟、帧间隔及错过 deadline 的比例。两帧插值的参考契约也见 [Veyra FrameWindow](https://github.com/Likely7/Veyra-NRVideo/blob/df41580f7fa0d2b26718f355640470e8cb94b324/include/veyra/pipeline/FrameWindow.h)。

GPU 5 ms 不等于只增加 5 ms 操作延迟。反过来，也不能简单把每个阶段各自的 p95 相加声称端到端 p95。应对同一输入输出链记录总延迟，并考虑音画同步；完整 controller-to-photon 需要外部测量。使用过去帧预测未来的外推属于不同算法和质量风险，不应混称为这里的两帧插值。

## PoC 和验收门槛

建议先离线固定片段，再接实时流；下列为未来工作门槛，不表示已经通过。

| 阶段 | 必须记录/满足 |
| --- | --- |
| 可运行 | 固定 commit、权重、macOS、目标 GPU（分别测 M1/M5）；成功建立 session、处理真实输入，验证尺寸/像素格式和相位；失败可回退原视频 |
| 算法正确 | 已知平移的运动方向、量纲与相位正确；平移/遮挡/切场、重复帧、混合速率 HUD、压缩噪声；输出不得读到已重用的纹理 |
| 基础性能 | 先测源分辨率，分别记录预热/稳态、输入等待、转换/拷贝、GPU 时长、输出调度、显存和持续运行；至少 p50/p95/p99 与 deadline miss |
| 30→60 | 真实帧、生成帧、hold、提交、实际呈现分别计数；确认内容中点正确和实际约 16.67 ms 呈现间隔；不只观察平均 FPS |
| 动态输入 | 40→60→40 与 60→40→60；输入 jitter、迟到、跳帧和静止场景；队列不持续增长、输出保持新鲜、恢复不震荡 |
| 用户体验 | 相同片段和显示条件下与 bypass A/B；检查文本、细线、粒子、快速转向、遮挡边缘；记录可接受新增延迟和音画同步，再由用户实际游戏验收 |

60 Hz 显示的单个 deadline 间隔是约 16.67 ms，但不能直接把“每张生成帧必须小于 16.67 ms”当作唯一吞吐门槛：30→60 每秒只生成约 30 张，能否按 deadline 交付还取决于真实帧处理、提前量和 GPU 争用。最终门槛应同时包含持续吞吐、最晚完成时间、源帧延迟和有界队列。先验证补帧单独工作，再与 MetalFX Spatial、锐化、NR 组合，避免把组合超载误判为单算法无效。

## 现有资料索引

- [macos-interpolation-options.md](macos-interpolation-options.md)：早期 Apple API/RIFE 候选与能力探针范围。
- [veyra-macos-portability.md](veyra-macos-portability.md)：Veyra 各组件移植状态，尤其原生/兼容层区别。
- [veyra-nrvideo-research.md](veyra-nrvideo-research.md)：固定版本 Veyra 的图顺序、光流、history、队列/纹理所有权及呈现证据。
- [opendlss-nr-metal-research.md](opendlss-nr-metal-research.md)：OpenDLSS-NR 的 Metal 算法可行性、现有实现，以及 M5 MacBook Air 与 M1 的设备差异。
- [spec.md](spec.md)：本地功能规划与 xCloud 动态帧率观察；研究结果不会自动修改其任务状态。

本文作为补帧选型总入口；上述源码细读记录保留。尚无候选通过 XFrame M1 或 M5 MacBook Air 的端到端性能或用户验收。
