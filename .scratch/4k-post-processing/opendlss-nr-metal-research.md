# OpenDLSS-NR：Metal 实现可行性

研究日期：2026-09-22。范围：一手文档和源码审阅；未构建模型、未取得权重或 NVIDIA 对照 captures、未运行 GPU 推理或性能测试。本报告是候选技术研究，不是集成决策或验收。

## 结论

**Metal 可以实现这套神经渲染算法。** OpenDLSS-NR 已用不依赖 NVIDIA Tensor Core 的 WGSL 实现同一网络；独立项目 MLX-DLSS 也已有 Apple Silicon 的 Swift、MLX 和自定义 Metal 实现。不过，要分别看三个目标：网络和权重可运行、输出逐位一致、目标设备实时处理。前一个已有实现证据；后两个不能从“支持 Metal”推导出来。[S1][S2][S5][S6]

对于 XFrame，优先评估 MLX-DLSS 现有原生后端，用 OpenDLSS-NR 的网络描述和数值契约作为交叉验证资料，比从 Windows Vulkan/PTX 后端整体移植更有价值。这是工程建议，不代表我们已经测得 M1 1080p60 可行。

## 固定研究版本

| 项目 | 核对的 commit | 用途 |
| --- | --- | --- |
| OpenDLSS-NR | `9d08f4184bbcb9d858e2fb7a7834ec0837a9d2f1` | 网络、数值契约、时序处理、WGSL 可移植路径 |
| MLX-DLSS | `0ca2deab092fe6f3e331bf4f616271dbc64521d0` | 已有原生实现、误差与性能边界 |

以下链接固定到这些提交。网络参数绑定 NR 310.8.0；不要把该结论推广到任意 DLSS 版本。[S1][S5]

## 它实现的是什么

OpenDLSS-NR 实现 DLSS 5 Neural Rendering 的图像生成网络：71 个 block，Swin 窗口 attention 与底部全局 ViT，六级池化的 U-net 结构。输出保持输入分辨率，生成外观细节并改变色调、结构和皮肤表现；这不是补帧，也不是 DLSS Super Resolution。NVIDIA 官方将它定位为生成式渲染，并描述了当前画面、运动矢量、历史状态及艺术控制参数作为条件。[S1][S3][S9]

输入为每像素 16 个通道：三路噪声、常量、当前显示域 RGB、重投影的历史输出 RGB、风格与其他控制量等。网络输出 RGB 残差和一个时间混合 logit。后处理把残差合成到当前画面，再按预测权重混入历史；历史供下一帧复用。无历史时使用当前 proxy 作为历史输入并禁用历史混合。[S3][S4]

这里的“增强”包含生成细节，不等同于恢复视频压缩前的真实信息。对 xCloud 应验证游戏美术、文字、HUD 和运动纹理是否被不合适地改变。[S3][S9；后一句为应用风险推断]

## Metal 需要实现的部分

| 部分 | 实现路线 | 关键边界 |
| --- | --- | --- |
| 模型加载与布局 | Swift/C++ 解析模型；转换布局至 Metal/MLX 张量 | 使用同一模型版本和参数；不同项目的打包格式不可假定互通 |
| 矩阵乘、attention、MLP、池化和 skip | MLX/MPSGraph 或自定义 Metal compute；现成 MLX-DLSS 可参考 | 通用算子适合先跑通，严格数值匹配通常需要定制 |
| FP8 E4M3 表示与舍入 | 字节存储、显式解码/量化；必要时模拟累加 | 没有同款 NVIDIA 指令不阻止计算，但可能增加开销 |
| 噪声、显示域转换与合成 | Metal kernels | 噪声种子、padding、色彩空间及舍入均影响结果 |
| 历史重投影 | Metal 采样与双缓冲历史，视频使用估计光流 | 光流并不等价于游戏引擎运动矢量；场景切换应清空历史 |
| 调度与同步 | Metal command buffer、资源复用、按设备优化融合 | PTX、CUDA launch、Vulkan 扩展和 NVIDIA 的跨 kernel 调度不能原样搬过来 |

这张表是基于源码结构的移植设计推断。直接证据包括 OpenDLSS-NR 的 WGSL 纯软件数值路径，以及 MLX-DLSS 的 `MLXFast.metalKernel`、`metal_simdgroup_matrix` 和 fused-window kernels。[S2][S6][S7]

## 为什么“同样算法”不自动等于“完全相同像素”

OpenDLSS-NR 专门规定了先舍入到 FP16 再到 E4M3、累加顺序、分组点积、残差何时加入、NaN 与带符号零的处理，以及 attention 的归约顺序。普通 FP16/FP32 矩阵乘即使数学表达式相同，也可能产生不同结果；更高精度也不保证更接近原实现。[S7]

其 WebGPU 版本用整数和显式舍入模拟这些行为，说明 NVIDIA 硬件不是表达该算法的必要条件。但作者公布的 WebGPU parity 在 RTX 4070 SUPER 上完成；噪声用到的近似超越函数有跨厂商差异，作者也明确不保证所有设备一致。因此不能把其“bit-exact”标语当作 Apple GPU 已经逐位通过的证据。[S2]

MLX-DLSS 已完成该 71-block 网络的原生实现，但文档仍报告非零误差，并列出运动、遮挡、jitter 和 mask 等时序参考样本缺口。它证明了 Metal 可运行这类网络，不证明与 OpenDLSS-NR 或 NVIDIA 在所有输入下逐位一致。[S5][S8]

## 性能证据如何解读

| 作者报告 | 测量条件 | 能说明什么 |
| --- | --- | --- |
| OpenDLSS-NR 1080p 7.8 ms | RTX 4070 SUPER，完整网络，40 帧最小值 | NVIDIA 优化路径的作者结果，不是 Apple 性能，也不是端到端延迟 |
| WebGPU 512×512 约 73 ms | 同类页面注明 RTX 4070 SUPER；451 dispatch | 软件模拟精确数值有显著成本；不能据此推算 Metal 或 M1 |
| MLX-DLSS 时序视频约 18.4–20.1 输入帧/秒 | M2 Max，512×384、228 帧、detail strength 2，含启动、光流、解码与编码 | 已有 Mac 端到端样例，但该配置不能证明 M1 1080p60 |

来源分别为 [S1][S2][S5]。这些路径、精度要求和计时范围不同，不做横向排名。尤其不要把 MLX-DLSS **补帧**模型的 1080p GPU 时间当成 **NR** 网络时间。

60 Hz 输出每个刷新周期约 16.67 ms，这是算术预算，不是 NR 可独占的时间：解码、光流、补帧、超分、合成以及系统 GPU 负载都会竞争资源。跨帧流水线可能改善吞吐但增加排队延迟，应同时测量处理耗时、队列深度和实际呈现时间。

## 纯视频输入与 XFrame 接入

网络可以处理单帧；视频时序效果需要历史对齐。OpenDLSS-NR 的 demo 从 Filament 取得引擎运动矢量，XFrame 只有解码帧，需要图像光流及遮挡/历史失效策略。不能把未提供运动的区域简单当成“零运动”：零运动表示历史还在同一位置，并不表示没有可用历史。[S4]

建议概念管线：解码帧 → 明确色彩转换/显示域 proxy → 原始图像估计光流 → 历史重投影 → NR 推理与合成 → 现有显示管线。光流优先从原始输入估计，避免生成细节干扰运动；这是一项待验证设计。NR 与补帧的先后顺序需 A/B，不能现在固定为产品决策。

用户已观测 xCloud FPS 会随场景从约 60 降至 40，再回到 60。NR 的历史必须跟随实际处理帧和时间戳；丢帧、重连、尺寸变化和场景切换应使历史失效。慢推理不能形成无限积压；需要有界队列与跳过增强的降级策略。这些是 XFrame 的候选接入约束，尚未实现或验收。

## M1 Mac mini 与 M5 MacBook Air

用户补充的目标设备是 M1 Mac mini 和 M5 MacBook Air；M5 的内存、GPU 核数与系统版本尚未核对，也未运行能力探测或实测。

- **M5 新增 GPU 内的 Neural Accelerators**：每个 GPU shader core 配有矩阵运算加速硬件。它与独立的 Apple Neural Engine 是不同单元；M1 本来就有 Neural Engine，不能称 M1 没有 AI 加速。Metal TensorOps 可以利用 M5 的新硬件，尤其适合密集矩阵乘和卷积。[S10][S11]
- **API 可用性不等于专用硬件存在**：Apple 说明 TensorOps 可跨 Apple Silicon 代际运行并使用可用加速，因此“Metal 4/TensorOps 只有 M5 能用”不正确。M1 可以执行相同计算，但没有 M5 这套 GPU Neural Accelerator 硬件路径。[S10]
- **低精度与系统版本分别判断**：macOS 27 的 TensorOps 增加 FP4/FP8 等格式。格式/API 支持不能证明基础款 M5 具有与 NVIDIA E4M3 Tensor Core 相同的原生吞吐和累加语义，也不能把 M5 Pro/Max 的结果当作 M5 Air 的结果。[S10；后两句为推断与验证限制]
- **已有针对 M5 的 NR 实现**：DLSSMac 使用 MLX、Metal 与自定义 FP8/NAX kernels，当前 fast profile 面向 M5，要求 macOS 27；作者仅测试 M5 Max 48 GB，并明确该发布的快速路径不支持 M1–M4。它是具体实现的限制，不是 NR 算法只能在 M5 计算；M5 Air 的兼容性与性能仍需验证。[S12]
- **其他硬件差异**：M5 Air 技术规格列出硬件光线追踪和 AV1 解码。光线追踪不能为已渲染的视频恢复引擎几何；AV1 解码只有在实际收到 AV1 流时才有用，不能直接改善当前 H.264 流。[S13；应用意义为推断]

工程判断：M5 Air 应作为神经补帧/NR 的第二台重点实验设备，M1 保留基础路径。两台都测同一输入、模型、分辨率与长时间运行，而非按芯片名称直接启用最高档。Air 无风扇，持续负载测试尤其必要；可运行不等于能持续满足 60 Hz。[S11]

## 后续原型的完成门槛

1. 先在独立离线工具中运行同一批静帧、短视频，明确模型版本、控制参数、分辨率、色彩空间和权重 hash。
2. 分开验证算术小样本、网络中间结果、最终图像及时序稳定性；没有 vendor fixtures 时只报告可测的误差，不能声明官方一致。
3. 在目标 M1 上测 540p/720p/1080p，区分首次编译、预热后 GPU 时间、完整管线 p50/p95/p99、内存、功耗和持续负载。
4. 用快速转镜、遮挡、粒子、HUD、小字、暗场、镜头切换和动态 40–60 fps 片段做盲测/A-B；同时观察细节改变和新增延迟。
5. 先单独测 NR，再组合光流/补帧/MetalFX；只有共同满足显示期限和质量门槛后才进入产品实现。

源码许可证和模型许可分开：OpenDLSS-NR 源码 MIT，未提供模型权重或参考 captures；MLX-DLSS 源码 Apache-2.0，模型不随源码提供。实际原型仍需要准备适用的模型数据，不能把开源代码理解为模型可随应用分发。[S1][S5]

## 来源

- [S1 — OpenDLSS-NR README](https://github.com/maanHimself/OpenDLSS-NR/blob/9d08f4184bbcb9d858e2fb7a7834ec0837a9d2f1/README.md)
- [S2 — WebGPU 实现与验证边界](https://github.com/maanHimself/OpenDLSS-NR/blob/9d08f4184bbcb9d858e2fb7a7834ec0837a9d2f1/ports/browser-webgpu/README.md)
- [S3 — 网络与输入输出](https://github.com/maanHimself/OpenDLSS-NR/blob/9d08f4184bbcb9d858e2fb7a7834ec0837a9d2f1/docs/network.md)
- [S4 — 时序、重投影与显示管线](https://github.com/maanHimself/OpenDLSS-NR/blob/9d08f4184bbcb9d858e2fb7a7834ec0837a9d2f1/docs/frame.md)
- [S5 — MLX-DLSS README 与作者测量](https://github.com/iamwavecut/MLX-DLSS/blob/0ca2deab092fe6f3e331bf4f616271dbc64521d0/README.md)
- [S6 — 原生 Metal fused window block](https://github.com/iamwavecut/MLX-DLSS/blob/0ca2deab092fe6f3e331bf4f616271dbc64521d0/Sources/DLSSMLX/NeuralRenderingFusedWindowBlock.swift)
- [S7 — OpenDLSS-NR 数值契约](https://github.com/maanHimself/OpenDLSS-NR/blob/9d08f4184bbcb9d858e2fb7a7834ec0837a9d2f1/docs/numerics.md)
- [S8 — MLX-DLSS 恢复状态与未验证项](https://github.com/iamwavecut/MLX-DLSS/blob/0ca2deab092fe6f3e331bf4f616271dbc64521d0/docs/recovery-notes.md)
- [S9 — NVIDIA DLSS 5 官方研究说明](https://research.nvidia.com/labs/adlr/DLSS5/)

- [S10 — Apple：Metal tensors / TensorOps 与 M5 Neural Accelerators](https://developer.apple.com/videos/play/wwdc2026/330/)
- [S11 — Apple：M5 MacBook Air 发布与无风扇设计](https://www.apple.com/newsroom/2026/03/apple-introduces-the-new-macbook-air-with-m5/)
- [S12 — DLSSMac 当前兼容性声明](https://github.com/Mappsnet7/DLSSMac)（2026-09-22 核对，非固定版本）
- [S13 — M5 MacBook Air 技术规格](https://www.apple.com/macbook-air/specs/)

相关资料：[补帧研究总览](frame-interpolation-research.md)、[Veyra macOS 移植情况](veyra-macos-portability.md)、[Veyra 源码研究](veyra-nrvideo-research.md)。
