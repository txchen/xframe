# MLX-DLSS 独立实验

Status: needs-info
Updated: 2026-09-22

## 目标与基线

用户选择 MLX-DLSS 作为实际实验基线。先测原生 CLI 的 NR 与 FG，再依据质量、持续吞吐和延迟决定是否接入 XFrame。当前不修改 XFrame 的播放管线。

- 上游：<https://github.com/iamwavecut/MLX-DLSS>
- 固定提交：`0ca2deab092fe6f3e331bf4f616271dbc64521d0`。
- 当前机器：M1 Mac mini，16 GB，macOS 27.0（26A428），Swift 6.4。
- 第二设备：用户的 M5 MacBook Air，配置和系统版本待记录。
- 独立目录：`.build/experiments/mlx-dlss/`；依赖、工具、模型和输出不进入 Git。
- 构建入口：`scripts/mlx-dlss-experiment.sh prepare`；采用 native Swift build system，release CLI、2 jobs、本地 Python venv 内 CMake/Ninja。

## 运行前所缺资料

本机未发现可用 Metal 离线编译器，`xcrun --find metal` 失败，`prepare-mlx-metallib.sh` 在生成 `.air` 时退出。需选用提供 Metal 编译器的 Xcode/Metal 工具链；实验脚本已加入提前检测。当前没有安装或切换系统工具链。

用户确认尚无真实模型权重，本轮先准备实验环境，不执行模型提取或推理。NR 需要 `NeuralRendering.dlssmodel` 或受支持的 `nvngx_dlssnr.dll` 310.8.0.0；FG 需要 `framegen.safetensors` 或 `libnvidia-ngx-dlssg.so.310.7.0`。上游不附带这些权重。SR 的模型准备还涉及一次 CUDA capture，因此不作为第一轮入口。

已有 `.build/fixtures/h264-1080p60.mp4` 和 `scaling-1080p60-120s.mp4`，可作格式/流程样例，但不能替代包含转镜、遮挡和 HUD 的真实游戏片段。第一轮 NR 静帧、FG 短片分别跑；模型输入成功后再扩大分辨率/片长。

## Metal 工具链恢复

本机 `xcodebuild -version` 明确报告当前为 Command Line Tools instance，需完整 Xcode。安装匹配系统的 Xcode 后，可用进程级 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` 选择它，避免改动全局选择；按 Apple 官方说明安装 Metal 组件（`xcodebuild -downloadComponent MetalToolchain`），以 `xcrun --find metal` 成功为准，然后重跑 `prepare`。Xcode 的首次启动/组件安装可能需要本机用户完成。来源：[Apple 附加组件说明](https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components)。

## 有权重后的命令

从 repo 根目录运行，下列路径是待用户提供/准备的模型，不代表已经存在：

```sh
scripts/mlx-dlss-experiment.sh prepare
scripts/mlx-dlss-experiment.sh run process-image INPUT.png \
  --output .build/experiments/mlx-dlss/nr-output.png \
  --model /absolute/path/NeuralRendering.dlssmodel
scripts/mlx-dlss-experiment.sh run process-video INPUT.mp4 \
  --output .build/experiments/mlx-dlss/fg-output.mp4 \
  --framegen-weights /absolute/path/framegen.safetensors --factor 2 --frames 30
```

每轮使用新的输出名称；上游默认拒绝覆盖。记录输入和模型 hash、上游提交、设备、实际输入分辨率/帧率、参数、处理用时、输出帧数与错误。离线 process-video 含媒体处理开销，不可冒充实时 GPU kernel 耗时或 controller-to-photon 延迟。

## 验收顺序

1. 构建 CLI 和 `mlx.metallib`，验证动态库可加载及命令入口。
2. 有模型后跑一张 NR 图像、一个两帧/短片 FG 样例，确认输出内容，而非仅进程返回成功。
3. 在 540p、720p、1080p 分别测预热/稳态和持续负载；先单独 NR/FG，再测组合。
4. 两机同片 A/B：细节、人物、HUD、小字、转镜、遮挡、切场、40–60 fps 输入；明确哪类改变可以接受。
5. 有界队列、时序调度和实际显示延迟进入下一阶段原型；离线导出达标不等于实时集成达标。

## 相关研究

- [补帧研究与延迟边界](../4k-post-processing/frame-interpolation-research.md)
- [NR / Metal 与 M1/M5 差异](../4k-post-processing/opendlss-nr-metal-research.md)

## 执行记录

- 已 clone 固定版本，并在隔离 venv 安装 CMake 4.4.3、Ninja 1.13.2。
- Xcode 默认 Swift 构建后端初始化报 `Unknown error parsing property list`；切换仓库已有的 `--build-system native` 路线。
- Metal library 构建已尝试并失败：缺少 `metal` 编译器，日志 `.build/experiments/mlx-dlss/metal-build.log`。
- 预检查按预期返回 69 并说明缺失工具；脚本语法检查通过。
- 未完成真实模型运行或性能验收。

- Release CLI 已成功构建；无参数启动按上游契约返回 usage / exit 2，验证了可执行文件加载和命令入口。此检查不初始化模型，也不证明 GPU 推理可用。构建日志：`.build/experiments/mlx-dlss/swift-build.log`。


### 2026-09-22：在线查找模型来源

用户要求自行上网查找。已下载原始库作静态检查，未执行 DLL/SO，也尚未提取权重或运行模型。

- FG：找到 [NVIDIA 官方 v310.7.0 库](https://github.com/NVIDIA/DLSS/blob/a291cc7d2cc642a51566f3dfd5376f635cd1b284/lib/Linux_x86_64/rel/libnvidia-ngx-dlssg.so.310.7.0)，7,764,600 bytes；SHA-256 `676cfeace1bf675a281cf234df619f24cef16a1259f36119ebdf01138468a057`。保存于 `.build/experiments/mlx-dlss/models/libnvidia-ngx-dlssg.so.310.7.0`。版本与上游提取器目标一致，尚未验证提取结果。
- NR：NVIDIA/DLSS 和 NVIDIA-RTX/Streamline 当前 main 文件树未发现 `dlssnr`。找到 [FF7R-DLSS5 v1 社区发布包](https://github.com/zhubaohi/FF7R-DLSS5/releases/tag/v1) 的 `nvidia.zip`，其中 DLL 为 165,840,496 bytes，SHA-256 `e16bcf15e16e13f527491cdf7845b2fe6521a738d8f7c9c721866a8496e1fc8e`。
- 该 NR DLL 与当前固定 MLX-DLSS 提取工具列出的已知 DLL hash `ceb6432f6fbdf44d886014bcd47241932bf8b67439feef9bbdd0961436662650` **不同**。已保存为候选样本，但未宣称兼容；即使版本号一致，也需继续比较权重资源。社区来源与官方发布区别保留，尚未验证 Authenticode 签名。
- 下载来源与 hash 收据：`.build/experiments/mlx-dlss/models/sources.json`。原始库、压缩包、模型不提交 Git。


### 2026-09-22：实际提取结果

用户授权提取后，在本地 tools-env 增加 numpy/safetensors，直接运行固定上游的独立 Python 提取/解码/打包脚本；未执行原始 DLL/SO，无需 GPU/Metal 编译器。

| 产物 | 字节 | MB（十进制） | MiB |
| --- | ---: | ---: | ---: |
| FG `framegen.safetensors` | 2,891,168 | 2.89 | 2.76 |
| NR packed 中间文件 | 147,716,314 | 147.72 | 140.87 |
| NR logical 中间文件 | 291,576,650 | 291.58 | 278.07 |
| NR `NeuralRendering.dlssmodel` 目录合计 | 291,677,678 | 291.68 | 278.17 |

最终两个模型合计 294,568,846 bytes，约 294.57 MB / 280.92 MiB。中间文件是转换过程的副本，不需重复算作运行时必需模型。

FG：92 tensors，1,441,568 parameters；全部数值有限。NR：DLL 静态版本 `310,8,0,0`，153 个 packed tensors 全部解码为 649 tensors，unsupported=0、opaque=0，全部数值有限；Metal 模型打包成功。NR packed→logical 的体积增加来自解包后的表示与布局，不是下载了更多模型。

这些检查证明文件结构被当前转换器完整识别，不证明 GPU 推理或与 NVIDIA 输出一致。NR 原始 DLL hash 仍不同于上游已知条目，保留该验证边界。

产物：`.build/experiments/mlx-dlss/models/weights/`；统计 `sizes.json`，各阶段日志 `nr-extract.json`、`nr-decode.json`、`nr-package.json` 位于实验根目录。Metal Toolchain 缺口仍待解决。


### 2026-09-22：按用户要求将压缩模型加入 Git

最终 FG ZIP（2,684,627 bytes）和 NR ZIP（127,373,759 bytes，分为两个小于 100 MiB 的部分）存于 `experiments/mlx-dlss/weights/`，使用普通 Git。原始 DLL/SO 和转换中间文件仍只保留在 `.build`。

换机运行 `python3 scripts/restore-mlx-dlss-weights.py` 即可按 manifest 校验并恢复，无需模型下载或 Git LFS。全新目录还原和重复运行校验均通过；模型推理尚未验证。该用户指令更新了此前“模型不提交 Git”的实验存储安排，不代表公开发布授权或模型许可变化。
