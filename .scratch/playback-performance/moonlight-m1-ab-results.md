# M1 Moonlight-style scheduling comparison

## Verdict

An input-driven rendering worker can remove a refresh cycle of input waiting at unfavorable arrival/display phases while preserving 60 Hz output. It does not consistently remove GPU-to-display waiting. Explicit Moonlight-style scheduled presentation did not improve latency in this experiment. This is a local scheduling diagnostic, not a live XFrame performance fix or a benchmark of the Moonlight binary.

Reference mechanism: Andy Grundman Moonlight fork `57088f1a22bd7a3f1ced1af5102444edcc422241`, reviewed in `moonlight-presentation-review.md`. Independent Swift diagnostic implementations, no production scheduler modifications.

## Conditions and measurement

M1 Mac mini, macOS 27.2.1, same 3840x2160 60 Hz LG display. Native fullscreen confirmed in app telemetry; all sampled drawables 3840x2160. Optimized `swiftc -O`. Start load average 1.26/1.53/1.75 on 8 CPU cores. No Instruments during reported performance comparisons. Single MTKView/CAMetalLayer, opaque BGRA8/sRGB, display synchronization enabled, three drawables, identical clear-color render pass. A separate 60 Hz dispatch timer produces frame IDs; FIFO capacity two. Frame content varies with source ID. This has no network, decoder, MetalFX or game input.

Every comparison has five alternating 15 s blocks per side, discarding first 3 s and final 1 s of each block (about 660 presented frames per analyzed block). Measurements use actual `drawable.presentedTime`, not callback execution time or requested presentation time. Sample-level GPU errors, missing timestamps, queue drops, >25 ms displayed-frame intervals, and output rate are checked. Zero presentation timestamps at startup/transitions are retained but excluded from latency. Discrete UI checks only around tests; no continuous screenshot polling.

## Comparison 1: MTK callback versus worker with drawable backpressure

A: automatic MTKView draw callback (preferred 120, actual screen 60), nonblocking GPU semaphore three, dequeue input then acquire drawable. B: pause automatic drawing, worker acquires drawable then waits for input, FIFO dequeue, identical `command.present`, commit, next drawable acquisition on the next loop. Release MTK cached drawables at transitions. No displayed-callback semaphore gate.

All ten blocks output about 60 fps, zero analyzed long intervals, drops, missing frames and GPU errors. However the display state changes in integer-refresh steps during the run. Early A/B totals are both about 58–60 ms; late totals fall to 44 and 28 ms. Worker input waiting is about 0.03 ms versus A 1.3–3.9 ms. This run does NOT establish a stable latency win. It demonstrates that reduced application waiting can be absorbed by downstream presentation waiting.

The event stream shows up to roughly four submitted-but-not-yet-presented frames during the high-delay state despite a three-drawable pool. This is a logical outstanding-frame count from timestamps, not four simultaneously held CAMetalDrawables. Drawable reuse therefore must not be equated with the prior content reaching display.

Files: `diagnostics/2026-11-15/moonlight-ab/moonlight-ab/run1-events.json` and `run1-analysis.json`. `events.json` additionally contains a later instrumented run; do not pool the runs.

## Comparison 2: immediate versus scheduled presentation on worker

Both sides run the same worker and a persistent NSWindow CADisplayLink. B calculates the upcoming refresh deadline from the display timestamps and requests one interval after that deadline, via drawable.present(at:) in a command-buffer scheduled handler. A uses command.present(drawable). Same fixed refresh and FIFO source.

| Pair | Immediate total median ms | Scheduled total median ms |
|---|---:|---:|
| 1 | 21.93 | 22.26 |
| 2 | 22.54 | 22.86 |
| 3 | 23.17 | 23.48 |
| 4 | 23.79 | 24.89 |
| 5 | 24.86 | 24.84 |

All analyzed blocks 60 fps, zero queue drops, >25 ms intervals, missing frames or GPU errors. The gradual phase drift affects both modes; no stable reduction from scheduled presentation.

Across all 4,500 scheduled submissions, actual display minus requested target is median 16.734 ms (range 16.668–16.799 ms). GPU finishes before the requested target for every frame: median margin 5.905 ms, range 4.271–8.368 ms. This proves the actual display is one cycle later than requested under these conditions. It does NOT prove GPU completion met the compositor's earlier latch deadline, nor establish an unavoidable macOS floor.

## Comparison 3: callback versus worker with the display clock held constant

Repeat comparison 1 with a persistent CADisplayLink running on both sides; callback only keeps the clock active, it does not render or schedule presentation. This controls a difference between the first probe and the Moonlight-like loop. Five pairs:

| Pair | MTK input wait median ms | Worker input wait median ms | MTK input-to-display median ms | Worker input-to-display median ms | Paired reduction ms |
|---|---:|---:|---:|---:|---:|
| 1 | 13.77 | 0.02 | 54.25 | 37.89 | 16.36 |
| 2 | 14.42 | 0.03 | 38.17 | 21.81 | 16.36 |
| 3 | 15.07 | 0.04 | 38.80 | 22.43 | 16.37 |
| 4 | 15.68 | 0.03 | 39.42 | 23.05 | 16.37 |
| 5 | 16.31 | 0.04 | 40.07 | 23.68 | 16.39 |

Median of per-block medians: 39.42 ms versus 23.05 ms. Ranges including first-pair higher-delay state: 38.17–54.25 versus 21.81–37.89 ms. All analyzed blocks output 59.99–60.00 fps; zero queue drops, >25 ms intervals, missing frames and GPU errors. GPU execution ~0.08 ms on both sides. First pair shows higher downstream delay in both modes; not discarded selectively. Stable later worker GPU-to-display remains 20.9–22.8 ms.

This supports an approximately one-refresh improvement at the tested arrival phase. Comparison 1 prevents generalizing that improvement to every phase or declaring CADisplayLink alone the cause. Timer/refresh drift is visible and intentionally not hidden.

## Separate system trace: where GPU-to-display time goes

35-second Metal System Trace, app PID 86416. Joined app present request and command-buffer GPU end to first WindowServer IOSurface read, compositor GPU completion, and output-surface swap. 2,091 unambiguous joins. Join script guards surface reuse, output overwrite and ambiguous output swaps. WindowServer PID 652. System trace is mechanism evidence only, not performance A/B data.

Mapping trace Mach epoch to the application's second-run markers gives:

| Block | Mode | Frames joined | GPU end to WS read median ms | WS work median ms | WS GPU end to swap median ms | Total post-GPU median ms |
|---|---|---:|---:|---:|---:|---:|
| 0 | MTK | 389 | 26.934 | 1.814 | 10.704 | 39.434 |
| 1 | Worker | 638 | 15.308 | 1.858 | 10.476 | 27.669 |
| 2 | MTK | 591 | 10.041 | 1.775 | 10.959 | 22.867 |

Same MTK mode changes from ~39.4 to ~22.9 ms post-GPU, with almost all difference before the compositor reads the app surface. Thus neither mode name nor GPU work alone explains the queue state. The compositor is doing ~1.8 ms of GPU work; waiting dominates. Independent median columns need not sum exactly.

The joined surface path proves composition for these frames. Generic Direct-rejection reason tables in this capture exported no rows, so do not claim this run determined the private eligibility predicate. Prior minimal-window traces already recorded `display rejected`.

Local trace: `.build/moonlight-ab/scheduling.trace`; exports and join results in `.build/moonlight-ab/trace-export`. Do not publish raw trace/toc blindly: trace metadata contains process environment.

## Product implications

1. Investigate an input-driven dedicated render path that acquires presentation capacity before selecting input. It can remove application callback waiting; it needs live-stream validation with bursty arrivals, MetalFX workloads, resize/fullscreen changes and shutdown before adoption.
2. Do not blindly take newest on every callback: the previous five-pair live experiment lost FPS for only ~2 ms benefit.
3. Do not gate all work on a single actual-present callback: prior live experiment cut output to 30 fps.
4. Do not assume scheduled-present API or a three-drawable pool eliminates compositor queueing. This run directly contradicts that assumption.
5. Remaining display-chain latency requires correlating compositor latch timing and Direct eligibility; these experiments do not establish the OS's private decision or promise sub-16 ms GPU-to-display.

All three standalone test apps were closed after completion. Production files were not modified by these comparisons. Existing diagnostic worktree changes were preserved; `git diff --check` passes. No new release issued and no claim that real XFrame streaming latency is now 23 ms.
