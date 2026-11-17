# Moonlight presentation review

Reviewed Andy Grundman branch `andyg.macos-metal-frame-pacing`, pinned commit `57088f1a22bd7a3f1ced1af5102444edcc422241`. Local reference: `.build/references/moonlight-metal-review`. This is a fork, not a claim about the current official release. Existing official reference is `032529d782242e3833e0b3b147dbbf96e878e3ca`.

## Findings from actual call paths

- `framepacing/framepacer.cpp:261-309`: independent render thread waits for decoded input; default Immediate mode waits for frame availability rather than one MTKView callback per refresh. Display-locked mode budgets input waiting against a refresh deadline, observed CPU render cost, and 1 ms safety. It does not always wait until the last moment: input arrival wakes the condition variable early.
- `pacer/displaylink_source.mm`: NSWindow CADisplayLink supplies timestamp/targetTimestamp to pacer. It is not CAMetalDisplayLink and does not supply drawables.
- `vt_metal.mm:1016-1057`: fixed-refresh target is one interval after the current deadline. Code explicitly expects an additional refresh in composited triple-buffering circumstances versus Direct. This is a developer expectation, not proof of XFrame's cause or a universal macOS lower bound.
- `vt_metal.mm:1062-1143`: scheduled callback invokes drawable presentAtTime / presentAfterMinimumDuration / present by mode. After commit it obtains the next drawable, allowing drawable availability to throttle the rendering thread. It does not wait for presented callback before starting every frame.
- `vt_metal.mm:163,1307`: drawable count is clamped to 2–3. A one-presented-frame gate is not its architecture.
- `framequeue.cpp`: capacity 5, default high watermark 3; overflow alternates newest-drop and oldest-replacement, with I-frame handling. Immediate dequeue catches up conservatively, not an unconditional take-newest sweep. These exact thresholds are not established as suitable for XFrame.
- `vt_metal.mm:836-880`: actual presentedTime is used, zero timestamps excluded; present delay begins before scheduled callback registration/commit. XFrame Display wait starts at GPU end, so these numbers cannot be directly compared. Compare identical frame stage timestamps and actual present intervals.

## Cautions

The source comment suggesting commandBuffer.present waits until GPU completion conflicts with Apple's documented scheduled-present convenience behavior; do not treat switching to addScheduledHandler alone as a proven latency optimization. Explicit target scheduling can itself add latency. The fork is evidence of design options, not evidence that its latency is lower on this M1.

Apple references:
- https://developer.apple.com/documentation/metal/managing-your-game-window-for-metal-in-macos
- https://developer.apple.com/documentation/quartzcore/cametaldisplaylink/preferredframelatency
- https://developer.apple.com/documentation/xcode/understanding-metal-performance-hud-metrics
- https://developer.apple.com/documentation/metal/mtldrawable/present(at:)

Apple documents Direct eligibility (Apple silicon, fullscreen opaque RGB layer, hardware/system edge cases), not a universal 23–27 ms GPU-to-display floor. Moonlight issue #1696 also warns that renderer HUD timing definitions differ.

## Local experiment already completed

Five alternating FIFO/latest-ready pairs, same M1 cloud title menu, Original rendering, fullscreen 4K60. Each 20 s block analyzed after removing first 5 s and last 1 s. FIFO output 59.84–60.03 fps; latest-ready 57.48–58.45 fps. Median arrival-to-display improves only about 2 ms, but each latest-ready block has 22–33 intervals above 25 ms versus 0–1 for FIFO. GPU-to-display remains about 22.5 ms. Reject unconditional latest-ready.

Raw events and analysis: `diagnostics/2026-11-15/selection-probe/`. Temporary source changes restored to pre-experiment diagnostics baseline. CADisplayLink phase sweep app was built but NOT measured; paused on user request to investigate public evidence first. Source snapshot retained in `.build/phase-probe/`.

## Next discriminating validation

Use a local synthetic frame source on the same M1 to compare MTKView automatic drawing with Moonlight-like independent input-driven rendering and drawable backpressure. Keep resolution, GPU workload, present API and frame selection identical initially. Record GPU end, actual presentedTime, input age, actual refresh intervals, and Direct/Composited mode. Only then vary explicit present target. This separates render-loop phase from presentation API and network jitter. Do not adopt a fixed offset or fork queue thresholds without repeated live validation, including MetalFX and smoothness.
