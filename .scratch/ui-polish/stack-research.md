# Native UI and video stack review

Reviewed 2026-09-21 against source at `25a4175`, before UI polish changes. This is a code and primary-documentation review, not an Instruments benchmark.

## Conclusions

- Keep the hybrid architecture. Playback already uses an AppKit `NSWindow` and `MTKView`; SwiftUI hosts the account and catalog interfaces, not decoded video frames. Rewriting the catalog in AppKit does not replace the decoder or renderer. Evidence: `Sources/XFrame/XFrameApp.swift`, `MetalRenderer.swift`.
- There is no universal performance ranking established by the reviewed sources. AppKit provides direct control over view lifecycle and custom drawing; SwiftUI introduces dependency-driven update work. Whether that work matters depends on the actual screen, data flow, and measured frame deadlines. Apple recommends finding long or unnecessary updates with Instruments, not assuming the framework is the bottleneck. [Optimize SwiftUI performance with Instruments](https://developer.apple.com/videos/play/wwdc2025/306/), [Demystify SwiftUI performance](https://developer.apple.com/videos/play/wwdc2023/10160/).
- A pure-AppKit rewrite would not even guarantee avoiding SwiftUI internally on modern macOS: Apple describes SwiftUI-backed rendering for controls including `NSSlider`, `NSSwitch`, and `NSSegmentedControl`. Apple explicitly supports incremental mixing of both frameworks. [Use SwiftUI with AppKit and UIKit, WWDC26](https://developer.apple.com/videos/play/wwdc2026/272/).
- The video path is an appropriate efficient native architecture: hardware-required VideoToolbox decoding, IOSurface-backed NV12 buffers, CoreVideo texture-cache import, and one Metal color-conversion/scaling render pass. It is not justified to call it the fastest possible implementation without measurements. [VideoToolbox](https://developer.apple.com/documentation/videotoolbox), [Apple's CVPixelBuffer/Metal interop guidance](https://developer.apple.com/videos/play/wwdc2020/10090/).

## Actual data path

`WebRTC H.264 access unit -> Annex B parsing / length-prefix conversion -> CMSampleBuffer -> asynchronous VTDecompressionSession -> RTCCVPixelBuffer -> LiveVideo latest-frame slot -> CVMetalTextureCache NV12 plane textures -> Metal fragment shader -> MTKView drawable`

Code evidence:

| Area | What is established | Limitation |
| --- | --- | --- |
| Decoder | `HardwareH264Decoder.configure` requires hardware acceleration and checks `UsingHardwareAcceleratedVideoDecoder`. | Hardware use is not a latency measurement. |
| Decode output | Requests video-range NV12, Metal compatibility, and IOSurface backing. | System-internal implementation copies are not observable from this code audit. |
| Decoded frame transport | `RTCCVPixelBuffer` wraps the existing buffer; `LiveVideo` retains only the newest frame under a lock. | WebRTC can have its own scheduling/buffering upstream; a one-frame app slot is not a one-frame end-to-end guarantee. |
| GPU import | `VideoTextures` creates `r8Unorm` and `rg8Unorm` plane views through `CVMetalTextureCache`. Pixel planes are not copied into a CPU RGB image. | Two wrappers are created per displayed frame; cache behavior and allocation costs need profiling. |
| GPU lifetime | Pixel buffer and both `CVMetalTexture` objects remain retained through command-buffer completion. | This follows the lifetime requirement in Apple's interop guidance. |
| Rendering | One four-vertex quad, Aspect Fit, YUV-to-RGB conversion in the fragment shader, framebuffer-only drawable. | Full-screen fragment work still scales with Backing Pixels; no GPU duration measurements exist here. |
| Queue bounds | One pending decoded frame; at most three in-flight GPU command buffers; no task per decoded image. | Three in-flight commands are a throughput/latency tradeoff, not proof of minimum latency. |

The cache-and-lifetime pattern matches Apple's recommendation to use `CVMetalTextureCache` for simpler surface tracking and reused IOSurface bindings. The cited session discusses ProRes decoding, but its CoreVideo-to-Metal resource management applies to these buffers; it is not evidence about xCloud H.264 codec performance. [Decode ProRes with AVFoundation and VideoToolbox](https://developer.apple.com/videos/play/wwdc2020/10090/).

## Concrete remaining opportunities

1. **Acquire drawables only when rendering is needed.** `MetalRenderer.draw` currently obtains `currentRenderPassDescriptor`, `currentDrawable`, and a command buffer before the no-new-frame/same-size early return. At a requested 120 Hz, that can perform avoidable drawable acquisition on idle ticks. Move the decision before acquiring the drawable while preserving resize redraws and frame ownership. Apple recommends acquiring drawables as late as possible and holding them briefly. This is an identifiable opportunity, not a measured speedup. [Metal Best Practices: Drawables](https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/Drawables.html).
2. **Measure compressed-byte allocations.** `nalUnits` copies `Data` to `[UInt8]`, creates per-NAL `Data`, constructs a length-prefixed payload, then copies it into a `CMBlockBuffer`. These are compressed bytes, not decoded pixel planes. A range-based parser and single owned sample allocation could reduce work, but lifetime safety and corrupted-packet tests matter more than assuming this is the bottleneck. Evidence: `HardwareH264Decoder.swift`.
3. **Measure frame pacing and main-thread contention.** The renderer is `@MainActor` and requests 120 Hz even for approximately 60 fps streams. Compare display-aligned pacing strategies with decode-to-present latency, idle wakeups, CPU, and power. A lower refresh request could reduce wakeups but increase waiting time, so do not change it blindly. Catalog layout can still compete for the same main thread despite not wrapping the video view. Evidence: `MetalRenderer.swift`, `XFrameApp.swift`.
4. **Avoid repeated catalog computation if traces show it matters.** `CloudLibrary.page` recomputes filtering and sorting on every read, and multiple view branches read it. `categories` reconstructs a set and sorts it. Cache derived catalog results when their inputs change, or at least evaluate a page once per body, if profiling indicates significant cost. Pagination and lazy views already bound view creation. Evidence: `CloudLibrary.swift`, `GameLibraryQuery.swift`, `GameBrowserView.swift`.
5. **Add latency instrumentation before architectural replacement.** Useful intervals are access-unit submission to decode callback, renderer receipt to GPU submission, GPU start/end, and presentation. Report distributions and dropped frames, not only average fps; local intervals do not measure network/controller-to-photon latency. Compare streaming with the catalog idle and while searching/scrolling. Apple's SwiftUI Instruments guidance distinguishes UI-update work from unrelated CPU spikes. [Optimize SwiftUI performance with Instruments](https://developer.apple.com/videos/play/wwdc2025/306/).

Do not claim that adding `kVTDecompressionPropertyKey_RealTime = true` fixes latency: Apple documents that true is already the default for decompression sessions. [RealTime property](https://developer.apple.com/documentation/videotoolbox/kvtdecompressionpropertykey_realtime).

## Decision boundary

Polish the catalog in SwiftUI now; preserve the native AppKit/Metal playback surface. If measured library scrolling or update costs remain problematic after targeted fixes, evaluate an AppKit collection view for that specific component, not a whole-app rewrite. This is an engineering recommendation based on current code and Apple's interop support, not a claim that SwiftUI is always equally fast. [NSHostingController](https://developer.apple.com/documentation/swiftui/nshostingcontroller).

Unmeasured: CPU/GPU time, power, motion-to-photon latency, audio/video synchronization under load, system compositor copies, and comparative AppKit-versus-SwiftUI catalog benchmarks. No controller, cloud session, or UI interaction was performed for this review.
