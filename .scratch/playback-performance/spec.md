# Local playback timing and bounded unattended regression

Collect a bounded latest-256 distribution for successful VideoToolbox submission-to-callback time, decoded-frame receipt to GPU submission, GPU command execution and decoded-frame receipt to drawable presentation. Export count, recent count, mean, nearest-rank p50/p95 and max in milliseconds. Unknown stages remain absent/n/a. Stream report schema advances to 2. No addresses, tokens, game identities, media or raw timestamps are recorded.

These are separate local intervals. They are not additive end-to-end segments: presentation includes frame waiting, while GPU is a subset. Local-file queue waiting includes deliberate scheduling/read-ahead; hardware decode callback time can include VideoToolbox reorder/scheduling. None establishes network latency, A/V synchronization, CPU utilization, power or controller-to-photon latency.

Avoid acquiring a drawable/command buffer on same-size ticks without a new frame. Preserve pending frame ownership if a drawable is unavailable; retries must still render and count presentation once. Keep the existing 120 Hz request and three-command bound unchanged until measured tradeoffs justify changing them.

Use real local H.264 hardware fixtures plus deterministic state tests. Repeated cancellation must release the full producer queue and the source object. RSS samples are observational and isolated where possible; allocator/framework caching means a short plateau or temporary growth is not definitive leak evidence. No unattended cloud sessions or UI/power-setting operations.

## Sources

- [Apple drawables best practices](https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/Drawables.html): acquire late and release promptly.
- [GPU start time](https://developer.apple.com/documentation/metal/mtlcommandbuffer/gpustarttime): use completed command-buffer timing; missing values must not become false zero-latency measurements.
- Prior repository stack audit: `../ui-polish/stack-research.md`.

## Live pacing follow-up — 2026-09-22

Measured losses occurred entirely when the single-frame inbox was overwritten between display ticks, with no GPU-busy/drawable failures. Replace that inbox with a two-frame FIFO, dropping the oldest on overflow and discarding frames older than 50 ms when consumed. Do not add startup prebuffering or unbounded memory. Preserve the existing render callback cadence and in-flight GPU bound for this isolated change.

Diagnostic schema 4 adds pacing data under timings: inbox/renderer replacements, draw/busy/drawable-miss counters, and latest-256 arrival/draw/drawable acquisition intervals. Detailed HUD labels skipped total explicitly and shows these numeric counters. Received callbacks and presentation counts remain distinct from unique game content. See pacing-investigation.md for evidence and remaining scope.

## Freshness and presentation accounting — 2026-09-22

Keep the proven MTKView cadence and default drawable pool. The latest-frame principle from Moonlight is applied selectively: preserve two-frame bursts, but retire a queued head older than 25 ms (1.5 intervals at 60 Hz) when another decoded frame is ready, avoiding a permanent one-frame backlog. The existing 50 ms stale-frame bound still applies. Do not accumulate more surfaces to make OUT look better.

Schema 5 adds GPU queue and post-GPU display timing, joining callbacks by frame in either order. Zero/invalid presented timestamps count as not-presented skips, never successful OUT. All stages retain bounded 256-sample windows. Current hardware experiments and rejected candidates are in issues/02-local-presentation-latency.md.

## Selectable pacing (2026-09-22)

Streaming Settings now saves Balanced (default) or Low latency (experimental) for the next session. The active source captures that policy at creation. Balanced preserves two slots and 25 ms catch-up; Low latency uses a single latest-frame slot; both retain 50 ms stale expiry and existing display synchronization. Detailed HUD and schema-6 reports identify active mode. 97 tests and signed build pass; live performance benefit of Low latency remains unverified.
