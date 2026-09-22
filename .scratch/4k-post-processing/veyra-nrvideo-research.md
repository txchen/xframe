# Veyra-NRVideo: implementation lessons for XFrame

Date: 2026-09-22. Research only; no XFrame implementation, upstream code copying, binary execution, model downloads or device/session changes.

## Scope and evidence

Inspected upstream [Likely7/Veyra-NRVideo](https://github.com/Likely7/Veyra-NRVideo) at **df41580f7fa0d2b26718f355640470e8cb94b324** (2026-09-22), including current code, 1.4.4 release notes and older experiment records. Read-only reference checkout is ignored under `.build/references/veyra-nrvideo`. Repository documents/UI in XFrame remain English.

Evidence labels used below: **implemented** means visible in this pinned source, **upstream measurement** means the author's report, not reproduced by us, and **XFrame proposal** means an inference requiring our own implementation and validation. Neither promotional GTA6/120fps wording nor software submission counters establish physical display quality, availability of a particular game, or M1 feasibility.

Upstream supports Windows video/image/capture and PS5 Remote Play inputs. It integrates vendor-specific D3D12/NGX/NVOF and frame-generation paths. We borrow architecture and validation lessons, not code or Windows-specific tuning constants. Code is GPLv3; its streaming combination additionally has AGPL-related obligations; model/runtime rights are separate. See [upstream README](https://github.com/Likely7/Veyra-NRVideo/blob/df41580f7fa0d2b26718f355640470e8cb94b324/README.md) and [third-party notices](https://github.com/Likely7/Veyra-NRVideo/blob/df41580f7fa0d2b26718f355640470e8cb94b324/THIRD_PARTY_NOTICES.md). No license compatibility conclusion is needed to independently implement these design ideas.

## Reading order and historical traps

Use current executable branches and the latest release record before older design plans. The repo retains chronological documents and some stale comments:

- The initial product spec describes a single post-SR guidance extent. Current `ResolutionPlan` separates source, base, NR, flow, FG and output extents; optical flow is source-space and can be reduced. Do not port the old diagram as the current architecture.
- An older repair used a dropped-frame-count limit; current code retains history according to a positive source PTS gap up to 250 ms, unless a real discontinuity exists. Nearby old comments still mention two dropped frames.
- Older experiments interpreted DXGI statistics as physically displayed frames. Release 1.4.4 retracts this interpretation; even remaining member names/comments do not restore that evidence.
- Moving provider Present to a helper thread was tried and reverted. A plausible plan in an earlier report is not an accepted optimization.

Sources: [ResolutionPlan](https://github.com/Likely7/Veyra-NRVideo/blob/df41580f7fa0d2b26718f355640470e8cb94b324/include/veyra/pipeline/ResolutionPlan.h#L29-L49), [current history decision](https://github.com/Likely7/Veyra-NRVideo/blob/df41580f7fa0d2b26718f355640470e8cb94b324/src/engine/EngineController.cpp#L1095-L1153), [release corrections](https://github.com/Likely7/Veyra-NRVideo/blob/df41580f7fa0d2b26718f355640470e8cb94b324/docs/RELEASE_NOTES_1.4.4.md#L7-L26), [reverted experiments](https://github.com/Likely7/Veyra-NRVideo/blob/df41580f7fa0d2b26718f355640470e8cb94b324/docs/FG_INDEPENDENT_REPAIR_EXECUTION_2026-09-22.md#L27-L34).

## Main conclusions

- Compute source-derived optical flow before neural appearance changes; adapt that motion explicitly into each consuming resolution and convention.
- Treat **SR → NR residual composition → FG** as the first source-backed comparison path, not the only correct order. Compare NR-before-SR separately; do not assume every backend implements the same branch.
- Keep NR/flow cost independent of final 4K output size; evaluate low-resolution neural residual composition over a preserved high-resolution base.
- Separate temporal history retention, display freshness, frame-pair look-ahead and output pacing. They are different budgets.
- Validate real-frame coverage, generated-frame positions and actual presentation cadence; all-on output counters alone are insufficient.

## Verified processing order

The current README recommends **SR → NR → FG**, with an experimental preview-only **NR → SR → FG** option that may save work but worsen ghosting/edges. This is not merely a diagram: the graph invokes SR before NR unless `nrBeforeSr` is true, then performs NR and residual composition, and in the alternative path invokes SR afterward. FG consumes the resulting enhanced picture. The controller enables the alternate order only for a non-image preview with NR enabled and actual upscaling; exports retain their separate normal graph setup. [README lines 89–95](https://github.com/Likely7/Veyra-NRVideo/blob/df41580f7fa0d2b26718f355640470e8cb94b324/README_EN.md#L89-L95), [order branch](https://github.com/Likely7/Veyra-NRVideo/blob/df41580f7fa0d2b26718f355640470e8cb94b324/src/pipeline/EnhanceGraph.cpp#L1777-L1798), [residual then optional SR](https://github.com/Likely7/Veyra-NRVideo/blob/df41580f7fa0d2b26718f355640470e8cb94b324/src/pipeline/EnhanceGraph.cpp#L1885-L1897), [controller gate](https://github.com/Likely7/Veyra-NRVideo/blob/df41580f7fa0d2b26718f355640470e8cb94b324/src/engine/EngineController.cpp#L323-L327).

**Guidance is a parallel branch from original source-space color, before SR/NR**, not flow estimated from the hallucinated/enhanced output. In current graph code, one motion result is adapted for the NR and full working resolutions and reused by consumers. FG receives the enhanced color plus that adapted source-derived motion. Thus “FG last” does not mean “compute all motion last.” [flow source and execution](https://github.com/Likely7/Veyra-NRVideo/blob/df41580f7fa0d2b26718f355640470e8cb94b324/src/pipeline/EnhanceGraph.cpp#L1626-L1643), [flow adaptation](https://github.com/Likely7/Veyra-NRVideo/blob/df41580f7fa0d2b26718f355640470e8cb94b324/src/pipeline/EnhanceGraph.cpp#L1708-L1717), [FG inputs](https://github.com/Likely7/Veyra-NRVideo/blob/df41580f7fa0d2b26718f355640470e8cb94b324/src/pipeline/EnhanceGraph.cpp#L1972-L1997).

For XFrame, an appropriate **experiment baseline**, not a universal quality conclusion, is: decoded real frames → color normalization; derive motion from the unenhanced pair; spatial upscale → optional neural residual enhancement → interpolate enhanced real-frame pair → paced presentation. Compare NR-before-SR as a separately measured alternative. Keeping FG last avoids running expensive enhancement on every generated intermediate frame, but the actual compute/quality balance still needs M1 measurements.

## Resolution domains and residual enhancement

Provider caveat: the DLSS SR branch explicitly chooses residual color for NR-before-SR, whereas the FSR branch at this revision still passes `srcRgba_`. Therefore the alternative-order description above is verified for the NVIDIA DLSS/Video SR routes, not a guarantee of identical behavior across every selectable backend. Do not infer successful combination acceptance from a shared settings flag. [DLSS input selection](https://github.com/Likely7/Veyra-NRVideo/blob/df41580f7fa0d2b26718f355640470e8cb94b324/src/pipeline/EnhanceGraph.cpp#L1744-L1755), [FSR input selection](https://github.com/Likely7/Veyra-NRVideo/blob/df41580f7fa0d2b26718f355640470e8cb94b324/src/pipeline/EnhanceGraph.cpp#L1725-L1737).

Veyra explicitly models six extents: source, base, NR, flow, FG, output. Upscaling preserves aspect ratio within a target box. Realtime NR caps processing to a 1080-high / 16:9-bounded extent, with additional lower/higher policies; native NR leaves the base size. Flow ordinarily uses source extent and can shrink when the realtime NR extent is smaller than the source. FG/output use the base extent. Export bypasses the realtime NR size reduction. Consequently a 4K output is not proof that NR or flow ran at 4K. [ResolutionPlan](https://github.com/Likely7/Veyra-NRVideo/blob/df41580f7fa0d2b26718f355640470e8cb94b324/include/veyra/pipeline/ResolutionPlan.h#L12-L50).

The shader preserves the high-resolution base, computes the difference between lower-resolution NR output and its input, and edge-guides that residual back onto the base. It has independent darkening/brightening/chroma/luma strengths, a shadow safeguard, and protected/feathered regions; it returns the unchanged base for zero strength or fully protected pixels. This is more nuanced than enlarging the entire low-resolution neural output. [residual shader](https://github.com/Likely7/Veyra-NRVideo/blob/df41580f7fa0d2b26718f355640470e8cb94b324/shaders/NrResidualComposite.hlsl#L7-L44).

XFrame should carry explicit resolution and color-space metadata per stage, and evaluate low-resolution enhancement + residual reconstruction as a cost-saving option. Protecting source HUD/text/minimaps deserves an acceptance corpus; it is not equivalent to possessing an engine-provided UI mask.

## Optical flow: what is implemented

The motion backends are NVIDIA NVOF, AMD FidelityFX optical flow, and GPU DIS FAST. NVOF remains the default; upstream reports DIS substantially slower on an RTX 5070 synthetic 1080p test, so portability is not a speed claim. [backend enumeration](https://github.com/Likely7/Veyra-NRVideo/blob/df41580f7fa0d2b26718f355640470e8cb94b324/include/veyra/engine/EnhancementSettings.h#L54-L70), [README caveat](https://github.com/Likely7/Veyra-NRVideo/blob/df41580f7fa0d2b26718f355640470e8cb94b324/README_EN.md#L141-L145).

GPU DIS uses two leased slots, converts source pairs to luma, estimates both directions, then validates current-to-previous flow using forward/backward consistency and photometric error. Out-of-bounds/nonfinite estimates lose trust; the output motion is confidence-weighted. Slot completion fences prevent reuse while in flight. These safeguards are valuable interface requirements even if XFrame ultimately selects a completely different Metal implementation. [provider setup](https://github.com/Likely7/Veyra-NRVideo/blob/df41580f7fa0d2b26718f355640470e8cb94b324/src/guidance/GpuDisOpticalFlow.cpp#L29-L44), [pair identity and fences](https://github.com/Likely7/Veyra-NRVideo/blob/df41580f7fa0d2b26718f355640470e8cb94b324/src/guidance/GpuDisOpticalFlow.cpp#L46-L87), [validation shader](https://github.com/Likely7/Veyra-NRVideo/blob/df41580f7fa0d2b26718f355640470e8cb94b324/shaders/GpuDisValidate.hlsl#L9-L24).

Motion is not a format-free texture: resizing the flow multiplies vector magnitudes by the output/input extent ratio; NR receives pixel-space motion while the DLSS FG adapter applies negative reciprocal working dimensions. XFrame needs an explicit motion contract covering pair identity, direction, units, scale, color convention, confidence, and validity. An image-sized motion texture with the wrong sign or scale can still render and be wrong. [FlowAdapt](https://github.com/Likely7/Veyra-NRVideo/blob/df41580f7fa0d2b26718f355640470e8cb94b324/shaders/FlowAdapt.hlsl#L1-L8), [NR guidance](https://github.com/Likely7/Veyra-NRVideo/blob/df41580f7fa0d2b26718f355640470e8cb94b324/src/pipeline/EnhanceGraph.cpp#L1818-L1831), [FG adaptation](https://github.com/Likely7/Veyra-NRVideo/blob/df41580f7fa0d2b26718f355640470e8cb94b324/src/pipeline/EnhanceGraph.cpp#L1990-L1997).

Do not infer all providers use bidirectional validation merely from the GPU DIS implementation. An older dedicated NVOF bidirectional experiment explicitly retained default FORWARD and said its synthetic fixed-pair success did not prove natural NR/FG benefits. [older bounded experiment](https://github.com/Likely7/Veyra-NRVideo/blob/df41580f7fa0d2b26718f355640470e8cb94b324/docs/REVIEW_BIDIRECTIONAL_FLOW_2026-09-08.md#L3-L11).

## Video guidance is not native engine integration

The graph initializes constant depth (0.9 for FG, 0.5 for NR), supplies zero motion when unavailable, and labels source video's depth as a fallback rather than engine depth. NR input/output extents are equal, distinguishing neural image enhancement from SR. Captured video cannot recover authoritative engine motion, depth, or pre-composited UI merely by adapting it to an SDK signature. [depth initialization](https://github.com/Likely7/Veyra-NRVideo/blob/df41580f7fa0d2b26718f355640470e8cb94b324/src/pipeline/EnhanceGraph.cpp#L383-L386), [constant values](https://github.com/Likely7/Veyra-NRVideo/blob/df41580f7fa0d2b26718f355640470e8cb94b324/src/pipeline/EnhanceGraph.cpp#L507-L508), [NR resources and extents](https://github.com/Likely7/Veyra-NRVideo/blob/df41580f7fa0d2b26718f355640470e8cb94b324/src/pipeline/EnhanceGraph.cpp#L1818-L1827).

A/half interpolation needs both A and B; the frame-window contract says the midpoint is generated after B arrives. This introduces a latency tradeoff at a 30fps source even if the GPU kernel is fast. Its declared third C frame is validation only, not a third DLSSG input; the header alone does not prove a production mode exercises that additional lookahead. [FrameWindow contract](https://github.com/Likely7/Veyra-NRVideo/blob/df41580f7fa0d2b26718f355640470e8cb94b324/include/veyra/pipeline/FrameWindow.h#L3-L25).

For XFrame the core unresolved gate is distinguishing 30 unique game frames carried by a 60fps stream from genuinely unique 60fps content. Neither screenshot quality nor a provider's generated-frame counter proves this source-cadence problem has been solved. Upstream's NR review explicitly avoided adding a synchronous duplicate detector. [bounded review decision](https://github.com/Likely7/Veyra-NRVideo/blob/df41580f7fa0d2b26718f355640470e8cb94b324/docs/NR_QUALITY_PERFORMANCE_ACCEPTANCE_2026-09-21.md#L29-L35).

## Migration decisions for XFrame

| Lesson | Decision | Validation still required |
| --- | --- | --- |
| Original-frame optical flow shared by later passes | Adopt as motion-prototype baseline | Metal implementation, sign/scale/confidence and compressed-video robustness |
| Independent processing extents and residual reconstruction | Add to NR/upscale comparison plan | M1 cost, thin-detail retention, temporal stability |
| SR → NR → FG, with NR-before-SR alternative | Compare both; no universal fixed order yet | Same source/output dimensions and model/settings, actual provider behavior |
| Source identity/PTS and coherent history epochs | Adopt as future frame-graph requirements | Skip, repeat, reconnect, cut, resize and settings-transition cases |
| Output cap reduces generation work | Adopt as scheduler requirement | 30-in-60 detection, 60/120 Hz deadlines, source coverage |
| GPU resource leases plus completion/consumer fences | Adopt lifetime principle with native Metal primitives | In-flight reuse and teardown tests; no D3D fence-value translation |
| NVOF, NGX, DLSS/XeSS provider swapchains and constant-depth SDK adapters | Reference only; not directly portable | Apple-supported path and image-only algorithm suitability |
| Upstream tuning thresholds and RTX throughput/power | Do not adopt as M1 defaults or benchmarks | Controlled local measurements |

## Source cadence and clocks

**Implemented:** Veyra distinguishes transport cadence from changing content. Its `ContentCadence` uses bounded observations and refuses to conclude that a static image is a low-FPS game simply because frames match. It also provides an explicit capture-60-to-30 mode, accepting selected source timestamps while doubling nominal duration. This branch is capture-specific, not proof of universal duplicate removal in all input paths. Sources: [ContentCadence](https://github.com/Likely7/Veyra-NRVideo/blob/df41580f7fa0d2b26718f355640470e8cb94b324/include/veyra/engine/ContentCadence.h#L6-L26), [capture branch](https://github.com/Likely7/Veyra-NRVideo/blob/df41580f7fa0d2b26718f355640470e8cb94b324/src/engine/EngineController.cpp#L1031-L1048).

**XFrame proposal:** a 60 fps WebRTC stream with duplicated 30 fps game images needs content-aware pairing, not unconditional every-other-frame removal. Compression noise, static menus, moving overlays and mixed-rate HUDs can defeat naive equality tests. Preserve actual media timestamps separately from arrival timestamps and host presentation deadlines; expose unknown cadence and an explicit user override when automatic confidence is insufficient. Do not automatically reinterpret a still scene as 30 fps.

**Implemented:** the XeSS path feeds plausible consecutive source PTS deltas into its timing guidance; it does not feed delayed Present-to-Present intervals back as source cadence. Source identity and history validity are checked. The latter would include the provider's own waiting and create a feedback loop. [VideoPresenter timing](https://github.com/Likely7/Veyra-NRVideo/blob/df41580f7fa0d2b26718f355640470e8cb94b324/src/engine/VideoPresenter.cpp#L179-L200).

## Temporal history is separate from the display queue

**Implemented:** bounded preview/capture drops can preserve NR/flow/FG history using the last processed frame and its real PTS. Seek, cuts, discontinuity, resize, pause/resume and device loss remain real reset signals. Re-presenting the same source is handled separately from disabling the provider, avoiding an unnecessary reset on the next new source. [History decision](https://github.com/Likely7/Veyra-NRVideo/blob/df41580f7fa0d2b26718f355640470e8cb94b324/src/engine/EngineController.cpp#L1095-L1150), [repeat preservation](https://github.com/Likely7/Veyra-NRVideo/blob/df41580f7fa0d2b26718f355640470e8cb94b324/src/engine/VideoPresenter.cpp#L230-L237).

**XFrame proposal:** distinguish (1) decode/reference failure, (2) a decoded frame skipped for freshness, (3) a presentation miss, (4) a repeated display, and (5) a content/timeline discontinuity. Only appropriate events invalidate temporal algorithms. Keep history identity shared across passes. Veyra's 250 ms is its optical tracking tolerance, NOT a recommended display-buffer age. Do not change XFrame's current 50 ms display-stale bound to 250 ms. Validate large motion/confidence and genuine cuts independently even when timestamps are continuous.

A sticky capture-driver discontinuity flag was filtered only after repeated normal timing evidence, and only for independently decodable raw frames; compressed input flags retained their meaning. That workaround must not become blanket suppression of xCloud decoder/network discontinuities. [Capture flag repair and limits](https://github.com/Likely7/Veyra-NRVideo/blob/df41580f7fa0d2b26718f355640470e8cb94b324/docs/CAPTURE_STICKY_DISCONTINUITY_2026-09-20.md).

## GPU ownership, identities and scheduling

**Implemented:** batches identify epoch, settings revision and source frame; each output also carries real/generated/hold kind, subframe, timestamp and validity. Leases keep textures alive, while consumer fences prevent overwriting textures still in use. Fence values are meaningful only within their originating fence. The live graph-owner scheduler bounds pending jobs to two and represents waiting as deadlines rather than sleeping callbacks. These are separate capacities from decoded frames or drawables. [FrameBatch contracts](https://github.com/Likely7/Veyra-NRVideo/blob/df41580f7fa0d2b26718f355640470e8cb94b324/include/veyra/pipeline/FrameBatch.h#L9-L59), [LiveGpuScheduler](https://github.com/Likely7/Veyra-NRVideo/blob/df41580f7fa0d2b26718f355640470e8cb94b324/include/veyra/engine/LiveGpuScheduler.h#L9-L40).

**XFrame proposal:** retain frame-pair and settings identity through motion estimation, enhancement, generated outputs and actual presentation callbacks. Bound each resource pool independently. Keeping a CVPixelBuffer/Metal texture object alive does not alone prevent its backing slot from being overwritten. A setting/source/size change must retire in-flight resources safely and reset the necessary histories at a coherent frame boundary.

**Implemented:** output caps can reduce the requested generation multiplier before expensive work, rather than generating every requested frame and discarding most afterward. The current optimization has guards: non-provider-owned FG, requested multiplier above 2, valid rate information, and a minimum 2X clamp. It is not a universal all-backend adaptive controller. Absolute-grid output pacing prevents wakeup jitter from shifting every subsequent deadline. [Generation budget](https://github.com/Likely7/Veyra-NRVideo/blob/df41580f7fa0d2b26718f355640470e8cb94b324/src/engine/EngineController.cpp#L1166-L1183), [absolute pacing grid](https://github.com/Likely7/Veyra-NRVideo/blob/df41580f7fa0d2b26718f355640470e8cb94b324/include/veyra/engine/PresentationSettings.h#L25-L55).

**Upstream measurement:** on a native-resolution DLSS 6X test, limiting generation toward display needs reduced GPU/power use substantially; true-upscale workloads saved much less. This is a workload-specific result, not a transferable M1 power promise. The release also separates queue latency, display sync and output rate instead of retaining three empirically indistinguishable presets. [Release scheduling lessons](https://github.com/Likely7/Veyra-NRVideo/blob/df41580f7fa0d2b26718f355640470e8cb94b324/docs/RELEASE_NOTES_1.4.4.md#L15-L26).

**XFrame proposal:** preserve our currently selectable decoded-queue policies; their mechanism differs from these removed Windows modes. For future post-processing, expose independent controls only when they produce a real effect. Apply target output cadence before generating work; keep generated deadlines and source preservation explicit. Avoid two independent components both throttling presentation without a defined owner.

## Latency and limits that matter for a TV

Interpolation uses both A and B. B must arrive before an in-between frame can be computed; after B arrives the output pair still needs pacing. GPU compute time is therefore only part of its added latency. Veyra's live helper anchors a pair to current host time and derives a bounded hold from actual generated/source timestamps rather than waiting on an old absolute source epoch. [Live pair timing](https://github.com/Likely7/Veyra-NRVideo/blob/df41580f7fa0d2b26718f355640470e8cb94b324/include/veyra/engine/LivePresentationTiming.h#L12-L23).

The author reports internal capture latency increasing when FG is enabled, attributing much of the increase to frame-pair waiting. These are capture-path measurements, not full controller-to-photon latency, not M1 measurements and not cloud-network results. [Release measurements](https://github.com/Likely7/Veyra-NRVideo/blob/df41580f7fa0d2b26718f355640470e8cb94b324/docs/RELEASE_NOTES_1.4.4.md#L28-L41).

**Known upstream limits:** true 1080p-to-4K SR + NR + high-multiplier FG still has long gaps; heavy XeSS 4X continuity is incomplete; physical-display and other-device coverage are limited. Independent input denoising is not implemented, and NR temporal stabilization is not equivalent to source denoising. [Release acceptance boundary](https://github.com/Likely7/Veyra-NRVideo/blob/df41580f7fa0d2b26718f355640470e8cb94b324/docs/RELEASE_NOTES_1.4.4.md#L56-L81).

**XFrame proposal:** validate 30-to-60 (2X) first, before higher multipliers. Keep source/decoded/unique/generated/submitted/actually-presented counters distinct. Use drawable presentedTime for the supported software display boundary and external measurement for full input-to-photon. Inspect frame-interval distributions and motion correspondence, not only averages. Do not add stage p95 values to claim a measured end-to-end p95. Do not solve overload by unlimited queues, repeated resets or generating stale frames merely to increase FPS.

## Input and color lessons

Capture mode must be verified from actual negotiated dimensions, cadence and pixel format, rather than a fragile enumeration index. Preserve matrix/range/transfer/HDR metadata; 10-bit pixels alone do not establish HDR. A low-quality chroma reconstruction or final scaling pass can look blurry even when nominal resolution is correct; test the original path before compensating with aggressive sharpening. Capture-specific driver/HDR fixes are not instructions to alter xCloud SDR color handling. [Release input fixes](https://github.com/Likely7/Veyra-NRVideo/blob/df41580f7fa0d2b26718f355640470e8cb94b324/docs/RELEASE_NOTES_1.4.4.md#L28-L41), [full-chain clarity investigation](https://github.com/Likely7/Veyra-NRVideo/blob/df41580f7fa0d2b26718f355640470e8cb94b324/docs/FULL_CHAIN_REGRESSION_REPAIR_PLAN_2026-09-22.md).

XFrame's own HUD should be composited after image processing. The game's HUD is already embedded in video; protection masks or conservative bypass are imperfect heuristics, not a clean HUD-less input. Image-derived optical flow and estimated/constant depth do not turn video into engine-provided geometry.

## XFrame implementation gates derived from this research

1. **Baseline and spatial upscale:** confirm SDR conversion/chroma/actual 4K drawable, then compare original scaling, MetalFX Spatial and any independently implemented FSR 1 candidate. Separate final size from NR/flow processing size.
2. **Motion/cadence prototype:** known translations in both axes, direction and unit checks, mixed-rate HUD, duplicates, scene cuts, occlusion and compression noise; report uncertainty. Preserve original PTS, arrival time and last-processed identity.
3. **2X interpolation:** identity-correct A/B pairs, correct midpoint position, generation validity, stop/seek/reconnect/resize safety, bounded queue/resource reuse, repeat-vs-reset regression. Measure full pair waiting and A/V consequences.
4. **Neural enhancement:** evaluate input-only motion/history reconstruction and lower-resolution NR plus detail-preserving composition. Verify Metal feasibility and rights independently; use original-frame comparison and quantify temporal flicker/art-direction changes.
5. **Combined pipeline:** compare processing order/resolution at equal input, output, display refresh and scene. Measure per-stage GPU cost and whole-frame actual presentation separately; compute only useful generated frames. Keep settings reversible and unsupported combinations explicit.
6. **Acceptance matrix:** bypass/SR/NR/FG and combinations; source 30/60 plus duplicated 30-in-60; stationary and fast pans, thin lines/text, cuts, lost/late frames; M1/4K60 first, 120 Hz when hardware available. Short alternating A/B runs first, then sustained runs; tests do not substitute for visual or input-latency acceptance.

The upstream Windows/NVIDIA backend, NR models and GPU measurements cannot be transplanted into Apple Silicon claims. The reusable deliverable is the set of data, timing, history, resource and measurement contracts above.
