# Local playback timing and bounded unattended regression

Collect a bounded latest-256 distribution for successful VideoToolbox submission-to-callback time, decoded-frame receipt to GPU submission, GPU command execution and decoded-frame receipt to drawable presentation. Export count, recent count, mean, nearest-rank p50/p95 and max in milliseconds. Unknown stages remain absent/n/a. Stream report schema advances to 2. No addresses, tokens, game identities, media or raw timestamps are recorded.

These are separate local intervals. They are not additive end-to-end segments: presentation includes frame waiting, while GPU is a subset. Local-file queue waiting includes deliberate scheduling/read-ahead; hardware decode callback time can include VideoToolbox reorder/scheduling. None establishes network latency, A/V synchronization, CPU utilization, power or controller-to-photon latency.

Avoid acquiring a drawable/command buffer on same-size ticks without a new frame. Preserve pending frame ownership if a drawable is unavailable; retries must still render and count presentation once. Keep the existing 120 Hz request and three-command bound unchanged until measured tradeoffs justify changing them.

Use real local H.264 hardware fixtures plus deterministic state tests. Repeated cancellation must release the full producer queue and the source object. RSS samples are observational and isolated where possible; allocator/framework caching means a short plateau or temporary growth is not definitive leak evidence. No unattended cloud sessions or UI/power-setting operations.

## Sources

- [Apple drawables best practices](https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/Drawables.html): acquire late and release promptly.
- [GPU start time](https://developer.apple.com/documentation/metal/mtlcommandbuffer/gpustarttime): use completed command-buffer timing; missing values must not become false zero-latency measurements.
- Prior repository stack audit: `../ui-polish/stack-research.md`.
