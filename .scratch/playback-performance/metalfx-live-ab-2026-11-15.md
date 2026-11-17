# M1 live Original / MetalFX repeated comparison

Same live A Game About Digging A Hole title/menu session, Standard / Balanced, no game input. M1 8-core GPU, LG Ultra HD 3840x2160 at 60 Hz (system_profiler verified). XFrame `.build/pacing-trace/XFrame.app`, fullscreen 3840x2160 drawable, 1920x1080 video. Only scaling selection changed through the View menu. No build/tests ran during sampling. Each primary sample followed at least 20 seconds of foreground playback after mode selection (rolling window is 256 frames). These are HUD window samples, not whole-phase percentiles or physical input-to-photon measurements.

| Phase | GPU p95 ms | Display wait p95 ms | Arrival-display mean ms | Arrival-display p95 ms | Output FPS |
| --- | ---: | ---: | ---: | ---: | ---: |
| Original A1 | 0.6 | 23.8 | 40.9 | 43.1 | 60.0 |
| MetalFX B1 | 6.6 | 33.9 | 53.3 | 55.6 | 60.0 |
| Original A2 | 0.7 | 23.4 | 40.2 | 46.5 | 60.0 |
| MetalFX B2 | 6.7 | 34.1 | 55.1 | 58.9 | 60.0 |

Additional B1 observation before switching back: GPU p95 6.6, display wait p95 34.0, arrival-display mean/p95 48.2/50.7 ms. This illustrates phase variation and is not excluded as an outlier. During B1 a screenshot confirmed effective MetalFX Spatial 1920x1080 -> 3840x2160 and zero packet loss/NACK. UI transitions produced short drops; steady sampled output remained 60 FPS. Total skipped rose 6 -> 13 -> 18 -> 22 across primary samples; these are cumulative and not comparable per-mode rates.

MetalFX increased GPU time by about 6 ms AND post-GPU wait by about 10 ms, repeatedly reversible when Original was selected. Thus this implementation's enhancement/presentation path contributes to higher latency; GPU kernel cost alone does not explain the difference. Missing a display opportunity or altered presentation phase is a hypothesis, not proven from aggregate HUD samples. Do not generalize this to MetalFX being inherently unsuitable, or equate this with the user's M5 53.6 ms display-wait p95 / 69.7 ms arrival-display p95. The user's screenshot scales to 2940x1654, this run to full 4K. No persistent 47 FPS failure was reproduced.

The original scaling preference was restored after the comparison and the test session was ended. No production code changes were made in this experiment.

Final restoration observation after returning to Original, before confirming session end: GPU p95 0.7 ms, display wait p95 23.6 ms, arrival-display mean/p95 36.6/38.9 ms, output 60 FPS. This again shows reversal but is not a separately timed primary phase.
