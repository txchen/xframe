# Original presentation investigation — M1, 2026-11-16

The useful change is to bound submissions waiting for **actual presentation**, rather than relying only on GPU completion. It prevents an extra queued frame from persisting after an additional submission. It does not remove the normal ~22–23 ms GPU-to-display interval on this machine.

## Reproduction and boundary

M1 Mac mini, LG 4K 60 Hz display, XFrame Original, native fullscreen, Standard/Balanced 1080p60 cloud stream of the title screen of A Game About Digging A Hole. Detailed HUD enabled in the final comparisons. No gameplay/save changes. No profiler or compilation during those comparisons.

Arrival means delivery of a decoded video frame to XFrame, not network arrival or user input. Display uses `MTLDrawable.presentedTime`. A separate Metal System Trace comparison matched these timestamps to physical display-surface swaps within 0.009 ms; this still is not input-to-photon measurement. Per-stage percentiles cannot be added to reconstruct the total percentile.

## Final comparisons

Both runs used twelve 12-second blocks, six per variant, in the order A B B A B A A B A B B A. A is the existing MTK renderer; B keeps that renderer and limits outstanding actual presentations to two. Analysis excludes the first three and last one seconds of each block.

| Run | Existing renderer | Two-presentation limit | Interpretation |
| --- | --- | --- | --- |
| Extra-draw stress | Up to three pending presentations; two blocks remained at 39.55 / 47.20 ms median display wait | At most two pending; all six blocks 22.34–22.60 ms | Prevents persistent extra buffering under this controlled trigger |
| Normal streaming | Median display wait 22.4–22.7 ms | Median display wait 22.4–22.7 ms; no gate rejections in any B block | No meaningful normal-case latency improvement or throughput regression |

Stress injected one additional invalidated draw shortly after a normal submission in each block. It is a mechanism test, **not** an estimate of ordinary-playback speedup. Stable output stayed about 60 fps on both sides. The normal comparison had five vs four intervals over 25 ms and zero vs one over 40 ms; this short run cannot establish long-duration gameplay smoothness. Arrival-phase-adjusted normal-case difference was only 0.27 ms.

## Implementation

`PresentationQueue` reserves before taking a source frame. Original live playback allows at most two reservations. The presented callback returns the reservation, including a callback with an invalid/zero presentation timestamp. GPU failure also returns it. Completion is idempotent and thread-safe; abandoning an unsubmitted draw returns its reservation on destruction. Other modes are counted without this limit, so switching back to Original waits for earlier outstanding submissions.

The GPU semaphore remains separate. The MTK clock, shaders, source FIFO, expiry/catch-up policy, and frame budgets are unchanged. Limiting to one actual presentation was rejected because it reduced output to roughly 30 fps. Limiting drawable count alone did not provide the same guarantee.

## Alternatives rejected

- Moonlight-style AVSampleBufferDisplayLayer paths sometimes lowered age but lost displayed frames; internal zero-drop counters alone were insufficient evidence.
- Moving Original rendering to a worker did not consistently lower actual display latency.
- Submitting later on the main thread saved about four milliseconds in some configurations, but occasional late submissions added an entire refresh. A deadline guard reduced that risk with additional short frame gaps and machine-specific timing assumptions.
- Disabling display synchronization changed the measurement/display behavior and did not qualify as a smooth, equivalent result.

The experiments do not establish an unavoidable macOS latency floor, a general WindowServer bug, or a MetalFX cause for Original latency. The remaining normal display interval still needs a safe, repeatable improvement before claiming that every frame is one refresh faster.

## Evidence and validation

- Numeric events, analysis scripts, and exact probe sources: `diagnostics/2026-11-16/main-gate2-stress/` and `main-gate2-clean/`.
- Broader experiment record: `live-worker-results.md`.
- Full test suite: 213 tests passed, including four reservation lifecycle/concurrency tests.
- Release-mode app built and signature verification passed at `.build/original-presentation-bounded/XFrame.app`.
- Production-path live lifecycle validation passed in two fresh sessions: first frame, windowed/fullscreen transitions, MetalFX-to-Original, session end, and reconnect. Original recovered to 59.5–60 fps; after switching back, HUD display wait mean 22.5 ms / p95 23.2 ms and arrival-to-display mean 34.0 ms / p95 45.6 ms. The fresh second session showed 60 fps, display wait mean 23.0 ms / p95 23.6 ms, arrival-to-display mean 39.9 ms / p95 42.7 ms. These are rolling HUD snapshots, not additional controlled A/B results. Transition intervals did drop frames; no claim of seamless fullscreen animation. No stuck playback or decode errors observed. Both sessions ended explicitly; no gameplay actions were sent.
- Tested executable SHA-256: `361ec7468ac2fdf3a13925c8f7304670f5004b31820236cc9a7a5bccc53c7de9`. Build/test evidence is retained under `diagnostics/2026-11-16/production-queue/`.
- This local build has not been published to GitHub or Homebrew. M5 behavior remains unverified.
