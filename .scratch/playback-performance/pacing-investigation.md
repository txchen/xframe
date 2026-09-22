# Sustained skipped frames: investigation and fix

Date: 2026-09-22. Working-tree change; no commit created.

## Finding

The measured loss happens in XFrame's single-frame live inbox: a second decoded callback overwrites an unconsumed frame before the next display tick. Small differences in arrival/render timing are enough to lose frames despite similar average rates. The measured sessions do not support hardware decoder or GPU saturation as the cause.

Environment: Apple M1 Mac mini, LG Ultra HD display, 3840x2160 backing pixels / 1920x1080 logical at 60 Hz; playback surface 3840x2036 pixels; Palworld main menu, HQ/zh-CN, native 1920x1080 H.264 hardware decode. Baseline/fixed comparison used foreground playback and controller input disabled; it does not replace extended physical gameplay testing. User subsequently authorized restarts for diagnosis. The earlier interrupted sample after the user ended/changed games was discarded.

## Feedback loop and evidence

`python3 .scratch/playback-performance/diagnostics/check-skip-rate.py <sample-file>` checks timestamped visible HUD observations. The investigation threshold of at most one skipped frame/s was selected before the fix. This is a diagnostic gate, not a promise of zero loss under all conditions.

| Sample | Duration | Input | Output | Skips | Skip rate |
|---|---:|---:|---:|---:|---:|
| Earlier reported symptom | ~38 s | lifetime ~60 | lifetime ~52–53 | 369 | ~9.71/s |
| Instrumented original inbox | 44.073 s | 59.79 fps | 58.31 fps | 65 | 1.47/s |
| Two-frame candidate | 68.341 s | 60.12 fps | 59.80 fps | 21 | 0.31/s |

Files: `diagnostics/baseline-hud.json` (approximate adjacent-tool timestamps), `diagnostics/instrumented-before.json`, `diagnostics/instrumented-after.json`. The original two files fail the gate; the fixed sample passes. HUD refresh granularity adds some uncertainty to wall-clock delta rates; the exact counter increments remain visible evidence. Original symptom severity varies between sessions, so compare the instrumented windows rather than claiming all runs had identical loss.

The instrumented original session's exported report (`diagnostics/pacing-before.json`) counted 12,890 decoded frames, 12,542 presentations and 347 skips, all inbox replacements. Renderer replacements, busy GPU permits and unavailable drawables were all zero. Queue occupancy remained bounded at one. Decode errors and reported video packet loss were zero. At report end, recent (256-sample) p95 values were:

- Hardware decode callback: 2.68 ms.
- GPU execution: 0.45 ms.
- Drawable acquisition: 0.11 ms.
- Arrival interval: 17.57 ms; draw interval: 17.36 ms (both means ~16.67 ms).
- Frame waiting: 14.05 ms; arrival-to-presentation: 37.77 ms.

The candidate's later HUD sample reported recent p95 waiting 17.8 ms and presentation 41.8 ms, while output tracked input at about 59.8/60.1. This suggests a few milliseconds of additional local waiting in this observation, not zero-cost buffering. These are overlapping local measurements, not controller-to-photon latency. A few startup and runtime skips remain; do not claim zero loss.

## Hypotheses tested

1. Arrival/display timing mismatch and single-slot overwrite: supported by categorized counters and the regression below.
2. Main-thread/drawable stalls or GPU backpressure as the main cause: not supported in the measured baseline; no busy/drawable/renderer-loss counters and low acquisition/GPU timings. Occasional unmeasured stalls remain possible.
3. Decode delivery jitter: arrival intervals vary around the render cadence, which is enough to expose the one-slot issue. Average FPS alone cannot characterize this; no evidence here of sustained decoder overload.

The existing 120 fps MTKView preference was not changed in the A/B. Apple documents this as a preference constrained by the display; it is not proof of 120 actual render ticks. [Apple preferredFramesPerSecond](https://developer.apple.com/documentation/metalkit/mtkview/preferredframespersecond).

## Fix and regression

`livePlaybackPreservesTwoFramesDeliveredBetweenDisplayTicks` drives the actual `LiveVideo.renderFrame` → `nextFrame` boundary. Before the fix, the first frame vanished, the second read returned nil, and skipped incremented (`.build/pacing-regression-red.log`).

LiveVideo now uses a FIFO capped at two decoded surfaces. Overflow drops the oldest, and consumption discards frames older than 50 ms. There is no deliberate startup prebuffer or unbounded queue. Stop/failure clear both slots. Existing hardware integration tests now check the new bound; a new regression verifies overflow, stale discard, recovery and stop.

The renderer's cadence and three-command GPU bound remain unchanged. A separate `isLive` stats flag replaces HUD's old assumption that a queue capacity of one identifies cloud playback.

Permanent bounded diagnostics distinguish inbox/renderer losses, busy ticks and drawable misses, and summarize arrival/draw/drawable-wait timings. Detailed HUD says `skipped total`. Report schema is 4; no account/title/network addresses, raw SDP, raw timestamps or pixels are added to the export. No temporary debug logs remain. The retained check script and numeric captures live in the explicitly named diagnostics directory.

## Validation and remaining work

- `bash scripts/test.sh`: 88 passed (`.build/pacing-fix-tests.log`).
- `bash scripts/build-app.sh`: release build, development signing and strict verification passed (`.build/pacing-fix-build.log`).
- Live foreground Palworld comparison passed the chosen skip-rate gate and brought output within about 0.32 fps of input over the measured window.
- Controller input was re-enabled after A/B; the app reported no connected controller. User was invited to test movement/view smoothness and perceived input delay. The user subsequently confirmed a substantial improvement and noticeably less mild stutter/frame-loss sensation. This validates the smoothness improvement during actual play; perceived input delay and test duration were not separately reported.
- Remaining: longer gameplay, other display rates/network conditions, and optional rolling HUD skip-rate display. Unique game-image FPS and broader selectable pacing modes are separate work. Preserve honest distinctions between automated checks, observed main-menu playback and user-reported control feel.

Prevention: tests previously enforced a single latest-frame slot without testing two valid arrivals between draw ticks. Keep the callback-to-consumption regression and the per-stage counters so future low-latency changes are evaluated for both loss and delay.

## User gameplay feedback

2026-09-22: “我感觉比之前的效果好不少, 轻微的卡顿丢帧感明显减少了”. Record this as user-observed improvement, alongside the controlled counters above. It is not a zero-drop guarantee or an input-latency measurement.

## Reopened: longer session with controller input active

2026-09-22: User reported fast growth again. No playback-code changes occurred after the initial two-frame fix; only validation documents were edited. Read-only inspection of the same running process (PID 65482, launch 10:01 local) found a renewed failure. `diagnostics/long-session-regression.json` records a 37.043-second window: input +2239 (~60.44 fps), output +1963 (~52.99 fps), skipped +275 (~7.42/s), all inbox losses. Renderer replacement/busy/drawable misses remained zero. Recent arrival p95 ~17.7 ms, draw interval p95 ~53.5 ms, decode p95 ~2.9 ms, GPU p95 ~0.6 ms, drawable acquisition ~0.1 ms. Thus longer draw-callback gaps exhaust the two-slot buffer; the initial fix is incomplete.

`sample 65482 8 1 -file .build/pacing-long-session.sample.txt` captured substantial main-thread AppKit/SwiftUI layout/update work, including CloudLibraryView. A specific candidate is CloudVideoConnection.run reporting a status string containing controllerStatus every 250 ms; with controller input active, controllerStatus includes an ever-changing packet sequence, invalidating the observable library status. Earlier controlled before/after measurements had controller input disabled, so they did not cover this condition. This is a strong hypothesis, not yet an A/B-confirmed root cause. Keep the raw sample in ignored .build; it contains process metadata and should not be published as sanitized stream diagnostics.

Next: isolate stable connection status from high-frequency controller telemetry and validate the same active-controller workload. Do not keep enlarging buffering to conceal main-thread stalls. No code, settings, focus or session changes were made during this read-only follow-up (beyond ordinary AX reads); the current game remains running.

## Controller-driven UI invalidation follow-up

The user independently observed that disconnecting the controller mostly stopped skips. In the same old process, disconnected sampling covered 75.982 seconds and 22 skips (0.29/s). Reconnecting reproduced 79 skips in 11.035 seconds (7.16/s), with all loss still in the inbox. `diagnostics/controller-reconnect-before.json` fails the existing 1 skip/s diagnostic gate. The old process remained PID 65482, started 10:01; merely rebuilding had not updated it.

Candidate changes remove changing controller packet counts from the observable library status (report streaming once), use a cheap stream-state read for the 250 ms health loop instead of sorting timing windows, and update HUD snapshots at 1 Hz. Hidden HUD skips formatting/text layout. Redundant backing-size/title writes are avoided. Input frequency, decode and render cadence, and the bounded two-frame queue remain unchanged. 90 automated tests and the signed release build pass; live controller-active preset comparison is the required next gate. An isolated unit test cannot reproduce the cross-framework AppKit/SwiftUI scheduling effect; the real application/controller/HUD counter experiment is the regression seam.

Upstream findings are in `upstream-pacing-research.md`. Both inspected projects update HUD statistics around 1 Hz and keep rendering outside broad UI state updates. This supports the architecture change but does not establish they encountered this exact native macOS bug.


### Rebuilt app, controller active, three presets

New process PID 77581, Palworld Simplified Chinese main menu, requested HQ, received 1920×1080, same maximized 1920×1018 pt / 3840×2036 px canvas. Input remained enabled, focused, armed and sending packets.

| HUD | Interval | Skips | Skips/s | Presented / received |
| --- | ---: | ---: | ---: | ---: |
| Detailed | 37.72 s | 15 | 0.40 | 99.34% |
| Hidden | 40.95 s | 7 | 0.17 | 99.76% |
| Compact | 33.05 s | 7 | 0.21 | 99.64% |

All three `check-skip-rate.py diagnostics/hud-{preset}-after.json` runs pass the pre-existing <=1/s diagnostic threshold. Samples and boundary caveats are retained in `diagnostics/hud-controller-after.json`. Counters refresh at 1 Hz; hidden/compact endpoint reads briefly show Detailed. These sequential windows cannot establish zero overhead or statistically distinguish the small residual differences; they do rule out the previously large sustained ~7/s loss during this test.

Detailed HUD at ~136 seconds: STREAM avg 60.0, OUT avg 59.7, 37 skips, draw interval p95 17.6 ms, arrival p95 17.7 ms, decode p95 3.0 ms, GPU p95 0.5 ms, presentation p95 40.2 ms. No busy/drawable/renderer losses or decode errors. RTT 33 ms, jitter buffer 1.3 ms, network + client estimate 75.1 ms. No true end-to-end latency claim. User independently noted OUT avg 59.7 and a substantial improvement.

An 8-second sample of the fixed app with controller active and Detailed HUD shows no CloudLibraryView stack entries, whereas the prior failing sample did. A few HUD/timing-summary stacks remain as expected; sampling is corroboration, not an exact CPU budget measurement. Raw process samples remain in ignored `.build/`.

The main-thread library invalidation hypothesis is supported by controller disconnect/reconnect reproduction, the before/after rates and disappearance of library layout stacks. The combined change also reduces timing-summary frequency and redundant backing-size writes, so this is not a strict isolated attribution of every saved millisecond. No additional queue depth or input-rate reduction was used. Remaining occasional skips and extended gameplay are follow-up work; do not call this a zero-drop or zero-overhead guarantee.

Further Detailed window including the 8-second sampling profiler: 52.203 seconds, 26 skips (0.50/s), 3,138 received / 3,112 presented. At roughly 188 seconds since video start, cumulative OUT avg remained 59.6 against STREAM 60.0. Restored Compact HUD, left game running and controller active.
