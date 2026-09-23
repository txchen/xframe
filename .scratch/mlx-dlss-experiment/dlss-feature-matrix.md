# NVIDIA DLSS 功能矩阵（截至 2026-09-23）

研究范围：DLSS 官方功能以 NVIDIA 开发者文档、技术研究和公告为依据；MLX 移植状态另与本仓库固定的上游源码及本机测量核对。DLSS 的数字是**套件发布代际**，不是单一算法版本；同一代可组合多个独立功能。型号、游戏集成、驱动和模型预设共同决定可用功能，不能把“支持 DLSS 4.5”直接理解为“支持所有功能”。[NVIDIA DLSS Developer](https://developer.nvidia.com/rtx/dlss)、[DLSS 4 Streamline 集成指南](https://developer.nvidia.com/blog/how-to-integrate-nvidia-dlss-4-into-your-game-with-nvidia-streamline/)。

## 版本与功能

| 品牌代际 | 当时引入/突出的功能 | 重要澄清 |
| --- | --- | --- |
| DLSS 1（2018） | AI 图像升尺度 | 早期需按游戏训练；不涉及帧生成。[NVIDIA DLSS 2.0 回顾](https://www.nvidia.com/en-us/geforce/news/nvidia-dlss-2-0-a-big-leap-in-ai-rendering/) |
| DLSS 2（2020） | 通用化的时间超分 SR，跨帧反馈、引擎运动矢量；后来有 DLAA 原生分辨率抗锯齿模式 | 只重建当前帧分辨率，不增加时间轴上的帧数。[DLSS 2.0 技术说明](https://www.nvidia.com/en-us/geforce/news/nvidia-dlss-2-0-a-big-leap-in-ai-rendering/)、[DLSS Developer](https://developer.nvidia.com/rtx/dlss) |
| DLSS 3（2022） | 在 SR 之外加入 Frame Generation（每两个游戏帧间生成一帧，2X 模式）；组合 Reflex 降低延迟 | FG 为 RTX 40 起，SR 仍可供旧 RTX 使用；Reflex 是协同的低延迟技术，不是插帧模型。[DLSS 3 说明](https://www.nvidia.com/en-us/geforce/news/gfecnt/20229/dlss3-ai-powered-neural-graphics-innovations/) |
| DLSS 3.5（2023） | Ray Reconstruction（RR），用 AI 替代光追降噪器 | RR 适用于有光追输入的 RTX 20/30/40 等；无光追场景不能凭空得到 RR 效果。[DLSS 3.5 说明](https://www.nvidia.com/en-us/geforce/news/nvidia-dlss-3-5-ray-reconstruction/) |
| DLSS 4（2025） | Multi Frame Generation（MFG，最多 4X，即每个原生帧最多 3 个生成帧）；SR/RR/DLAA 引入第一代 Transformer 模型 | MFG 为 RTX 50；Transformer SR/RR/DLAA 面向全系 RTX。FG 模型本身也更新，但“Transformer”不等于“FG 必然用 Transformer”。[DLSS 4 公告](https://www.nvidia.com/en-us/geforce/news/gfecnt/20251/dlss4-multi-frame-generation-ai-innovations/)、[NVIDIA 研究报告](https://research.nvidia.com/labs/adlr/DLSS4/) |
| DLSS 4.5（2026） | 第二代 Transformer SR；RTX 50 上 Dynamic MFG 和固定最高 6X（每原生帧最多 5 个生成帧）；改进 FG UI；第二代 Transformer RR 于 2026-08-25 发布 | Dynamic 模式按目标帧率/显示器刷新率调节倍率，并非每次都生成 5 帧。第二代 SR/RR 面向全系 RTX；FG UI 改进支持 RTX 40/50 且依赖游戏缓冲区。[4.5 MFG/SR 发布](https://www.nvidia.com/en-eu/geforce/news/dlss-4-5-dynamic-multi-frame-generation-6x-mode-released/)、[4.5 RR 发布](https://www.nvidia.com/en-gb/geforce/news/gamescom-2026-dlss-4-5-ray-reconstruction-release-announcements-trailers/) |
| DLSS 5（2026-09 已上线） | **3D-Guided Neural Rendering**：每输入帧输出一帧，增强光照、材质等最终外观 | 不生成额外的时间帧，不是 FG 5 代。2026-09-01 NVIDIA 宣布已在 NBA 2K27 提供，RTX 50 系列本机运行，也可通过 GeForce NOW 体验；其他游戏仍取决于实际集成。[DLSS 5 发布](https://www.nvidia.com/en-eu/geforce/news/dlss-5-3d-guided-neural-rendering/)、[研究摘要](https://research.nvidia.com/labs/adlr/DLSS5/) |

## 各功能原理与输入

| 功能 | 大致做什么 | 关键输入与条件 | XFrame 视频后处理的对应关系（推论） |
| --- | --- | --- | --- |
| Super Resolution（SR） | 从低分辨率渲染帧重建较高分辨率输出，利用历史帧缓解锯齿与闪烁，换取渲染成本。旧 CNN 以局部卷积处理，DLSS 4 Transformer 用跨像素、跨帧注意力增强时序与细节；DLSS 4.5 第二代继续改进。 | 游戏当前低分辨率帧、运动矢量、上一帧输出/时间历史；生产集成还需正确 jitter、曝光、相机重置等。[DLSS 2.0](https://www.nvidia.com/en-us/geforce/news/nvidia-dlss-2-0-a-big-leap-in-ai-rendering/)、[集成清单](https://developer.nvidia.com/blog/how-to-integrate-nvidia-dlss-4-into-your-game-with-nvidia-streamline/)、[DLSS 4 研究](https://research.nvidia.com/labs/adlr/DLSS4/) | 已压缩的串流视频没有游戏引擎原生 MV/jitter/历史，能做视频超分或时序重建，但不能等同原版游戏内 DLSS SR。 |
| Deep Learning Anti-Aliasing（DLAA） | 与 SR 同系列的时序 AI 重建，在原生输出分辨率做抗锯齿，重画质而非靠降低内部渲染分辨率提速。 | 同类引擎时间数据及 RTX；通常吃掉而非释放 GPU 余量。[DLSS Developer](https://developer.nvidia.com/rtx/dlss) | 可做视频抗锯齿/去闪烁的类比功能，但串流中锯齿已进入编码结果，质量上限不同。 |
| Frame Generation（FG，2X） | 根据相邻真实帧之间的变化，合成一张中间帧；DLSS 3 的卷积自编码器综合两帧、光流、引擎 MV/深度等。 | RTX 40/50、游戏 FG 集成、光流及引擎数据；Reflex 降低额外队列延迟。[DLSS 3](https://www.nvidia.com/en-us/geforce/news/gfecnt/20229/dlss3-ai-powered-neural-graphics-innovations/)、[4.5 FG UI 模型](https://www.nvidia.com/en-eu/geforce/news/dlss-4-5-dynamic-multi-frame-generation-6x-mode-released/) | 最贴近 XFrame 的视频补帧目标，但串流端只有解码帧，无真实引擎 MV/深度/HUD 分层；需从图像估计，无法直接继承 NVIDIA 游戏内质量或时延。 |
| Multi Frame Generation（MFG）、Dynamic MFG | 在一对原生帧之间合成多张中间帧；DLSS 4 模型将每对帧只需计算一次的部分与每张输出重复计算的部分拆开。DLSS 4.5 最多 6X，Dynamic 自动选择需要的倍率。 | RTX 50 Blackwell、支持的游戏/驱动/Streamline；引擎 MV、深度、无 HUD 图像及 UI 图层等。Dynamic 需合适的帧调度。[DLSS 4 研究](https://research.nvidia.com/labs/adlr/DLSS4/)、[集成清单](https://developer.nvidia.com/blog/how-to-integrate-nvidia-dlss-4-into-your-game-with-nvidia-streamline/)、[4.5 发布](https://www.nvidia.com/en-eu/geforce/news/dlss-4-5-dynamic-multi-frame-generation-6x-mode-released/) | 60 Hz 上稳定 30→60 只需一张中间帧；6X 不会提升 60 Hz 显示上限。Dynamic 的“按需要补”思想可移植到 XFrame 调度，底层模型不能直接等同。 |
| Ray Reconstruction（RR） | 对低采样率光追/路径追踪缓冲去噪，并与超分联合重建，替代多个手工降噪器。DLSS 4 和 4.5 分别升级到第一、二代 Transformer。 | 游戏光追采样和 G-buffer，如线性深度、运动矢量/镜面运动矢量及相关材质/照明指导信息；需集成在引擎后处理早期。[DLSS 3.5](https://www.nvidia.com/en-us/geforce/news/nvidia-dlss-3-5-ray-reconstruction/)、[集成清单](https://developer.nvidia.com/blog/how-to-integrate-nvidia-dlss-4-into-your-game-with-nvidia-streamline/)、[4.5 RR](https://www.nvidia.com/en-gb/geforce/news/gamescom-2026-dlss-4-5-ray-reconstruction-release-announcements-trailers/) | XFrame 接到的是已经降噪、合成、压缩的最终画面；无法事后恢复未传输的光追样本/材质缓冲，因此不能复现原版 RR。 |
| 3D-Guided Neural Rendering（DLSS 5） | 以已渲染画面为硬约束，每帧用单步像素空间扩散模型生成更真实的光照/材质外观；因果式、确定性、时序稳定，每入一帧出一帧。 | 当前帧颜色、引擎 MV、时间状态、艺术指导参数；模型训练用场景属性。RTX 50，本机运行，支持到 4K；开发者可选模型、调强度并用语义/引擎遮罩控制。[DLSS 5 论文摘要](https://research.nvidia.com/labs/adlr/DLSS5/)、[2026-09-22 开发者文章](https://developer.nvidia.com/blog/whats-new-for-game-developers-dlss-5-with-3d-guided-neural-rendering-nvidia-ace-updates-and-new-rtx-kit-capabilities/) | 与补 30→60 无直接关系；纯视频缺乏引擎条件和美术控制，即便另训类似模型也不应称为 DLSS 5。 |
| NVIDIA Reflex / Reflex Frame Warp | Reflex 将 CPU/GPU 渲染排队压短；Frame Warp 在显示前用更新的输入重投影已渲染帧以降低交互延迟。它们与 FG 配合，但功能目的不同。 | 引擎/输入/呈现链路的低延迟集成；Frame Warp 还需要视角与相关场景数据。[DLSS 3 与 Reflex](https://www.nvidia.com/en-us/geforce/news/gfecnt/20229/dlss3-ai-powered-neural-graphics-innovations/)、[DLSS 4 研究报告](https://research.nvidia.com/labs/adlr/DLSS4/) | XFrame 可独立做缓冲和显示时序优化；客户端视频插帧不能声称实现 NVIDIA Reflex。 |

## 易误读的性能与状态边界

- DLSS 4 的“8X 性能”和 DLSS 4.5 的“6X”不是同一个基准：8X 可包含 SR 相对原生 4K 的渲染节省；6X 是至多每 1 张原生帧对应 6 张显示帧。FG 增加显示帧率，不增加游戏输入、物理或网络源帧采样率。[DLSS 4 公告](https://www.nvidia.com/en-us/geforce/news/gfecnt/20251/dlss4-multi-frame-generation-ai-innovations/)、[4.5 发布](https://www.nvidia.com/en-eu/geforce/news/dlss-4-5-dynamic-multi-frame-generation-6x-mode-released/)。
- DLSS 4.5 Dynamic MFG 发布初期不兼容帧率限制器和 V-Sync；NVIDIA 在 2026-09-03 的驱动/应用更新中加入支持，要求驱动 616.64 与 Streamline 2.14 或更新。这是随时间变化的要求，测试前应核对当前驱动。[NVIDIA 驱动说明](https://www.nvidia.com/en-eu/geforce/news/nba-2k27-dlss-5-3d-guided-neural-rendering-geforce-game-ready-driver/)。
- DLSS 5 已在一个游戏正式上线，但它的公开实现仍为 NVIDIA/RTX 50 专有；其他已宣布游戏的支持日期不能从品牌发布推断。[DLSS 5 已上线公告](https://www.nvidia.com/en-eu/geforce/news/dlss-5-3d-guided-neural-rendering/)。
- NVIDIA Image Scaling（NIS）是非 AI、仅当前帧的空间升尺度/锐化算法，不等于 DLSS SR；RTX Video Super Resolution 是面向播放视频的独立产品，也不等于游戏内 DLSS。[NIS 开发者说明](https://developer.nvidia.com/rtx/image-scaling)、[RTX Video 公告](https://blogs.nvidia.com/blog/rtx-video-super-resolution/)。

## Apple Silicon / MLX 可行性（以本仓库固定的 MLX-DLSS `0ca2deab` 为准）

“能用 MLX/Metal 实现网络算子”、“已有可运行的实验移植”、“能在 XFrame 60 Hz 串流中实时使用”是三个不同命题。MLX 是 Apple Silicon 上的机器学习框架，不会运行 NVIDIA 的 RTX DLL 或自动提供训练权重。[Apple MLX](https://github.com/ml-explore/mlx)、[MLX-DLSS 固定版本 README](https://github.com/iamwavecut/MLX-DLSS/blob/0ca2deab092fe6f3e331bf4f616271dbc64521d0/README.md)。

| 功能 | 固定版本的实际状态 | XFrame 上的判断 |
| --- | --- | --- |
| SR | 上游有实验性的 DLSS SR preset K、LDR、2× 视频移植，输入视频用估算光流、常量深度、零 jitter；模型准备仍需一次 CUDA capture。[上游 SR 说明](https://github.com/iamwavecut/MLX-DLSS/blob/0ca2deab092fe6f3e331bf4f616271dbc64521d0/docs/super-resolution.md) | 可研究视频超分，但本仓库当前只有 MetalFX Spatial 实时缩放，没有接入这条 MLX SR；缺少引擎原始输入，画质和成本须另测。 |
| DLAA | 上游未提供独立 DLAA 视频模式。 | 原理上可移植类似的时序抗锯齿网络；不能把上游 SR 或普通视频滤镜称作已实现 DLAA。 |
| FG（2×） | 上游已有普通视频补帧移植；没有游戏引擎 MV/深度/HUD 分层时，相关输入退化为视频路径。[上游 FG 说明](https://github.com/iamwavecut/MLX-DLSS/blob/0ca2deab092fe6f3e331bf4f616271dbc64521d0/docs/frame-generation.md) | XFrame 目前仅将其接入可选的内置性能测试，未接入实时串流。M1 的 1080p 30→60 p95 为 69.09 ms **helper 往返墙钟时间**，超过每对源帧 33.33 ms 的预算；M5 待测。[本仓库测试记录](../post-processing-benchmark/spec.md) |
| MFG / Dynamic MFG | 上游 FG 可对一对视频帧计算多个时间相位，但没有 NVIDIA RTX 50 的 MFG 集成、动态 UI/帧调度和引擎缓冲；不能据此宣称 DLSS 4/4.5 MFG 已移植。[上游 FG 说明](https://github.com/iamwavecut/MLX-DLSS/blob/0ca2deab092fe6f3e331bf4f616271dbc64521d0/docs/frame-generation.md) | 60 Hz 下优先研究按实际帧时间补到 60；稳定 30→60 每对只需一张中间帧。 |
| RR | 固定版本没有 RR 模型移植。 | 机器学习网络原则上能用 MLX 重写，但纯视频没有原始光追缓冲，无法忠实实现 NVIDIA RR。 |
| DLSS 5 神经渲染 | 上游有实验性的 Neural Rendering 图像/视频移植，输入视频用估算运动并缺乏完整引擎美术控制；与 FG 是不同模型。[上游 README](https://github.com/iamwavecut/MLX-DLSS/blob/0ca2deab092fe6f3e331bf4f616271dbc64521d0/README.md)、[NVIDIA DLSS 5 输入](https://research.nvidia.com/labs/adlr/DLSS5/) | 可以作为独立画质实验，但不能增加 30 fps 视频的帧数，M1/M5 的 1080p60 性能与视觉质量尚未由 XFrame 测试证明。 |
| Reflex | 属于输入、引擎和呈现队列控制，不是 MLX 推理模型。 | 可以优化 XFrame 的解码与显示缓冲，但不能把客户端优化叫作 NVIDIA Reflex。 |

权重与发布许可、原始缓冲获取、端到端时延、画质和目标设备性能都需要分别验证。内置性能测试只能筛掉明显超预算的候选，不能代替真实串流验收。
