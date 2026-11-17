# Independent render-path reproduction — 2026-11-16

No XFrame app or stream was started, stopped or modified during these tests. M1 / LG Ultra HD, native fullscreen 3840x2160. Independent app win.xframe.render-path-probe, clear-only GPU pass, synchronized presentation. CUA operated menus and confirmed completed UI; no screenshots during sampling, no profiler.

## Empty queue versus continuous MTK

Raw: ~/Library/Logs/RenderPathProbe/2026-11-16T16-53-42Z-F159659F/events.json
Source/hash/summary: first-repro/.

Four 12-second ABBA blocks, trim first3/last1s. All analyzed timestamps valid, fullscreen true, no outstanding callbacks at export.

| Block | Mode | Frames | GPU-end to actual median | Pending before submit median |
|---|---|---:|---:|---:|
| 0 | continuous60 | 480 | 63.43 ms | 4 |
| 1 | isolated | 16 | 22.59 ms | 0 |
| 2 | isolated | 16 | 22.76 ms | 0 |
| 3 | continuous60 | 479 | 23.34 ms | 1 |

Continuous blocks both ~60fps with zero >25ms intervals. The initial high-latency state is retained, not hidden. This app has no actual-presentation gate, unlike released XFrame: do not call its 63ms result a current XFrame regression. Logical outstanding frames do not equal live drawable object count.

Isolated frames wait >=0.5s and require zero actual-presentation callbacks outstanding. Their GPU execution medians ~0.08ms. This reproduces ~23ms post-GPU waiting without a decoded FIFO, live stream, conversion shader, MetalFX, or prior unpresented frame. It does not by itself prove a universal macOS minimum or identify compositor policy.

## Isolated phase scan

Raw: ~/Library/Logs/RenderPathProbe/2026-11-16T16-56-57Z-769D6609/events.json
Source/hash/summary: isolated-phase-sweep/.

Eight8s blocks, first3/last1s excluded; 7–8 analyzed frames/block, 63 total. A CADisplayLink provides independent refresh targets. Delay is requested from an MTK callback, and all observed submit/GPU times are retained. No old presentations pending at any analyzed submission; all fullscreen, valid timestamps, zero outstanding at export.

| Requested offset | GPU-end to actual median |
|---|---:|
| 0 ms | 22.73 ms |
| 2 ms | 19.99 ms |
| 4 ms | 17.50 ms |
| 6 ms | 32.27 ms |
| 8 ms | 30.44 ms |
| 10 ms | 28.26 ms |
| 12 ms | 26.19 ms |
| 14 ms | 24.53 ms |

Actual minus last recorded CAD target is ~16.71–16.77ms except offset6 (~33.40ms, GPU finishes after that target). This is sparse screening, not a sustained scheduling fix, and not evidence of a universal precise latch threshold. The sweep introduced a CAD clock; don't infer clock causality by comparing it to the preceding ABBA run. Main-timer wake error is measured, not assumed zero. In the sweep the CAD clock is logged on each callback; MTK tick rows omit callbacks returning before the delayed-draw gate.

## Next work

1. Repeat empty-queue phase samples with randomized/interleaved offsets and larger per-phase counts; normalize using actual GPU completion phase. Determine whether any frame reaches the immediately upcoming refresh. Keep failed/zero timestamps counted.
2. Capture a short sparse run with Instruments, joining app surface -> compositor read -> output swap; compare the observed sequence to an unprofiled matching run. We need to distinguish when the compositor accepts the surface from when it displays the output.
3. Audit the standalone window against Apple's direct-display setup, then isolate actual display output mode and composition conditions. Earlier drawable-size/color-format/window-level changes are not tests of physical display mode. Do not silently stop user apps or alter unrelated settings.
4. Only a candidate that changes this path gets a sustained60fps standalone test; return to XFrame after it survives cadence and latency checks. Fixed4ms offset is NOT such a proven fix.

Latest source adds only bounded in-memory logging and clears old idle events on run start after these captures; the exact measured source and binary hashes are archived above. No production scheduling change, push or release.
