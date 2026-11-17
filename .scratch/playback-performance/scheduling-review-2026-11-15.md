# Scheduling review and foreground playback investigation

User goal: lowest practical display latency and smooth sustained cadence. Real foreground playback is the acceptance boundary; average FPS and build success are insufficient.

## Source findings

Balanced retains two decoded frames. Overflow discards the oldest. At each draw, frames older than 50 ms are discarded; with a successor ready, an oldest frame older than 25 ms is discarded. Adaptive separately assigns RTP-derived deadlines. These policies do not cap the presentation queue.

The renderer consumes a frame before acquiring a drawable. Drawable acquisition can therefore age the selected frame. Three GPU permits are released on command completion, not actual presentation. Low GPU queue time cannot rule out completed-but-not-presented frames. The fixed requested 120 FPS is not the actual draw rate: this M1 baseline measured 16.667 ms mean draw intervals (~60 Hz).

All inbox discard reasons were previously combined. Schema 10 now records overflow, expiry, catch-up, renderer replacement, submission, GPU start/end, and invalid presentation, correlated by frame ID. Numeric ring storage remains bounded; no images or account data are recorded. Actual presentation timestamps remain distinct from callback receipt.

## Live baseline

Computer Use launched `.build/XFrame.app`, selected A Game About Digging A Hole, and observed its animated title/menu without entering gameplay or changing a save. Standard quality, Balanced, Original scaling, 1920x1080 input, 1920x1288 drawable. Foreground output reached 60 FPS. Source paths were rechecked against the current scheduler; this older local build has some UI text differences from the freshly built trial.

The exported baseline lasted 99.66 seconds including connection. 5209 decoded, 5161 shown, 48 skipped: 46 inbox, 0 renderer, 2 not shown. No packet loss/NACK or decode errors. Recent GPU mean 0.164 ms, drawable acquisition mean 0.080 ms, GPU queue mean 0.400 ms. Recent display wait mean 23.215 ms; total arrival-to-display mean 33.640 ms, p95 46.861 ms (includes end transition). Foreground observations before ending were about 33.5-34.9 ms mean, 36-36.8 ms p95. Early startup phase showed ~40 ms display wait. No claim of a physical input-to-photon measurement.

The bounded trace's 4091 presentation intervals had 16.667 ms median/p95 and 9 gaps over 25 ms, maximum 66.668 ms. This is the trace tail, not the entire session.

## Rejected drawable-depth experiment

An isolated signed build changed only `CAMetalLayer.maximumDrawableCount` to 2 in the presentation path. Same game/menu, input size, window, scaling and pacing. Foreground stable display wait remained about 23.1 ms; arrival-to-display observations varied with phase (~32-35.3 ms mean). This did not establish a latency benefit. The source change was removed. No VSync disabling or larger inbox was adopted.

A short test-suite run overlapped the middle of this trial; that portion is load-contaminated and cannot be used as an idle-performance comparison. Stable observations were taken after it completed. These are sequential cloud sessions, not a randomized same-session A/B; differences in total skips cannot establish superiority.

Artifacts: `diagnostics/2026-11-15/baseline.json`, `double-drawable.json` and analyzer summaries. Run `python3 scripts/analyze-presentation-trace.py REPORT.json`. Schema 9 lacks joined GPU stages and individual inbox reasons; these remain unavailable, never reported as zero.

## Starfold rechecked

Fetched https://github.com/JarvanSun/Starfold on this investigation; HEAD remains `cbc7e96d414173735f9e1f46ef88d07a8edbbfae`.

`Packages/StreamKit/Sources/StreamKit/Rendering/SystemVideoPresenter.swift` uses a host-clock timebase and timestamped sample buffers with AVSampleBufferVideoRenderer. `StreamRenderer.swift` drains an asynchronous FIFO with up to six pending frames. Its enhancement path waits for GPU completion. Its display latency uses the planned `presentAt` returned by enqueue, not an actual displayed timestamp. This makes system-scheduled presentation a valid isolated experiment candidate, but provides no evidence that replacing our backend improves latency. Existing XFrame adaptive RTP pacing already incorporates the relevant pacing idea; copying its larger queue would conflict with the low-latency goal without evidence.

Apple documents that CAMetalLayer normally presents asynchronously to Core Animation transactions; disabling display synchronization may cause tearing, so it is not an acceptable default shortcut:
https://developer.apple.com/documentation/quartzcore/cametallayer/presentswithtransaction
https://developer.apple.com/documentation/quartzcore/cametallayer/displaysyncenabled

## Acceptance boundary

The M5 user's sustained ~35% missing decoded frames has not been reproduced on this M1/menu/network. Do not declare its root cause fixed. Do not attribute all drops to packet loss, or treat a few-percentile reduction in a sequential session as an optimization. Need paired per-frame stage/reason evidence on the failing condition before changing production discard thresholds or presentation architecture.

## Schema 10 live verification

A third signed build restored the default drawable pool and added numeric tracing only. The same title/menu was run and ended through the UI, then `instrumented.json` was exported. The trace contained 3567 presentations with both matching arrival and GPU endpoints. Mean joined arrival-to-display 36.096 ms; GPU 0.265 ms; GPU queue 0.446 ms; post-GPU display wait 23.035 ms. Maximum matched completed-but-not-presented occupancy was two. 3566 display intervals had 16.667 ms p50/p95, six intervals over 25 ms. Discards recorded: seven inbox overflows, two catch-up skips, two invalid presentations, no expiry or renderer replacement. This directly verifies the new data rather than assuming emitted fields are populated.

209 tests passed after the trace/report changes, followed by eight targeted tests after the renderer replacement trace change; release build/signature verification passed. Existing replay tests (five) pass. The analyzer was checked with synthetic reversed event order, known joined timings, overlapping presentation waits, drops and absent stages. `git diff --check` passed. Final test session was ended, leaving the library open. No production pacing policy was changed and no performance-fix release was published.
