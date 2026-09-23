# Palworld variable frame-rate timing capture — 2026-09-22

One user-operated Palworld capture was exported from the running XFrame app as `.build/fixtures/aaa.json` and preserved as [`samples/palworld-variable-fps-01.json`](samples/palworld-variable-fps-01.json). SHA-256: `ffdc7995f7678314c7d2d358a2bb5fbd64fb971f10069436f875a992331a6604`. The user reports the pattern is consistently reproducible and declined a second capture. Scene, graphics settings and display refresh rate were not separately recorded. The report contains numeric/typed diagnostics, not gameplay images or sound.

Schema 9, active capture: 52.46 seconds of bounded trace, 2,552 decoder-input access units, 2,552 hardware decode completions, 2,552 deliveries to LiveVideo and 2,534 actual drawable presentations. The report counted 17 cumulative skipped frames, 0 decode errors, 0 reported RTP packet loss and 0 NACKs. The trace has no missing decoded references for the replay.

## Where the rate changes

One-second windows (local report seconds) show the same broad cadence at all four stages:

| Interval | Decoder input fps | Decoded fps | Presented fps | Interpretation |
| --- | ---: | ---: | ---: | --- |
| 15–17 | 60 | 60 | 59.7 | Initial high-rate period |
| 21–23 | 32 | 32 | 32 | Short sharp dip; second 22 had 20 input fps |
| 29–37 | 50.1 | 50.0 | 50.0 | Sustained mid-rate period |
| 42–48 | 42.9 | 43.0 | 42.7 | Sustained low-rate period |
| 49–56 | 57.2 | 57.2 | 57.1 | Recovery toward 60 |
| 59–65 | 41.1 | 41.1 | 41.3 | Later low-rate period; final recovery is outside this capture |

These local-second windows are from the generated [evaluation](samples/palworld-evaluation-01.json); the 52.46-second trace begins at report second 14.45. Individual RTP timestamp intervals also lengthen with the dips. Thus the rate change is present by the **decoder input**, before hardware decode or Metal presentation. The first measurable complete-frame boundary is after WebRTC reassembly/jitter buffering. This cannot distinguish game rendering from encoder pacing or network/jitter-buffer behavior upstream of that boundary. RTP timestamps measure encoded-frame cadence, not whether adjacent images differ.

For frames matched by RTP timestamp, decoder input to completion was median 3.06 ms and p95 3.64 ms (one initial 98.91 ms outlier). Decode completion to LiveVideo delivery was median 0.07 ms, p95 0.13 ms. Delivery to actual drawable presentation was median 33.85 ms, p95 44.81 ms. These local intervals explain why presentation roughly follows input with some delay and a small number of skips; they do not give controller-to-photon latency.

## 60 fps replay model

The [replay script](../../scripts/replay-frame-trace.py) maps each original to its nearest 60 Hz tick (at most 8.33 ms retiming). A tick without an original uses the two bracketing RTP frames; if two originals compete for one tick, it keeps the closer one. The output file records the exact RTP pair, interpolation fraction and required reference-ready delay for every tick.

Across 3,148 target ticks in this capture, the model retains **2,536 original frames** and requires **612 generated frames**; 15 source frames compete for already occupied ticks and would be skipped under this policy. The number is specific to this captured cadence and this assignment policy. In the sustained 42–48 second low-rate period, 300 of 420 output ticks keep originals and 120 need interpolation. In the 49–56 second recovery, 458 of 480 keep originals and 22 need interpolation. A perfectly aligned 40→60 fps second would instead use 40 originals and generate 20.

The model's reference-ready delay relative to a timeline anchored at the first decoder input is median 4.01 ms, p95 18.71 ms and p99 35.95 ms. Covering every tick with one fixed delay would require 98.91 ms because the first decode callback was unusually late; after the first second, the maximum is 54.16 ms. In the 42–48 second low-rate period, modeled delay is p95 17.4 ms and p99 22.7 ms, with one 54.2 ms outlier. These are simulated timing requirements, **not measured added user-visible latency**. Actual extra latency depends on how a future interpolator shares the existing presentation wait, its compute time and the display schedule. The current measured delivery-to-presentation median is already 33.85 ms, but it cannot simply be subtracted from the modeled delay.

No interpolation was run, and no image-quality or motion-artifact judgment is possible from numeric timestamps alone. Before shipping an interpolation mode, measure its GPU time, drawable presentation and controller feel during gameplay. This capture establishes the timing workload and where the observed cadence decline first appears in XFrame's measurable pipeline.

## Verification

`PYTHONDONTWRITEBYTECODE=1 python3 scripts/test-frame-replay.py` passes five tests, including a continuously varying synthetic 58→42→58 trace, competing originals, missing references and RTP wrap/discontinuity handling. The replay command succeeds on the real capture with zero unavailable reference ticks. The Swift suite and signed app build were completed when the tracer was introduced; this change only revised the offline replay policy and documentation.
