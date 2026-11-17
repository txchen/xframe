# Render Path Probe

Independent macOS app (`win.xframe.render-path-probe`). No XFrame process, streaming account, video decoder, network, MetalFX, or application HUD is involved. Uses a root opaque MTKView, BGRA8/sRGB, synchronized presentation and a clear-only render pass.

Build: `tools/display-probe/build.sh`. Open `.build/render-path-probe/Render Path Probe.app` and choose **Experiment → Start full-screen ABBA** (Command-R). The app enters native full screen and waits three seconds before four 12-second blocks. Stop and save is Command-period. Quit is Command-Q. It does not modify display settings or XFrame preferences.

- A: normal 60 fps MTKView callback submissions, up to three GPU commands in flight.
- B: the same callback/rendering/presentation path, but submits only when no prior actual presentation is pending and at least 0.5 seconds have elapsed since the last submission. This tests an effectively empty presentation queue; it is not a proposed playback strategy.
- Order: A B B A. The analyzer excludes the first three and last one seconds of each block.
- Each frame records drawable acquisition, submit, GPU start/end, actual `presentedTime`, callback execution, pending presentations, mode and full-screen state. Every MTK callback is recorded, including callbacks that do not submit.
- No periodic serialization, UI refresh or screenshot is performed during sampling. Results are written after rendering stops and callbacks get a one-second drain interval. Missing/error/zero timestamps are excluded and counted. Outstanding presentations at export must be checked.

Unique run directories: `~/Library/Logs/RenderPathProbe/<timestamp>-<id>/` with `status.json` and `events.json`.

Analyze:

```sh
python3 tools/display-probe/analyze.py /path/to/run/events.json
```

This first diagnostic holds the submission clock constant. It does not sweep every refresh phase, identify private compositor policy, measure physical photons, prove Direct-to-display, or establish a playable low-latency fix. A sparse-versus-continuous difference can reflect a system policy response as well as queue depth; follow-up must correlate real submit phases and compositor reads.

Next discriminating experiment: sweep sparse submissions across an independently observed refresh cycle, log requested and actual timing, and compare continuous submissions at the same actual phase. Use a short Instruments capture only to attribute compositor reads/swaps; performance rankings must come from unprofiled runs. Do not reuse the one-frame gate as a 60 fps product scheduler.

## Isolated submission phase scan

In a fresh launch choose **Start isolated phase sweep** (Command-P). Eight 8-second blocks request a delay of 0, 8, 2, 10, 4, 12, 6, 14 ms from an MTK callback before drawing one isolated frame. Each waits for zero outstanding presentations and at least 0.5 seconds since its previous submission. An independent CADisplayLink records refresh timestamps and targets. Requested offsets are not treated as actual submit times: the log records the observed submit/GPU timestamps and timer scheduling error. The sweep adds a display clock, so comparisons with the first ABBA run are diagnostic rather than a controlled estimate of the effect of the clock itself.

This scan tests a different question from previous continuously submitting phase sweeps: can a frame in an empty presentation queue reach the immediately upcoming refresh at any observed phase? Sparse samples do not prove 60 fps capacity or smoothness. After a promising phase is found, it needs a separate sustained test before calling it a fix.
