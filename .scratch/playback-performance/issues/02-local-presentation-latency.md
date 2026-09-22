# Reduce local presentation latency without restoring sustained frame loss

Status: ready-for-agent
Type: task
Resolution: bounded freshness and accurate presentation accounting implemented; foreground pacing gates pass; lower display-latency target and final controller gameplay remain open

## Request

2026-09-22: User questioned roughly 40 ms of receiver/client contribution to the HUD latency estimate and requested comparison with Moonlight. The recent controller/UI fix reaches approximately 59.6–59.7 presented fps against 60 incoming; preserve that gain.

## Boundaries and findings

XFrame `VideoFrame.arrivedAt` starts at delivery of a decoded frame to LiveVideo. `frameWait` ends before command presentation/commit; `presentation` ends at Metal drawable.presentedTime. Presentation includes frame waiting and GPU/display scheduling; it must not be summed again with frameWait/GPU. Apple describes presentedTime as the host time when the drawable was displayed; this still is not an external measurement of panel response or input-to-photon latency.

The HUD estimate adds interval receiver jitter-buffer delay, decode mean, post-decode presentation mean and network RTT. Recent jitter-buffer delay was approximately 1 ms; decode p95 approximately 3 ms, GPU p95 approximately 0.5 ms, frame-wait p95 approximately 16.5 ms and presentation p95 approximately 40.2 ms. These p95 values are not components that can be added or subtracted to reconstruct the mean estimate. Most local time is scheduling/presentation, not hardware decode throughput.

Moonlight's cross-backend render-call metric does not uniformly include actual presentation completion. See ../moonlight-latency-research.md for pinned stable/development source evidence. Do not claim a same-M1 benchmark, a universal Moonlight millisecond target, or that a small Moonlight render statistic proves equivalently short physical-display latency.

## Experiment plan

1. Measure non-overlapping stages from the same frame: decoded arrival → render submission → GPU completion → reported display. Keep timing collection bounded and summaries at 1 Hz; no per-frame observable UI updates. Account for failed/dropped drawable presentation explicitly. Preserve existing mean and tail statistics; do not subtract unrelated percentile distributions.
2. Compare existing FIFO with latest-ready-frame selection after the controller/UI invalidation fix. The earlier one-slot result was confounded by UI stalls; do not assume its prior high loss proves one-slot inherently unsuitable. Bound age/queue depth and record intentional replacements, output ratio and recent latency together.
3. Separately compare MTKView scheduling with a display-deadline-aware CAMetalDisplayLink path requesting one frame of latency on supported macOS. The requested latency is not an Apple guarantee, especially windowed. Do not simply turn VSync off and accept tearing as success.
4. Compare matched windowed/fullscreen runs with controller active and equivalent HUD settings, codec/stream resolution, display refresh and network conditions. Do not change FIFO depth and render scheduling in the same attribution experiment.
5. Accept only a measured reduction in local presentation mean/tail while retaining near-input output rate, bounded memory, reasonable visual pacing, working resize/focus/controller shortcuts and no telemetry-induced regression. Keep cloud RTT separate; no claim of reducing it by local rendering changes.

## Scope

This research turn does not restart the user's current game or change the live renderer. A timing-definition correction must not be presented as a latency improvement. True input-to-photon comparison requires an external end-to-end measurement and a comparable host/stream.

## Implementation authorization and diagnostic gate

2026-09-22: User authorized continued optimization of core stream stability/latency using Moonlight/XStreaming lessons. The research-only scope above applied to the previous turn; native implementation, builds and controlled Palworld tests now continue under this request.

Before renderer changes, `check-presentation-latency.py diagnostics/latency-mtk-baseline.json` fails at mean 30.82 ms / p95 43.35 ms. This experiment targets <=25 ms mean and <=40 ms p95 decoded-arrival-to-reported-display, with >=98% displayed/decoded and no decode errors. These are chosen experiment gates, not universal guarantees. First instrumented MTKView run confirms approximately 12.4 ms queue + 0.4 ms GPU queue + 0.5 ms GPU + 23.0 ms display waiting; windowed 60 Hz, controller active.

Added a real presentation-callback seam regression: a zero drawable timestamp incorrectly raised OUT from 0 to 1 (red). The corrected callback now records it as not-presented, joins GPU/presentation callbacks in either order, and preserves terminal reports. 93 tests pass. Four timing components are recorded from same-frame timestamps, bounded to 256 samples. Report schema 5; HUD summaries remain 1 Hz.

- Instrumented baseline: `latency-mtk-instrumented.json` retains 82.5 s of session data and 4,078 decoded frames; recent mean presentation 46.09 ms, p95 49.37 ms, displayed ratio 99.36%. Earlier foreground HUD windows were approximately 36–42 ms mean and 38–44 ms p95. Queue and macOS display phase vary; retain the full range, not just the best snapshot. Same 46.135 s foreground counter interval had 12 skips (0.26/s).
- Candidate changes only the cloud display driver to CAMetalDisplayLink (one-frame latency request), with the same two-frame FIFO, VSync/default drawable pool, 120 Hz preferred maximum, GPU in-flight limit, codec and input frequency. Local file playback keeps its existing MTKView scheduling.
- First candidate cloud attempt failed during WebRTC setup before any video frame; excluded from renderer performance comparison. Retrying in the same application also exercises display-link teardown/recreation.

- Rejected the CAMetalDisplayLink integration: actual local display wait increased to about 49 ms and total presentation mean 57–73 ms. `latency-displaylink-rejected.json` fails at 70.39 ms mean / 73.56 ms p95 despite 98.91% display coverage. A fullscreen/hidden observation did not remove the regression; this is not evidence that every CAMetalDisplayLink implementation is slow. The experimental source is isolated under ignored `.build/`, not the app implementation.
- Next isolated candidate keeps MTKView/Metal/VSync, but draws on coalesced decoded-frame arrival rather than a periodic redraw timer. Pending bursts resume after GPU completion without busy-waiting. A separate 1 Hz main-run-loop timer refreshes telemetry during frame stalls without drawing. Queued notifications are cancelled on source replacement; cloud view drawing goes through MTKView.draw() so drawable acquisition/release ownership remains correct.

- Rejected frame-arrival-driven rendering too: steady windowed presentation mean 76.7–89.3 ms, with approximately 64 ms after GPU completion and blocking drawable acquisition. OUT remained near 59.7 but latency worsened, illustrating why FPS alone is insufficient. Reverted the source notification/scheduler/timer code to the instrumented MTKView baseline. The 94–95-test transient scheduler work is not part of the final test count.

- Same-session two/three-drawable observations are in `diagnostics/latency-buffer-ab.json`. Total latency varied with queue phase; fullscreen GPU-to-display time remained approximately 23 ms for both pool sizes. No reliable isolated display-stage improvement was established, so the temporary diagnostic menu and pool-size change were removed. Keep the default three drawables. One idle test session later ended with the existing WebRTC-closed error; cause was not isolated, and no automatic input or reconnect workaround was introduced.
- Implemented bounded freshness catch-up: keep a two-frame burst queue, but if a fresher decoded frame is ready, discard a head older than one 60 Hz interval rather than remaining a full frame behind. A lone frame retains the existing 50 ms maximum-age bound. The real LiveVideo callback/consumption regression failed with old behavior (returned frame 1, retained frame 2); now selects frame 2 and counts exactly one skip. Existing two-frames-between-ticks coverage still passes. 94 tests pass.

- Rejected the initial 16.7 ms catch-up cutoff: steady 64.286 s window had 97 skips (1.51/s), failing the existing skip-rate gate despite some shorter-latency snapshots. Relaxed catch-up to 25 ms (1.5 frames at 60 Hz), retaining ordinary one-frame arrival jitter; added coverage for preserving both frames after a 20 ms delay and retiring the older frame at 30 ms. 95 tests pass. The earlier 16.7 ms wording describes the rejected experiment, not the delivered policy.

- Final 25 ms policy: Detailed 0.256 skips/s, Hidden 0.268/s, Compact 0.238/s; all pass the existing pacing gate. Foreground recent presentation mean 31.4–36.9 ms, p95 34.3–39.3 ms. Exported final/end-focus window is 37.17/51.27 ms and fails the separate 25/40 ms latency target. 95 tests and signed release build pass. Physical controller was disconnected for the final run; acceptance remains open. See ../latency-optimization-validation.md and diagnostics/freshness-balanced-hud.json.

- Controller-connected follow-up on the final app: input active throughout, Detailed 0.418 / Hidden 0.439 / Compact 0.224 skips/s, all pacing checks pass; HUD OUT 59.6 fps. Local mean 29.5–39.1 ms remains above the 25 ms target. Physical connection/input-overhead check completed; manual gameplay feel and extended sessions remain open. See final follow-up in ../latency-optimization-validation.md.
