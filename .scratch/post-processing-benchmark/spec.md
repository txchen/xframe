# Built-in post-processing benchmark

XFrame exposes **View → Post-Processing Benchmark…** (Command-Shift-B). It opens
an independent window and uses a bundled, silent 1080p30 excerpt of *Big Buck
Bunny*, so a supported Mac can run it without downloading a video, installing
ffmpeg, or opening a game. A local `framegen.safetensors` file can be imported
once, or downloaded from an authorized HTTPS URL, to add the packaged
MLX-DLSS research helper. XFrame never bundles weights.
The app refuses to start a run while it owns an
active streaming session. The run is cancellable, does not change playback
preferences, and can export an ISO-dated JSON report.

The runner has one interface: run the fixed workload and return per-case
measurements. The window only starts, cancels, displays and exports it. The
tested cases are the XFrame backends that can execute from the shipped app:

| Case | Timed work | Budget |
| --- | --- | ---: |
| MetalFX 1080p → 1440p | NV12 video-still color conversion, scaler, composition | 16.67 ms |
| MetalFX 1080p → 4K | Same at 4K output | 16.67 ms |
| MetalFX 1080p → 4K + High sharpening | Adds XFrame's fused sharpening fragment | 16.67 ms |
| VideoToolbox 720p / 1080p / 1440p 30 → 60 fps | One midpoint from each of 60 consecutive decoded video-frame pairs at each supported size | 33.33 ms |
| Optional MLX-DLSS video 720p / 1080p / 1440p 30 → 60 fps | Same adjacent video pairs, passed as RGB8 to the packaged helper with batch size one | 33.33 ms |

MetalFX cases use 65 offscreen submissions, discard five warmups and report the
median and p95 of 60 GPU-command intervals. If Metal command timestamps are
unavailable, the result explicitly labels the command-completion wall-time
fallback. VideoToolbox uses the bundled moving video, resizes it before timing
when needed, discards five warmups, and reports median/p95 of 55
processor-completion wall times. Decoding, resizing, model
session startup and app startup are outside the timed intervals. The
VideoToolbox API does not attribute its internal GPU time to the caller, so
the report does not invent a GPU time. A failed or unsupported case has its
own status and reason, rather than a zero score.
MLX-DLSS takes 61 prepared RGB8 video frames and measures the wall time from
sending each next frame to receiving its generated midpoint. It excludes
decode, resize, and RGB preparation; it includes interprocess transfer, MLX
generation, and output transfer. Five pairs warm up the model and 55 provide
median/p95. An imported or downloaded model is verified against the known
DLSS SDK 310.7.0 SHA-256 and stored owner-only in
`~/Library/Application Support/XFrame/BenchmarkModels/`. XFrame automatically
uses the valid cached copy on later launches. A failed download or wrong hash
does not replace an existing cache; the URL is not saved. The report includes
only the model SHA-256. The helper is built from pinned source and its matching precompiled
Metal kernels into the release app, so the test does not need Swift, Python,
or network access on the machine running XFrame. The built app grows by roughly
155 MB. Building the app requires Python with pip to obtain matching kernels
if they are not already cached or supplied with `XFRAME_MLX_METALLIB`.
Frame-generation grades therefore apply to a native stream at each tested
input size; they do not include a downscale/interpolate/upscale chain.

**Headroom** means p95 at most 70% of the relevant frame interval;
**Tight** means p95 within the full interval; **Over budget** means it exceeds
that interval. This is a capacity hint, not a promise of 60 fps gameplay:
stream decode, other rendering work, presentation, thermal state, contention,
image quality and input latency are not measured. The app suggests the highest
spatial and frame-generation cases with measured headroom separately.
The 60 Hz goal is fixed for comparability even if the current monitor refreshes
faster. A run on another Mac should be compared by matching fixture SHA-256,
macOS version and timing kind.

MLX-DLSS remains a video-only research port, not an XFrame live rendering
backend. Its proprietary extracted weights cannot be bundled in the public
app. The [upstream project](https://github.com/iamwavecut/MLX-DLSS/blob/main/README.md)
provides no hosted weights, so XFrame ships no preset model URL; users enter
their own authorized HTTPS location. Selecting weights enables only the optional capacity test. The
[standalone benchmark](../../scripts/benchmark-frame-generation/README.md)
also remains available for deeper profiling. A future integrated MLX backend
must be judged separately for gameplay quality and latency.

On the M5, run `bash scripts/build-app.sh`, open `.build/XFrame.app`, then use
**View → Post-Processing Benchmark…**. The first build fetches the pinned
MLX-DLSS source and Metal wheel if absent. Import the M5's private
`framegen.safetensors` file once, or download it from an authorized HTTPS
location; subsequent runs use the cached copy without asking again. Export
JSON and compare `fixture`, model digest, macOS version, timing kind, and p95
across the two reports. Source URLs and model paths are not embedded in JSON.

## Verification on Apple M1 / macOS 27

The signed app visibly completed a nine-case run with selected local weights
and exported [M1 JSON with MLX-DLSS](m1-result-mlx.json). Its p95 times were:

| Case | p95 | Grade |
| --- | ---: | --- |
| MetalFX 1080p → 1440p | 1.87 ms GPU command | Headroom |
| MetalFX 1080p → 4K | 3.80 ms GPU command | Headroom |
| MetalFX 1080p → 4K + High sharpening | 4.20 ms GPU command | Headroom |
| VideoToolbox 720p 30 → 60 | 5.89 ms processor wall | Headroom |
| VideoToolbox 1080p 30 → 60 | 93.52 ms processor wall | Over budget |
| VideoToolbox 1440p 30 → 60 | Unsupported, 2,073,600-pixel limit | Unavailable |
| MLX-DLSS video 720p 30 → 60 | 34.52 ms helper round-trip wall | Over budget |
| MLX-DLSS video 1080p 30 → 60 | 69.09 ms helper round-trip wall | Over budget |
| MLX-DLSS video 1440p 30 → 60 | 117.87 ms helper round-trip wall | Over budget |

An earlier six-case UI export without weights is retained as
[M1 base JSON](m1-result.json). The sharp VideoToolbox 720p–1080p difference
was reproduced in three alternating runs and investigated with process stack
sampling in [the resolution-gap research note](vt-resolution-research.md).
The 1080p path spent substantial time in CPU resampling and host/ANE transfers;
Apple does not document why it chooses that path. Quality and live-pipeline
checks are still needed before offering a 720p downscale path. These are
candidate results for this M1, not M5 predictions.
