# XFrame 0.1.5 — Lower Original latency and Keychain sign-in

- **Lower display latency in Original scaling.** Frames now render on a dedicated real-time thread, timed just before each display refresh. In matched xCloud sessions on M1, local frame age (decoder input to presentation) fell by about 7 ms, from about 40 to 33 ms. p95 and p99 also fell by 5–7 ms. Cadence, decoding and CPU use did not get worse. Entering or leaving full screen still pauses briefly, as it did before. To use the previous path:
  `defaults write win.xframe.app XFrame.Experimental.OriginalRenderWorker -bool NO`
- **Sign-in is stored in the macOS login Keychain.** The saved Microsoft sign-in moves automatically from the previous owner-only file. The file is removed only after the Keychain copy has been read back successfully. If migration fails, the file keeps working and migration is retried later. Updates signed by the same team read the item without new prompts. Sign Out removes the saved sign-in.

Measurement boundaries: local decoder-input-to-presentation timing, not input-to-photon latency. Measured on M1; other Macs were not measured. Details: [acceptance results](https://github.com/txchen/xframe/blob/v0.1.5/docs/research/original-render-latency/acceptance-results-r2.md).

Requires Apple Silicon and macOS 27 or later.

```sh
brew update
brew upgrade --cask txchen/tap/xframe
```
