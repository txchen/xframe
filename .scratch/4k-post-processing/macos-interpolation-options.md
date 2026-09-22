# macOS interpolation candidates

Research date: 2026-09-22. Capability discovery only; no frame processing benchmark or visual acceptance performed.

## Apple VideoToolbox

- `VTLowLatencyFrameInterpolationConfiguration` is available from macOS 26. It accepts previous and current decoded frames and generates intermediate frames. Apple positions it for real-time receiving applications. Optional combined scaling is limited to 2x spatial enlargement plus one midpoint frame. [API](https://developer.apple.com/documentation/videotoolbox/vtlowlatencyframeinterpolationconfiguration), [Apple presentation](https://developer.apple.com/videos/play/wwdc2025/300/).
- The installed macOS 27 SDK header `VTFrameProcessor_LowLatencyFrameInterpolation.h` specifies discrete temporal phases: configuration value 1 permits 0.5; value 2 permits 0.25, 0.5, 0.75. Higher values improve temporal phase resolution but increase latency. A dynamic 40–60 fps input therefore needs scheduling and phase-selection evaluation; simple midpoint doubling is not exact resampling to 60 fps.
- `VTFrameRateConversionConfiguration` is available from macOS 15.4. It accepts source and next frames, phase positions, and optional precomputed optical flow; quality prioritization is configurable. Apple positions this path for high-quality video editing, so its suitability for interactive streaming needs measurement. [API](https://developer.apple.com/documentation/videotoolbox/vtframerateconversionconfiguration).
- Use runtime `isSupported`, configuration construction, pixel-buffer attributes, and session startup checks rather than assuming all Apple Silicon generations behave identically. The parent task's `.build/interpolation-support.swift` probe on this Apple M1 / macOS 27 reports support for both configurations and VT optical flow. This proves capability reporting only, not successful processing or real-time throughput. No verified universal M2/M3-only restriction was found in the sources inspected.

## RIFE

RIFE is an open-source learned interpolation algorithm. Its original project supports arbitrary interpolation times; its published 720p throughput example uses an NVIDIA 2080 Ti and must not be treated as a Mac performance result. [Original implementation](https://github.com/hzwer/ECCV2022-RIFE).

Deployment candidates include the existing [ncnn Vulkan port](https://github.com/nihui/rife-ncnn-vulkan), which publishes macOS binaries without requiring CUDA or PyTorch, and the independent [RifeMetal port](https://github.com/cinemore/rife-metal), whose maintainer documents MPSGraph plus a Metal warp kernel and a Swift package. These are separate implementations, requiring dependency, model, numerical correctness, and throughput evaluation before use in XFrame. RIFE's name does not establish 1080p real-time performance on this M1.

## Suggested evaluation order

First prototype VideoToolbox low-latency interpolation at decoded stream resolution, then compare with RIFE or the higher-quality VideoToolbox path if quality or phase restrictions require it. Measure end-to-end added delay, GPU processing time, missed display deadlines, HUD artifacts, scene changes, and 60→40→60 input transitions. Availability alone is not acceptance.

## Vision optical flow plus custom Metal synthesis

Vision's `VNGenerateOpticalFlowRequest` estimates per-pixel motion between images. It does not supply the complete interpolation pipeline: image warping, bidirectional consistency, occlusion handling, scene-cut fallback and output scheduling remain application work. This is a customizable candidate rather than a ready-made frame generator. [Apple Vision introduction](https://developer.apple.com/videos/play/wwdc2020/10673/), [request API](https://developer.apple.com/documentation/vision/vngenerateopticalflowrequest).

## MetalFX frame interpolation

Apple's documented integration takes rendered images, motion vectors and depth. Decoded xCloud video supplies images but not engine motion/depth; reconstructed inputs would require a separate feasibility and fidelity evaluation. This is distinct from the already-integrated MetalFX Spatial scaler. [Apple MetalFX interpolation presentation](https://developer.apple.com/videos/play/wwdc2025/211/).

The same local Apple M1/macOS 27 probe returned true for `MTLFXFrameInterpolatorDescriptor.supportsDevice`. This removes an assumed hardware-support blocker, not the input-data or performance requirements. Probe output is retained in `.build/interpolation-support.log`; it did not start a processing session or modify the running app.
