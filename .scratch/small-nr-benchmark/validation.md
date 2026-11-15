# Small NR benchmark and M1 investigation

Status: validated locally

XFrame adds Small NR at 720p, 1080p, and 1440p with a separate model-folder import.
The helper is pinned to MLX-DLSS `7870371e8bf6c03967213f1a5d40db6c5a3bee38`.
The model is the 31-block network extracted from `WEIGHTS_CC_SMALL_FP8` in NR 310.9.16.0.
Weights remain outside the public app. The local source receipt records a community mirror, not verified NVIDIA distribution.

## Measurement contract

The release path uses FP16, `metal-fused`, `standard`, processing scale 1, and vendor-aligned network geometry.
Stream protocol 4 runs GPU preprocessing and composition and returns packed RGB8.
Every input sets reset-history, constant-depth, and RGB8 flags. A zero motion plane accompanies it.
History resets before every frame, so the zero vectors never reproject an earlier frame.
These are independent frames, not temporal reconstruction with estimated or game motion.

Each size processes 61 consecutive fixture frames: six warmups and 55 measured frames.
The helper row includes input and guide transfers, GPU preprocessing, inference, composition, and RGB8 readback.
The preparation-inclusive row also includes fixture resize, CPU bitmap output, and RGB packing.
Both exclude decoding, startup, and display. The budget is 33.33 ms for 30 source frames per second.
Neither row is a pure GPU-kernel time or controller-to-photon latency.

The command-line entry calls the same benchmark as the UI:

```sh
/Applications/XFrame.app/Contents/MacOS/XFrame --benchmark-small-nr \
    /absolute/path/NeuralRendering-Small.dlssmodel /absolute/path/report.json
```

In the UI, end the streaming session, open **View → Post-Processing Benchmark…**, import the Small model folder, run, and export JSON.
The frame-generation model is a separate import and is not required for Small NR.

## Why the first M1 run took about 300 ms at 720p

The first implementation selected upstream `first-frame`, which builds features and composes output on the CPU.
Its 720p preparation-inclusive median was 299.48 ms and p95 was 302.33 ms.
The helper alone was 297.47 ms, so XFrame's RGB preparation was not the main cost.
See [the original report](m1-cpu-path.json).

A diagnostic helper recorded upstream preprocessing, inference, and postprocessing separately.
Five runs each discarded six warmups and measured six consecutive frames.
The median of the five stage medians was 67.46 ms preprocessing, 153.14 ms inference, and 47.07 ms postprocessing.
The inference timer includes graph construction and GPU completion, not only kernel execution.
These diagnostic runs locate the cost; they are not the release benchmark results.
See [stage timings](stage-profile.json).

## Controlled path and model comparisons

Apple M1, 8 CPU cores, 16 GiB RAM. Release-built helper, same fixture, Small weights, resolution, and rendering controls.
Five rounds alternated the listed cases. Each case used six warmups and six measured frames.
Host load before the investigation was approximately 1.5–2.0; no user processes or display settings were changed.
The helper output was read fully, checked for finite pixels, and every process exited successfully.

| 720p path | Median of run medians | Range of run medians |
| --- | ---: | ---: |
| Small, CPU pre/post, float output | 292.91 ms | 291.90–294.89 ms |
| Small, GPU pre/post, float output | 210.86 ms | 210.32–212.85 ms |
| HT, GPU pre/post, float output | 336.75 ms | 310.02–337.38 ms |

See [raw alternating runs](path-comparison.json).
The first frame from CPU and GPU Small paths was exactly equal in float32 output.
This single-frame check is not NVIDIA parity or a temporal-quality assessment.
See [output comparison](path-output-comparison.json).

A second five-round comparison kept GPU preprocessing and changed the output path:

| 720p path | Median of run medians | Range of run medians |
| --- | ---: | ---: |
| Small, float output | 209.64 ms | 206.04–211.15 ms |
| Small, GPU-composed RGB8 output | 204.43 ms | 203.47–205.71 ms |
| HT, GPU-composed RGB8 output | 332.16 ms | 329.46–332.60 ms |

See [output-path runs](output-path-comparison.json).
RGB8 first-frame output differed from float output by at most 0.001961, within half an 8-bit step.
See [quantization check](packed-output-comparison.json).

The HT results above were measured now using the same new helper as Small.
They are not historical measurements of the older runtime. Earlier project records contain old NR extraction checks and FG timing, not a measured M1 NR baseline.

GPU pre/post removes avoidable CPU work, but the model still dominates this path.
Even the improved 720p path is well above the 33.33 ms source-frame budget on M1.
No old-to-new NVIDIA speedup or M5 performance is inferred from these results.

## Final 0.1.2 package validation

The Developer ID-signed 0.1.2 build 3 ran the complete benchmark successfully on M1.
The preparation-inclusive rows, each with 55 samples after six warmups, were:

| Resolution | Median | P95 |
| --- | ---: | ---: |
| 720p | 210.74 ms | 214.55 ms |
| 1080p | 418.42 ms | 422.26 ms |
| 1440p | 698.98 ms | 704.47 ms |

See [the signed-app report](m1-gpu-path.json). This was one final package-validation run.
The controlled comparisons above were separate runs without concurrent builds.

All 204 tests passed. Release contract checks passed, including version-independent archive guards.
Apple accepted submission `9be46eec-daa5-4293-a348-9aa5803b8f41`.
Stapling, signature verification, and Gatekeeper assessment passed on the final extracted ZIP.
Real M5 MBA performance and live-game visual quality remain untested here.
