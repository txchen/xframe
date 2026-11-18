# XFrame 0.1.5 — Lower Original latency

- **Lower display latency in Original scaling.** Frames now render on a dedicated real-time thread, timed just before each display refresh. In matched xCloud sessions on M1, local frame age (decoder input to presentation) fell by about 7 ms, from about 40 to 33 ms. p95 and p99 also fell by 5–7 ms. Cadence, decoding and CPU use did not get worse. Entering or leaving full screen still pauses briefly, as it did before. Turn it off or back on at any time with **View → Low-Latency Original Rendering**, including during a stream.

Measurement boundaries: local decoder-input-to-presentation timing, not input-to-photon latency. Measured on M1; other Macs were not measured. Details: [acceptance results](https://github.com/txchen/xframe/blob/v0.1.5/docs/research/original-render-latency/acceptance-results-r2.md).

Requires Apple Silicon and macOS 27 or later.

```sh
brew update
brew upgrade --cask txchen/tap/xframe
```
