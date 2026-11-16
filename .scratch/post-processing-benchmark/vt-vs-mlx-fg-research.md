# VideoToolbox 与 MLX-DLSS FG：XFrame 选型研究

核查日期：2026-11-15。MLX-DLSS 固定到 `7870371e8bf6c03967213f1a5d40db6c5a3bee38`。下文“公开事实”来自 Apple 文档与上游源码，“本地证据”来自已有 benchmark，“判断”是针对 Xbox 视频串流的工程推论。已纳入用户最新 M5 测试（报告 UTC 时间 2026-11-16T01:14:26Z，本地日期 2026-11-15）；本次文档更新没有另外运行测试，尚无画质 A/B。

**当前选型：优先推进 VideoToolbox 的实时插帧接入；MLX FG 保留为研究 benchmark，不作为当前实时接入优先项。** 用户 M5 实测 1080p VT 中位 9.83 ms、P95 9.97 ms；MLX FG 包含 RGB 准备为 26.55 / 27.23 ms。MLX 虽进入 30→60 fps 的计算预算，但余量偏小，且没有已证实的画质优势支持额外成本。Small NR 当前路径不适合这台设备实时处理，暂不推进实时接入。

这是基于当前实现、设备和短时离线测试的工程选择，不是 VT 画质获胜或所有 Apple 设备性能排名。实时串流、持续负载、功耗、画质与操作延迟尚未验收。

## 两者究竟是什么

| 项目 | VideoToolbox 低延迟插帧 | MLX-DLSS 的视频 FG 路径 |
|---|---|---|
| 方法 | Apple 的机器学习视频处理能力；不是简单复制帧 | 从 NVIDIA FG 网络恢复的视频路径，在 MLX/Metal 上执行 |
| 输入 | 前一帧、当前帧及目标插值相位；像素缓冲区 | 两张 RGB 帧；当前 CLI 用 RGB8 或 float32 原始字节 |
| 引擎数据 | 参数接口不要求游戏提供运动矢量或深度 | 视频路径把运动矢量置零、深度设为常量，省掉由此退化的引擎辅助处理 |
| 输出 | 两张输入帧之间的中间帧 | 网络推断流和遮罩、扭曲输入并合成中间帧；CLI 不输出原始帧 |
| 与 NR 的关系 | 独立能力 | FG 是独立模型；Small NR 的高耗时不能当成 FG 耗时 |

公开事实来源：[Apple WWDC25](https://developer.apple.com/videos/play/wwdc2025/300/)、[低延迟配置](https://developer.apple.com/documentation/videotoolbox/vtlowlatencyframeinterpolationconfiguration)、[帧参数](https://developer.apple.com/documentation/videotoolbox/vtlowlatencyframeinterpolationparameters)、[固定版 FG 说明](https://github.com/iamwavecut/MLX-DLSS/blob/7870371e8bf6c03967213f1a5d40db6c5a3bee38/docs/frame-generation.md)、[流式 CLI](https://github.com/iamwavecut/MLX-DLSS/blob/7870371e8bf6c03967213f1a5d40db6c5a3bee38/Sources/mlxdlss/FrameGenStreamCommand.swift)。

公开事实：VT 此配置还能同时做时间插帧和空间放大；组合模式仅支持 2× 放大和一张中间帧。**XFrame 本次测的是纯时间插帧，未启用该放大模式。** [Apple 配置文档](https://developer.apple.com/documentation/videotoolbox/vtlowlatencyframeinterpolationconfiguration)

判断：两者用于串流时，增加的是收到的视频的显示帧数，不会增加 Xbox 的游戏逻辑帧率、输入采样率，也不能把压缩视频变成完整的游戏引擎 DLSS 集成。MLX 视频路径缺少引擎运动、深度和独立 HUD 信息，不能套用 NVIDIA 原生游戏 FG 的质量或延迟宣传。

## 已有性能证据

数字为 median / p95，单位 ms；均为 30→60 fps。30 fps 每对相邻源帧约有 33.33 ms 的持续处理预算。

| 设备、系统、来源 | 分辨率 | VT | MLX FG |
|---|---:|---:|---:|
| M1，macOS 27.0，2026-09-23 本地记录 | 720p | 5.717 / 5.888 | 33.398 / 34.518 |
| 同上 | 1080p | 90.038 / 93.522 | 67.388 / 69.090 |
| 同上 | 1440p | 不支持 | 115.560 / 117.869 |
| M5，macOS 27.2.1 (26B131)，2026-11-16T01:14:26Z 用户报告 | 720p | 3.346 / 3.766 | 12.682 / 13.155 |
| 同上 | 1080p | 9.828 / 9.969 | 26.547 / 27.228 |
| 同上 | 1440p | 不支持 | 47.166 / 48.271 |

本地来源：[M1 原始 JSON](m1-result-mlx.json)。M5 数值摘自用户在对话中提交的完整 JSON，未保存独立原始文件。素材均为 Big Buck Bunny、静音 1080p H.264、30 fps，SHA-256 `5872055dcb979f5d469ede9c575e60418bc9d7731e0528c05ee0817cc0b08633`。M5 FG 权重 SHA-256 `21faede75312631273f930a6fc1aed17f1eb5ac4a476a485551afc6d7ced2958`；VT 与 FG 均为五次预热后 55 个相邻帧对。

计时边界：M1 是旧日期、旧系统的记录，不能解释为纯芯片代差。VT 是 NV12 输入的 processor completion wall time，素材缩放在计时外；M1 表中 MLX 是不含 RGB 准备的 helper 往返。M5 表中 MLX 则采用包含缩放、CPU bitmap 输出、RGB packing、helper 传输与生成的完整准备路径。它们用于评估接入成本，不是等口径 GPU kernel 比赛；均未覆盖完整解码、显示、排队与输入延迟。

M5 诊断行（不含 RGB 准备）的 MLX median / P95 为：720p 11.843 / 12.224 ms，1080p 25.489 / 26.042 ms，1440p 45.320 / 46.237 ms。1080p 两种计时的中位数相差约 1.06 ms，单独消除 RGB 准备不足以追平 VT；通信、推理和输出的占比尚未拆分，不能把剩余耗时全部归为网络推理。

判断：M5 1080p VT 的 P95 占 33.33 ms 预算约 30%，MLX 占约 82%，分别剩约 23.36 ms 和 6.11 ms。当前路径 MLX 中位耗时约为 VT 的 2.7 倍。720p 两者都有余量；1440p VT 不支持，MLX 超预算。M1 那次 1080p MLX 比 VT 快，但两者均超预算，不能据此推广为全设备实时可用。

同轮 Small NR 包含准备的 median / P95：720p 88.222 / 89.181 ms，1080p 180.240 / 181.770 ms，1440p 319.780 / 323.762 ms。它是独立帧 NR 研究路径，不是 FG，也不能代表未来所有 NR 实现的性能上限。

## 延迟、格式与接入成本

公开事实：两者均需要相邻两张真实输入。Apple 低延迟接口直接指定 previous/source；MLX CLI 先收首帧，再收下一帧后生成结果。Apple 会在启动 session 时加载模型，官方提醒这可能超过一个帧周期。[Apple 配置](https://developer.apple.com/documentation/videotoolbox/vtlowlatencyframeinterpolationconfiguration)、[MLX CLI](https://github.com/iamwavecut/MLX-DLSS/blob/7870371e8bf6c03967213f1a5d40db6c5a3bee38/Sources/mlxdlss/FrameGenStreamCommand.swift)

判断：如果 A 在 0 ms 到达、B 在约 33.33 ms 到达，A/B 的中间帧最早也要等 B 到达后才能计算。要均匀显示 A→中间帧→B，播放器必须安排缓存和播放时钟。因此“推理 9.83 ms”不等于“只增加 9.83 ms 输入延迟”；实际代价取决于原有缓存、显示时机、截止时间和丢帧策略，不能给统一固定值。

公开事实：上游 CLI 默认 `batch=4`，凑齐 `batch+1` 张输入后处理一组；XFrame 明确使用 `--batch 1 --factor 2 --format u8`，默认 FP16。[上游 CLI](https://github.com/iamwavecut/MLX-DLSS/blob/7870371e8bf6c03967213f1a5d40db6c5a3bee38/Sources/mlxdlss/FrameGenStreamCommand.swift)、[本地参数](../../Sources/XFrame/MLXFrameGenerationBenchmark.swift)

判断：30 fps 下 batch4 的第一对输出，比 batch1 多等三次源帧到达，约 100 ms；吞吐优化不一定适合交互。当前 XFrame 已避免这个默认批处理等待，不能用“改 batch1”解释现有慢测量。

公开事实：VT 提供运行时像素格式、源/目标缓冲区属性、最大维度和最大像素数查询，能力随设备与配置而定；像素上限应按 `spatialScaleFactor=1` 查询纯插帧。[像素格式](https://developer.apple.com/documentation/videotoolbox/vtlowlatencyframeinterpolationconfiguration/supportedpixelformats)、[最大像素数](https://developer.apple.com/documentation/videotoolbox/vtlowlatencyframeinterpolationconfiguration/maximumpixelcount%28forspatialscalefactor%3A%29)

本地证据：当前 M1/M5 纯插帧查询均为 2,073,600 像素，足够 1920×1080、不够 2560×1440；这不是 Apple 所有设备和未来系统的固定上限。MLX 在现有 benchmark 跑过 1440p，但没有由此得到任意分辨率或所有设备实时可用的保证。

判断：VT 的 CVPixelBuffer 接口更贴近现有解码链。当前 MLX helper 要 RGB 准备、管道传输、结果读回，增加部署和生命周期管理工作。原生调用 MLX 模块可能减少 IPC，但必须实测收益，不能承诺解决模型计算成本。不要根据 GPU 使用率或框架名称猜测 VT 内部跑在 GPU 还是 ANE。

公开事实：VT `endSession()` 结束 session，之后必须重新启动才能处理新帧；该文档没有承诺即时中断单个在途任务。MLX CLI 是顺序流协议，当前 XFrame 以终止子进程结束 helper，没有逐帧取消协议。[Apple endSession](https://developer.apple.com/documentation/videotoolbox/vtframeprocessor/endsession%28%29)、[本地 helper 生命周期](../../Sources/XFrame/MLXFrameGenerationBenchmark.swift)、[上游 CLI](https://github.com/iamwavecut/MLX-DLSS/blob/7870371e8bf6c03967213f1a5d40db6c5a3bee38/Sources/mlxdlss/FrameGenStreamCommand.swift)

判断：正式串流需要有限队列、超时回退原帧、断流/切换时丢弃过期结果，并让原帧与合成帧共用正确 PTS；不能把模型处理完成等同于呈现成功。

## 画质和模型交付

公开事实：上游报告对照 NVIDIA 输出的约 59.9 dB PSNR，以及五段视频的抽帧重建结果，用于验证移植近似原视频路径；没有给出相同素材下与 Apple VT 的对照。上游还确认所检查的 310.7.0、310.8.0、310.9.16 FG 网络相同，Small NR 的更新不代表 FG 也换了网络。[固定版 FG 验证说明](https://github.com/iamwavecut/MLX-DLSS/blob/7870371e8bf6c03967213f1a5d40db6c5a3bee38/docs/frame-generation.md)

判断：现有证据不能回答哪一个对快速转镜、HUD 字体、粒子、遮挡、切镜与压缩伪影更好。Apple 视频演示和上游 vendor parity 也不等于真实 Xbox 操作验收。

公开事实：MLX-DLSS 项目代码采用 Apache 2.0，README 要求自行提供 NVIDIA 库提取权重，上游不附带或下载厂商权重。代码许可证不能替代权重的使用/分发条款。VT 由系统框架管理模型，无需应用另行分发这份 FG 权重。[LICENSE](https://github.com/iamwavecut/MLX-DLSS/blob/7870371e8bf6c03967213f1a5d40db6c5a3bee38/LICENSE)、[README](https://github.com/iamwavecut/MLX-DLSS/blob/7870371e8bf6c03967213f1a5d40db6c5a3bee38/README.md)、[Apple session 配置](https://developer.apple.com/documentation/videotoolbox/vtlowlatencyframeinterpolationconfiguration)

## 网上评价的证据边界

本轮检索没有找到可信的 MLX FG 与 VT 低延迟插帧同素材画质对比，不能把搜索不到解释为没有任何评测，也不能声称网上已有胜负共识。

- Apple 官方把低延迟插帧与面向高质量视频编辑的 Frame Rate Conversion 分开；后者的演示或评价不能直接归给本次接口。官方低延迟演示展示了平滑运动，但没有充分覆盖 Xbox 快速转镜、HUD、粒子和遮挡。[WWDC25](https://developer.apple.com/videos/play/wwdc2025/300/)
- MLX 上游的 59.9 dB 衡量移植输出与 NVIDIA 库输出的一致性，不是生成帧与真实中间帧的画质分数。五段视频另有真实中间帧对照，但没有 VT 同场成绩。[上游验证](https://github.com/iamwavecut/MLX-DLSS/blob/7870371e8bf6c03967213f1a5d40db6c5a3bee38/docs/frame-generation.md)
- Reddit 有用户称 Mac 上 DLSS 画质令人印象深刻，同时报告高延迟，但该帖测试的是 NR，不能作为 FG 更好的证据。[用户体验帖](https://www.reddit.com/r/macgaming/comments/1waz5g2/tested_dlss_5_on_apple_silicon_via_dlssmac/)
- 使用 VT 中间帧的 macOS 开发者讨论过变帧率采集和显示同步导致的重复帧、错过插帧时机。这是调度体验报告，不是 VT 与 MLX 的画质对比，也不证明 VT 算法本身存在这些缺陷。[开发者讨论](https://www.reddit.com/r/macgaming/comments/1tj1lp3/how_do_you_synchronize_an_irregular_capture/)

技术解释：MLX 的恢复实现包含两级卷积网络，在较低分辨率估计运动流与遮罩，再做全分辨率变形和混合。Apple 未在所查公开资料中披露低延迟模型的完整结构及硬件分工。因此当前速度差不能直接归因为 VT 使用 ANE、模型更小，或 MLX 画质更高。

## 后续范围

M5 FG 性能对照已完成，不再把补测它作为前置任务。后续优先围绕 VT 做真实串流验证：帧间隔、有限队列与过期结果丢弃、持续负载、画质和操作延迟。现有 benchmark 成绩不等于已接入实时播放。

MLX 保留为可选研究对照；若以后重新考虑接入，应先用同一段原生 60 fps 游戏录像抽帧成 30 fps，与 VT 比较恢复帧，确认额外成本是否换来足够的画质收益。当前没有必要为了选型继续优化 MLX 或 Small NR。本文仅记录选型与证据，不新增实现或发布版本。
