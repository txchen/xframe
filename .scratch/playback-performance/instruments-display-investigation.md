# Instruments display-path investigation, 2026-11-15

Xcode 27.2 (27B52) is initialized. Commands use process-local DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer; global xcode-select remains unchanged. No simulators installed by this investigation.

## Question and method

Locate the post-GPU delay, without claiming a performance improvement from instrumented runs. M1 Mac mini, external 3840x2160 60 Hz monitor, signed release diagnostic build `.build/pacing-trace/XFrame.app`, PID 27251 verified before attach. Same live A Game About Digging A Hole animated menu, Standard/Balanced, native 1920x1080 stream. No game input or saves changed. Load 2.34 on eight logical CPUs before recording.

Four 15-second Metal System Trace recordings are under `.build/instruments-display/`: `original-window.trace`, `original-fullscreen.trace`, `metalfx-fullscreen.trace`, `metalfx-nohud.trace`. First recording overlaps startup; the other three start after steady playback. XML exports and joined per-frame records are next to these ignored local artifacts. Traces contain process/environment metadata; they are not release assets.

Join a CAMetalLayer present request to application GPU work by command-buffer ID, then to the first later WindowServer read of its IOSurface. Join that compositor command to its output surface and first subsequent display swap. Reject an application-surface reuse before the compositor read, an overwritten compositor output before swap, ambiguous multiple outputs, and boundary-incomplete chains. The readable scripts and numeric summaries are in `diagnostics/2026-11-15/instruments/`. IOSurface access time is the recorded driver access event, not a claim about the exact GPU texture-fetch instruction. Display swap is system-reported presentation, not a physical input-to-photon measurement.

## Result: the large wait precedes compositor use

All matched-frame medians below are milliseconds under the profiler. They describe where time goes, not an uninstrumented A/B performance ranking. Independent medians need not sum exactly.

| Trace | Joined frames | App GPU end to WS surface read | WS access to GPU end | WS GPU end to swap | Total post-GPU |
|---|---:|---:|---:|---:|---:|
| Original window | 701 | 26.316 | 0.844 | 12.587 | 39.780 |
| Original fullscreen | 923 | 26.104 | 2.050 | 10.892 | 39.044 |
| MetalFX fullscreen | 918 | 26.802 | 1.891 | 11.175 | 39.960 |
| MetalFX fullscreen, HUD hidden | 913 | 20.561 | 1.754 | 12.781 | 34.002 |

A concrete Original fullscreen chain: application GPU ends at 8.077095958 s; WS reads that surface at 8.104090791 s; WS GPU ends at 8.106332583 s; output swaps at 8.116818625 s. This frame spends 26.995 ms before compositor access, 2.242 ms in the compositor submission/work interval, and 10.486 ms awaiting the output swap. Thus the wait exceeds one 16.67 ms refresh interval because it includes multiple pipeline stages before the final refresh wait.

All four recordings report no direct-to-display presentation. Windowed failure reason includes `layer geometry isn't defined in screen space`; fullscreen reports `display rejected`, with no actionable suggestion. Hiding HUD still reports `display rejected` (909 rows); therefore HUD removal does not establish a direct-display fix. Hidden-HUD post-GPU p95 is 57.411 ms, so its lower median cannot be presented as a stable win. One recording per condition, not five interleaved repetitions.

## Measurement limits and remaining cause

Before MetalFX tracing, uninstrumented HUD showed GPU p95 6.6 ms, display-wait p95 33.9 ms, arrival-to-display p95 55.0 ms, output60. Other uninstrumented Original observations ranged from ~23 to ~40 ms display wait. Profiling changes load and potentially presentation phase. The trace values must not replace the earlier uninstrumented baselines or establish MetalFX's exact incremental latency.

The trace establishes the location of the wait, but does not distinguish client-to-server handoff delay, compositor frame selection/deadline policy, and display scheduling. The compositor event tables are empty on this capture; attribution comes from GPU/IOSurface/swap chains. It does not prove that WindowServer alone is faulty or that the delay is unavoidable. It also does not explain the M5's 53.6 ms p95 by itself.

Next causal experiment should instrument intended display/deadline and actual submission time and control scheduling phase, then verify real output cadence and latency without Instruments. Do not blindly serialize drawable presentation: the earlier one-slot gate halved output to30 without removing the baseline wait. Likewise, shortening the decoded FIFO does not directly remove a delay that occurs after GPU completion. Direct-display rejection deserves a separate minimal layer/window test before changing application architecture.

## Session end and product changes

Session ended after297.658 seconds with `The WebRTC connection failed or was closed`; captured report outcome is failed. Across the session:17053 decoded,16977 presented,76 skipped,0 decode errors,0 packets lost,0 NACK. The four recordings completed before the disconnect. This is a bounded diagnostic session, not sustained-playback acceptance. Detailed HUD and Original scaling were restored; app is at its library.

No production scheduling code was changed in this pass and no latency fix/release is claimed. Prior schema10 diagnostics remain in the worktree. Actual report saved as `diagnostics/2026-11-15/instruments/session.json` and `~/Documents/xframe-instruments-display-2026-11-15.json`.

## Follow-up: scheduled deadline versus actual refresh

Exported Core Animation `CAMetalLayer.Stalls` / `DrawableLifetime` signposts from the same recordings. They contain raw Mach ticks for `timePresentCalled`, `targetTimestamp`, and `targetPresentationTimestamp`. Conversion uses the trace's own `time-info` epoch and125/3 timebase, not an assumed nanosecond clock. Join signposts by IOSurface and present-call timestamp (within2 ms); additionally compare lifetime-end with the independently joined output swap. Fullscreen Original lifetime-end and output-swap differ by median0.0002 ms, max0.0074 ms, validating the association.

Original fullscreen has902 complete matched deadlines:738 frames display one refresh late (16.6669 ms median),164 hit the internal target. All902 have GPU completion before the recorded targetTimestamp (minimum0.0092 ms margin). In the late group GPU margin median5.870 ms; in the on-target group5.767 ms. Thus a GPU deadline miss does not explain the extra refresh in this trace. Internal signpost fields are diagnostic hints, not an MTKView public scheduling guarantee.

| Original fullscreen group | Frames | GPU end to WS access median | Post-GPU display median |
|---|---:|---:|---:|
| One refresh after internal target |738|26.319 ms|39.204 ms|
| At internal target |164|9.828 ms|22.434 ms|

The change occurs around trace second13 without an app rendering-mode change. GPU margin remains about5.8 ms; compositor work remains about2 ms. The ~27 ms access delay therefore consists of the shorter ~10 ms path plus an extra refresh interval in this observed state. It is not a fixed27 ms shader workload. MetalFX fullscreen has904 matched deadlines, all one refresh late despite GPU margin median6.619 ms. Hidden-HUD MetalFX has901 matches:899 one-refresh late,2 on target; some GPU margins are negative there, so do not generalize the Original no-miss claim to every mode.

### Explicit deadline live experiment, without Instruments

Built isolated signed `.build/deadline-probe/XFrame.app`, same game/menu, Standard/Balanced, Original scaling, fullscreen4K after startup. Temporary menu selects default MTKView, CAMetalDisplayLink latency1, latency2, then default again. Display-link range60/60/60; uses supplied drawable and fresh render-pass descriptor, pauses MTKView's automatic loop. Logs callback, submit, public targetTimestamp, public targetPresentationTimestamp, GPU start/end, actual presentedTime. Memory-only bounded collection, exported on mode transitions/end. No profiler runs in these samples.

Excluding first5 seconds of each segment:

| Segment | Matched frames | Display-wait median / p95 | Actual minus public target median / p95 |
|---|---:|---:|---:|
| Initial default (includes window/fullscreen transition; not clean baseline)|2950|22.907 /47.472 ms|n/a|
| CAMetalDisplayLink latency1|1952|48.497 /48.917 ms|0.068 /0.126 ms|
| CAMetalDisplayLink latency2|3545|48.446 /48.906 ms|0.065 /0.126 ms|
| Restored default|4131|22.482 /23.389 ms|n/a|

Both explicit settings receive a callback-to-deadline interval of~16.53 ms and deadline-to-target interval33.33 ms: the system assigns a target~49.87 ms after callback. GPU finishes~15.05–15.09 ms before the public deadline, and there are no>8 ms actual-target misses in the measured segments. The requested latency1 is therefore not a guarantee of a one-refresh visible response on this composed display path. This explains why the earlier display-link experiment was slower; it did not merely miss its supplied deadline. Direct replacement is rejected. One sequence is sufficient to reject this candidate here, not to claim a tuned winning policy.

Apple documents targetTimestamp as the present-call deadline and notes final preferredFrameLatency may be larger when the system needs additional time:
- https://developer.apple.com/documentation/quartzcore/cametaldisplaylink/update/targettimestamp
- https://developer.apple.com/documentation/quartzcore/cametaldisplaylink/preferredframelatency
- https://developer.apple.com/documentation/quartzcore/cametaldisplaylinkdelegate/metaldisplaylink(_:needsupdate:)

Session ended explicitly and returned to library; outcome stopped,13849 decoded,13773 presented,76 skipped (includes startup/mode transitions),0 decode errors/lost packets/NACK. Restored default HUD60 output, display-wait p9523.4 ms before ending. Session and probe events are in `diagnostics/2026-11-15/deadline-probe/`; source/build snapshots are under ignored `.build/deadline-probe`. Experiment source restored byte-for-byte to the pre-experiment files, temporary source removed, git diff --check passed. No production policy change or release.

The extra-refresh location is established, but the internal cause of compositor retention is not: further isolation should compare a minimal opaque fullscreen Metal layer with XFrame's actual window/layer tree and preserve all other display/capture conditions. Simply changing API or reducing CPU queue depth is not supported by these results. Do not claim macOS must always add this delay, or that this is the exact same cause on M5.

## Minimal fullscreen window comparison

Created two independent optimized Swift apps outside production Sources, under `.build/minimal-metal`. No network, decoder, XFrame frame inbox, MetalFX, or game code. Each frame clears a BGRA8Unorm drawable with a slowly changing opaque color, presents and commits immediately, and records actual GPU/presentation timestamps in bounded memory. MTKView probe uses the same preferred120 callback setting as XFrame (actual display60 Hz), GPU permit count3, and supports root Metal view, nested black parent, and static overlay variants. Bare probe uses one NSView with an opaque CAMetalLayer, colorspace=nil, and a main-runloop60 Hz timer, so it removes both MTKView and the specified sRGB color space. Timer scheduling differs intentionally; do not rank total latency between these apps as equivalent workloads.

Preflight M1 LG Ultra HD3840x2160 at60 Hz, UI1920x1080, eight GPU cores, load1.53. Initial idle system_profiler reported Display Asleep. Opening/clicking the probe woke the display; checks before the captures no longer reported asleep and power assertions showed UserIsActive. No caffeinate or power-setting change was made. User explicitly confirmed no ongoing screen sharing/remote desktop/recording connection. No user app or capture service was stopped. Tool-driven screenshots are discrete observations; there was no screenshot polling during the15-second trace intervals. Instruments itself remains a source of perturbation.

Four recorded15-second Metal System Traces:

| Variant | Direct-to-display frames | Display rejection rows | DrawableLifetime samples | Actual after internal target |
|---|---:|---:|---:|---:|
| Root MTKView |0|918|938|all938 about16.667 ms late|
| MTKView inside black parent |0|910|938|all938 about16.667 ms late|
| Nested plus static overlay |0|912|not exported|not claimed|
| Bare CAMetalLayer, no specified colorspace |0|917|939|all939 about16.667 ms late|

All rejection reasons are `display rejected`; no actionable condition is exposed in the exported suggestion. These counts refer to trace events, not a five-run performance comparison. They establish reproducibility of the extra-refresh symptom in a separate minimal app. Root/fullscreen MTKView GPU clear median~0.078 ms, while its long-run post-GPU median~47.48 ms; the different submit phase makes this unsuitable as a direct XFrame latency comparison. The point is that a negligible GPU workload also waits and misses the internal target by one refresh. MTK probe logged19987 submissions/presentation callbacks,0 GPU errors,35 invalid/zero presentation timestamps across startup, resize, transitions and captures. Bare trace run logged9619,0 GPU errors,34 invalid/zero presentations. Invalid timestamps are excluded, not counted as fast success.

A follow-up self-instrumented geometry check of the same bare window setup verifies:
- NSApp active, window visible, onActiveSpace, native fullScreen all true.
- Window and screen frames both{{0,0},{1920,1080}} points; view/layer bounds cover the same extent.
- Window and layer opaque; drawable3840x2160, backingScale2, layer colorspace=nil.
Thus this is not merely a small window captured to look full-screen. Actual rendering was visually inspected. Both apps were explicitly quit after saving data.

This rules out XFrame's overlay, parent-container hierarchy, MTKView wrapper, selected sRGB colorspace, video conversion and network as necessary causes of the observed one-refresh delay. It does not prove the driver rejects every color space or every window configuration; nor does it identify the private condition behind `display rejected`. Apple's guidance says an opaque RGB fullscreen layer on Apple silicon normally qualifies, while explicitly allowing hardware/system edge cases. This probe meets the documented visible conditions, but public tracing reports only the final rejection, not the failed internal predicate.

Source: https://developer.apple.com/documentation/metal/managing-your-game-window-for-metal-in-macos

The supported conclusion is an independently reproducible composed-presentation behavior on this M1/macOS27.2.1/LG output configuration, not a proven XFrame hierarchy bug and not yet an identified OS defect. The remaining isolating variables are the display output/configuration and OS/hardware behavior, best tested with this same probe on a second output/device while preserving measurement conditions. Do not rewrite XFrame's UI or label the issue fixed on this evidence.

Reproducible source, numeric event data, full-screen geometry and analyzed results live in `diagnostics/2026-11-15/minimal-metal/`. Raw `.trace` and exported XML stay under ignored `.build/minimal-metal/`; the analysis script reads those trace exports through the earlier XML reader. No XFrame production source changed in this pass; git diff --check passed.
