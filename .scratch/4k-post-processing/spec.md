# 4K display and TV post-processing

Status: needs-triage
Updated: 2026-09-22

## User goal

Improve decoded 1080p cloud video on a 4K monitor/TV. Provide optional upscaling, 30-to-60 frame interpolation and neural visual enhancement that can be combined when hardware and measured latency permit. M1 Mac mini is the first acceptance device. GTA VI is a user-motivating future use case, conditional on actual service availability and observed game cadence; no release, streaming availability or 30 fps behavior is assumed.

## Delivery order

1. Spatial upscaling and restrained sharpening: native MetalFX Spatial first, ordinary scaling bypass and fullscreen integer scaling for comparison; evaluate FSR 1 EASU/RCAS port to Metal as an alternate backend. Preserve color/range, aspect ratio, readable UI and resizing. 1080p-to-2160p is the initial case; no claim to recover all missing native-4K detail.
2. Client-side video frame interpolation: a first-class priority, initially optional/experimental, targeting 30 unique source frames to 60 displayed frames per second. Evaluate optical-flow/image-only methods on decoded video. A 60 fps transport may contain repeated 30 fps game frames: identify content cadence before interpolation, do not equate received FPS with unique game FPS. Evaluate MetalFX interpolation input and device requirements before choosing it; engine-side motion/depth buffers are not presently available.
3. DLSS 5-style neural rendering research: inspect OpenDLSS-NR and other primary-source implementations for Metal/Apple Silicon feasibility. Evaluate required inputs, motion/history estimation, supported GPU operations, weights availability/distribution rights, memory, temporal stability and timing. This is not a promise of official NVIDIA DLSS support on Mac. A runnable Vulkan implementation is not proof of native M1 compatibility or real-time 4K performance.
4. Integrated 4K TV profile: independently toggle upscale, interpolation and neural enhancement; expose only supported combinations. Benchmark processing order and resolution rather than unconditionally running all passes at 4K/60. Source-backed comparison baseline from Veyra: decode/color normalization → source-derived motion branch → spatial upscale → optional NR residual enhancement → interpolation of enhanced real frames → XFrame HUD → present. Compare NR-before-SR and lower-resolution processing as separate alternatives; do not assume the earliest proposed interpolation-before-enhancement ordering is preferable. Veyra’s alternative order differs across providers. See [source-audited processing order and caveats](veyra-nrvideo-research.md#verified-processing-order). Game HUD is already baked into the video and needs artifact evaluation; only XFrame's own HUD can be cleanly composited afterward.

## Acceptance

- Compare each stage alone and combinations against an unprocessed baseline; no assumption that enabling everything improves perceived quality.
- Record source/unique/received/generated/displayed rates separately, actual presentedTime latency, processing mean/p95, memory, GPU load, sustained thermal behavior and A/V sync on M1 and 4K TV.
- A 60 Hz output has 16.67 ms per display interval; this is a total throughput budget, not an allowable extra latency for every pass. Set stage budgets from prototypes.
- Interpolation must bound look-ahead and queue age, handle scene cuts, menus, subtitles, fast pans, occlusion, missing/repeated frames and source FPS changes, and fall back safely if deadlines cannot be met. It improves visual cadence, not the game's simulation/input-response FPS; report added buffering honestly.
- Test 1080p content with compression artifacts, text and foliage. Avoid oversharpening ringing, neural flicker, changed faces/art direction and interpolated UI distortion. Keep all enhancement optional with a clear original-image bypass.
- Preserve controller throughput and low-overhead HUD; auto-downgrade expensive optional processing before harming the base stream. Test supported 60/120 Hz TV modes and document display-side processing effects separately.

## Primary-source feasibility notes

- [Apple MetalFX](https://developer.apple.com/documentation/MetalFX): spatial scaling is the initial native backend. [Metal capability tables](https://developer.apple.com/metal/capabilities/) and [Metal 4 interpolation overview](https://developer.apple.com/videos/play/wwdc2025/211/) are inputs to per-device/API checks; no interpolation integration has been validated here.
- [AMD FSR 1](https://gpuopen.com/fidelityfx-superresolution/) is spatial upscaling; evaluate a Metal shader port, not a direct plug-in of a Windows SDK. [FSR 2](https://gpuopen.com/fidelityfx-superresolution-2/) requires color, depth and velocity buffers. Decoded xCloud video does not expose engine depth/velocity; codec motion information is not an equivalent integration contract.
- [NVIDIA DLSS 5 description](https://www.nvidia.com/en-eu/geforce/news/dlss-5-3d-guided-neural-rendering/) describes neural lighting/material enhancement using color and motion vectors; it is distinct from super resolution and frame generation.
- [OpenDLSS-NR README](https://github.com/maanHimself/OpenDLSS-NR), checked 2026-09-22, explicitly describes same-resolution neural rendering and says DLSS-SR is not implemented. Main-path requirements include Windows/NVIDIA Ada or newer and NVIDIA Vulkan extensions; WebGPU is a separate port. Author-reported RTX 4070 SUPER minimum timings are 7.8 ms at 1080p and 29.3 ms at 4K, not M1 benchmarks. We have not reproduced its results, acquired weights or run the project. Assess model licensing separately from the repository code license before redistribution.

This update records scope and strategy only; no processing shaders, model integration or game/session changes are included.

## Veyra-NRVideo lessons incorporated

[Implementation study and source references](veyra-nrvideo-research.md), pinned to `df41580f7fa0d2b26718f355640470e8cb94b324`, are required reading before the first combined-processing prototype. This study is complete; implementation and M1 feasibility remain open.

- **Upscaling/NR:** keep source/base/NR/flow/FG/output sizes explicit. Evaluate lower-resolution NR residuals over a preserved high-resolution base; verify chroma/color first. A 4K texture does not establish native-4K detail or 4K inference.
- **Motion contract:** estimate from unenhanced real-frame pairs; track identity, direction, pixel/normalized units, extent scale, confidence and validity. Optical flow is an estimate, not engine motion/depth. Validate motion/occlusion independently of the visual enhancement.
- **Temporal state:** presentation skips, repeated displays and true content discontinuities are different events. Preserve history only when valid for the actual source gap; do not copy Veyra’s 250 ms tolerance into our display queue. Keep source PTS independent of arrival and presentation timing.
- **Generation scheduling:** generate only useful target-rate frames, count real/generated/hold separately, protect source coverage and use bounded deadlines/resources. Verify complete consumer lifetime before texture reuse; settings revisions must not mix in an A/B pair.
- **Acceptance:** begin with 2X, measure pair look-ahead plus actual presentation, and compare order/resolution at fixed inputs. Vendor Present throughput is not scanout or controller-to-photon latency. Upstream high-multiplier/full-chain limitations remain relevant cautions, not proof of M1 limits.
- **Controls:** evaluate queue depth, display synchronization and output cap as separate mechanisms; avoid adding empirically identical presets. Keep current XFrame queue options until its own evidence supports a change.

Capture-card/PS5 specifics inform common input and timing contracts; this research does not add PS5 or capture support to XFrame’s product scope. No upstream implementation is copied.
