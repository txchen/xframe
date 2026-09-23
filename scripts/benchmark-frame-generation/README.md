# 30 → 60 fps frame-generation benchmark

This benchmark uses consecutive frames from an ordinary 1080p video. It compares
Apple's VideoToolbox low-latency interpolation with the **video-only MLX-DLSS
frame-generation port**. The latter is not NVIDIA's full game-integrated DLSS
Frame Generation pipeline: the video input has no game motion vectors or depth.

## Re-run on an M5 Mac

Requirements: macOS 26 or newer, Apple Silicon, Swift toolchain, Python 3.10+ with pip,
`ffmpeg`/`ffprobe`, `git`, `curl`, `unzip`, and locally extracted
`framegen.safetensors` weights. The script downloads source code and a video
fixture, builds the two tools, and writes all results under
`.build/benchmark-frame-generation/runs/<timestamp>/`.

```sh
FG_WEIGHTS=/absolute/path/framegen.safetensors \
  scripts/benchmark-frame-generation/run.sh
```

`FG_INPUT=/absolute/path/video.mp4` selects a different video; `FG_PAIRS=60`
controls how many frame pairs to measure. The default video is [Big Buck Bunny
1080p60](https://github.com/bower-media-samples/big-buck-bunny-1080p-60fps-30s)
at commit `c4c7ec6aa5d68944d32faa28f332f999c8866cbc` (SHA-256 checked by
`prepare-video.sh`). FFmpeg takes seconds 6–12 and converts to 1080p30 H.264,
180 source frames. The benchmark uses the first 61 for 60 generated midpoints.
Its source is [Blender Foundation's film](https://peach.blender.org/); the
hosting repository is a third-party sample mirror.

The [MLX-DLSS source](https://github.com/iamwavecut/MLX-DLSS) is pinned to
`0ca2deab092fe6f3e331bf4f616271dbc64521d0`. Supply your own weights;
they and the NVIDIA library from which they may be extracted are never copied
into tracked files. The pinned MLX core is 0.31.1. If the machine has no Metal
compiler, the script uses the matching published `mlx-metal==0.31.1` wheel's
precompiled `mlx.metallib`.

The current M1's extracted weights are at
`.build/experiments/mlx-dlss/models/weights/framegen.safetensors` (2,891,168
bytes; SHA-256 `21faede75312631273f930a6fc1aed17f1eb5ac4a476a485551afc6d7ced2958`).
`.build` is Git-ignored: transfer this file privately to the M5 or extract it
there from your own NVIDIA library using the [upstream weight-extraction
instructions](https://github.com/iamwavecut/MLX-DLSS/blob/0ca2deab092fe6f3e331bf4f616271dbc64521d0/README.md).
Set `FG_WEIGHTS` to the resulting M5 file path.

## M1 measurement (macOS 27.0, 16 GB, 2026-09-22)

Same 1920×1080, 30 fps input, 60 adjacent pairs, one generated frame per pair.
The 30 fps source interval is 33.33 ms.

| Path | Observed time | Meaning |
| --- | ---: | --- |
| VideoToolbox | 88.0–92.7 ms median; 91.9–93.8 ms p95 | `VTFrameProcessor.process` wall time, two sequential 60-pair runs, first five pairs excluded |
| MLX-DLSS `process-video` | 49.2 ms/frame | 2.952 s reported generation time / 60, excluding reported decode/encode/setup time |
| MLX-DLSS raw RGB stream | 57.3 ms/frame | 3.440 s / 60, includes pipe read/output and RGB conversion, excludes decode/encode |
| MLX-DLSS raw RGB stream GPU | ≥51.5 ms/frame | 3.089 s observed AGX process GPU time / 60, includes model startup and RGB conversion |

The DLSS full video process reported 61 input and 121 output frames at 60 fps.
The VideoToolbox output preview was generated successfully. Both measured
processing paths exceed the 33.33 ms per-pair budget on this M1 at 1080p; this
does **not** predict M5 throughput or interactive display latency.

`measure-gpu.py` samples the Apple GPU driver's private
`AGXDeviceUserClient.AppUsage.accumulatedGPUTime` counter by process ID. The
last observed count is a lower bound because the process can exit between
samples. It includes all GPU work charged to that process, not isolated kernel
timestamps. For VideoToolbox, the process counter was 0 in the run without
preview output; a run that also wrote a PNG showed 0.6 ms. VideoToolbox's
internal work was **not attributable via this counter**, so its GPU execution
time remains unknown. Zero must not be interpreted as free GPU processing.
Apple documents this API as a frame processor that loads an ML model, without
promising a particular hardware execution unit; no GPU-versus-ANE claim is
made here. See [Apple's VideoToolbox documentation](https://developer.apple.com/documentation/videotoolbox/vtlowlatencyframeinterpolationconfiguration).

The two implementations use different pixel formats (VideoToolbox NV12,
MLX-DLSS RGB8) and different algorithms. This is a capacity measurement, not
an image-quality comparison. It does not include a display loop, motion-vector
input, or a gameplay quality evaluation. VideoToolbox on this M1 accepts at
most 1920×1080 for pure temporal interpolation; the 2560×1440 Diablo II stream
would require scaling or another backend.
