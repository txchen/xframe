# Display wait causal probes

Same M1/LG 4K 60 Hz, Original rendering, 1080p input, fullscreen 3840x2160. Isolated signed release experiment builds, live A Game About Digging A Hole menu. No VSync disabling, no source-queue tuning. GPU time measured from command timestamps, display from drawable presentedTime. Load preflight 1.53 on eight cores, no heavy worker. Build finished before observations; builds/profilers did not overlap reported steady windows.

## Hypothesis 1: Core Animation transaction mismatch

Baseline command.present -> commit, asynchronous CAMetalLayer, compared in the same session to presentsWithTransaction=true and Apple-documented commit -> waitUntilScheduled -> drawable.present.

Baseline display wait mean/p95 22.7/23.7 ms, total mean/p95 36.9/39.1, output60. Transaction after settling: display22.6/23.6, total30.4/44.8, output58; another observation output59. Skips rose 11 -> 34 -> 62. Returning to baseline restored60. The altered frame-wait phase is not evidence of a total improvement. Rejected, no persistent product change.

Reference: https://developer.apple.com/documentation/quartzcore/cametallayer/presentswithtransaction.md

## Hypothesis 2: two submitted frames cause the extra refresh

A separate build used a nonblocking one-slot semaphore before consuming/encoding a frame, released only in its drawable's presented callback. Thus, after draining existing submissions, only one drawable could be awaiting presentation. This is a diagnostic throttle, not an acceptable production pacing policy.

Baseline fullscreen startup briefly had display wait39.4/40.4 ms (mean/p95), then returned to ~23 ms around the toggle; do not attribute that phase change to the gate. With the gate settled, output was30 FPS while input60. Display wait stayed22.4/23.2 ms, total37.7/48.4, GPU p95 0.7. Continued observation remained30 FPS, display22.4/23.2, total39.4/48.6. On disabling the gate, output returned60, display22.6/23.5, total31.5/34.2. The high cumulative skipped count in this experiment is intentionally induced by the30 FPS throttle, not a newly discovered production regression.

This falsifies the simple explanation that removing our second pending drawable removes the ~23 ms latency. Two simultaneous completed drawables can be a consequence of pipeline latency rather than its cause. Do not ship one-frame serialization or lower the decoded inbox bound as a fix for this wait.

## What is established and what is not

The wait remains between GPU completion and reported presentation even without a second pending drawable, and changing transaction synchronization does not remove it. We have not identified the exact internal WindowServer/compositor/display deadline responsible. A fixed 16.7 ms additional queue is still an unproven interpretation; no physical scanout measurement was taken. The previously stated 'we queued an extra frame' was a hypothesis, not a proven cause.

This machine has Command Line Tools only: xcrun --find xctrace fails and Spotlight finds no com.apple.dt.Xcode. Metal System Trace is unavailable here, so no system-compositor trace was collected. Further attribution needs that timeline or a display-clock experiment exposing target and actual deadlines; it cannot be inferred from summing independent p95s.

Both experimental source changes and menu entries were removed by restoring the pre-experiment files, preserving earlier schema10 diagnostics. Rejected experiment sources/builds remain under ignored `.build/presentation-experiment` and `.build/presentation-gate`. No latency improvement or new release is claimed.

## Exported trace confirms the causal probe

Saved `diagnostics/2026-11-15/presentation-gate.json`. Match frame IDs with submitted, gpuCompleted and presented endpoints. Relative seconds80–110 contain900 matched frames with maximum submitted-but-not-presented occupancy1, mean post-GPU wait22.535 ms, median display interval33.333 ms. Seconds115–150 after restoring baseline contain2097 matched frames, maximum occupancy2, mean wait22.689 ms, median interval16.667 ms. Boundary-incomplete frames are excluded. Five-second subwindows in the gate interval had mean waits22.40–22.69 ms; restored steady subwindows22.57–22.78 ms. These actual matched events confirm the gate executed and that serialization did not remove the wait. Transition/ending windows are not included in that comparison.
