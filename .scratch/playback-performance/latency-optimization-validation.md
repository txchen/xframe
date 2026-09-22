# Native streaming latency experiments — 2026-09-22

## Retained changes

- Same-frame timing joins GPU and drawable callbacks in either order. Non-overlapping intervals: decoded arrival → submission → GPU start → GPU end → actual reported display. Existing presentation includes all of these; no double-counting in the estimate.
- Zero/invalid drawable timestamps are not successful presentations. OUT increments only for a valid shown frame; skipped/not-shown accounts for failures. Late callbacks cannot mutate stopped reports.
- Preserve the two-frame burst queue, but catch up when a fresher decoded frame exists and the head is older than 25 ms (1.5 intervals of the current 60 fps stream). Keep the 50 ms overall stale bound. Normal two-frame jitter remains buffered.
- Preserve MTKView scheduling, VSync, the default drawable pool, controller packet frequency and 1 Hz HUD summaries. No temporary experimental menu or additional per-frame UI state remains.

## Regression evidence

`zeroDrawableTimeDoesNotCountAsDisplayed` failed before the callback guard (OUT was 1 after a zero timestamp), then passed. `livePlaybackPrefersFreshFrameAfterExcessBacklog` failed before catch-up (returned frame 1 after a 30 ms backlog), then passed. The final suite additionally preserves ordinary 20 ms jitter and short two-frame bursts. 95 tests pass; signed release build and diff whitespace checks pass.

## Rejected alternatives

- CAMetalDisplayLink integration: mean ~57–73 ms local presentation, worse than the prior timer. Saved report fails the 25 ms mean / 40 ms p95 experiment target. Not retained.
- Drawing immediately for each coalesced decoded-frame arrival: OUT near 59.7 but local presentation ~77–89 ms, blocking drawable acquisition and ~64 ms post-GPU wait. Not retained.
- Two versus three drawables: sequential whole-latency changes were not isolated from queue/VSync phase changes; fullscreen post-GPU waits were ~23 ms for both. No default change retained.
- Aggressive 16.7 ms catch-up: 97 skips in 64.286 s, 1.51/s; failed the existing <=1/s skip gate. Replaced by 25 ms rather than accepting a stutter regression.

## Limits of comparison

These are sequential live Palworld cloud sessions, not an externally synchronized input-to-photon benchmark. Host/RTT and arrival/display phase can change between sessions. End-session reports contain the latest 256 timings and can include the short focus transition to the library; prefer foreground HUD intervals when judging steady playback. Initial instrumented controller-active foreground snapshots were ~36–42 ms local mean, while the exported final window was 46.09 ms. No cherry-picking of these values as a universal baseline.

An initial cloud setup attempt failed before video; a later idle session closed with a WebRTC error. Neither has been attributed to the rendering changes. No automatic input spam or reconnect was added. The controller later disconnected, and final physical-controller gameplay acceptance remains separate from automated and foreground video checks.

Final live measurements are recorded below after the completed run. The initial ambitious <=25 ms mean target remains open unless the saved evidence actually passes it.

## Final live verification

Palworld main menu, requested HQ / Simplified Chinese, received 1920×1080, maximized 1920×1018 pt / 3840×2036 px canvas. Controller input enabled but physical controller disconnected for these final intervals; the user was asked to reconnect but had not replied. Preserve this acceptance limit.

| HUD | Foreground interval | Skips | Skips/s | Shown / received |
| --- | ---: | ---: | ---: | ---: |
| Detailed | 70.281 s | 18 | 0.256 | 4,191 / 4,209 |
| Hidden | 63.355 s | 17 | 0.268 | 3,776 / 3,793 |
| Compact | 79.798 s | 19 | 0.238 | 4,801 / 4,820 |

All three saved interval files pass `check-skip-rate.py` (<=1/s). Session HUD shows STREAM approximately 60.0 / OUT approximately 59.7. These are real display counts under the corrected zero-timestamp policy, not unique game-content frames. No ongoing large HUD-dependent drop-rate gap was observed; this is not proof of zero telemetry overhead.

Recent foreground presentation snapshots: mean 35.9, 31.4, 34.3, 36.9 ms; p95 38.5, 34.3, 37.0, 39.3 ms. These are rolling last-256 windows, not a claimed 31 ms session average or a controlled fixed millisecond win over every prior phase.

Final exported report `diagnostics/latency-freshness-balanced-final.json`: 267.493 s session (includes setup), 15,161 decoded, 15,090 actually displayed, 69 skipped, zero decode errors and zero reported packet loss. Display coverage 99.532%. Its last timing window includes the focus transition used to end/export: mean 37.17 ms / p95 51.27 ms, so the ambitious 25 ms mean / 40 ms p95 gate still FAILS. Do not omit this failure or mark the latency target complete. GPU execution mean 0.44 ms versus post-GPU display mean 24.35 ms supports further compositor/presentation investigation.

The final signed app is built; all 95 tests pass and `git diff --check` is clean. Experimental code is isolated in ignored `.build/`; no experimental menu, display-link driver, arrival-driven driver or pool-size switch remains in Sources/Tests. The test session was ended cleanly and the library is ready for user gameplay. Remaining acceptance: physical controller gameplay on the final policy, extended sessions, and a lower actual display-latency target with comparable window/display conditions.

## Final controller-connected follow-up

After the user reconnected Xbox Wireless Controller, started a new HQ / zh-CN Palworld session using the same final signed app. Input remained active; sent packets increased from 3,556 through 5,773 to 8,054 at the interval endpoints. Controls were released; this checks continuous controller input overhead, not manual gameplay responsiveness.

| HUD | Interval | Skips | Skips/s | Shown / received | Endpoint local mean / p95 |
| --- | ---: | ---: | ---: | ---: | ---: |
| Detailed | 35.862 s | 15 | 0.418 | 2,096 / 2,112 | 36.7 / 39.1 ms |
| Hidden | 38.711 s | 17 | 0.439 | 2,339 / 2,355 | 29.5 / 32.1 ms |
| Compact | 40.157 s | 9 | 0.224 | 2,407 / 2,417 | 39.1 / 41.1 ms |

All three controller-final-*.json files pass check-skip-rate.py. Counters refresh at 1 Hz; interval endpoints include brief preset transitions, so shown/received coverage is preferable to interpreting wall-clock sample ratios as exact output FPS. HUD reported STREAM 59.9 / OUT 59.6 fps. Last detailed observation: zero decode errors, zero reported packet loss/NACK, 41 inbox skips and one not-shown frame, GPU mean 0.4 ms and display wait 22.9 ms. No controller-associated high skip-rate regression appeared in these short windows. Phase-dependent rolling latency still exceeds the 25 ms mean target; do not mark that target complete.

Restored Compact HUD and left the game running for manual gameplay. Final controller-connected foreground pacing is now checked; movement/camera feel and extended-session acceptance remain user checks. No source changes or rebuild were needed for this follow-up.
