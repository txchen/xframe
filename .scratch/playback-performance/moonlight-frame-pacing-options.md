# Moonlight frame pacing options and XFrame recommendation

Date: 2026-09-22. Research only; no app code, build, running session or playback defaults changed.

## Recommendation

Implement a small, measured experiment before exposing a permanent setting: **Balanced (default)** retains current behavior; **Low latency (experimental)** would prefer fresher decoded frames with a strict queue/age bound. Only ship the second policy if repeated actual-presentation measurements demonstrate a useful latency reduction with an acceptable cadence tradeoff. Do not clone all four Android modes or equate a settings label with a macOS implementation. A smoothness-first mode can wait until there is evidence that current Balanced buffering is insufficient.

Frame pacing controls the spacing of displayed frames and the buffering/drop tradeoff. A stable average 60 fps does not establish evenly spaced presentation. These controls do not improve cloud host rendering FPS or decoder throughput by themselves.

## Desktop Qt: checkbox and platform boundary

Released v6.1.0 (`f786e94c7b2f943e24e65d7d74deb539b827fc84`) exposes a Frame pacing checkbox, enabled only with V-Sync. Its tooltip describes delaying early frames to reduce micro-stutter. Pinned development master (`032529d782242e3833e0b3b147dbbf96e878e3ca`) retains this boolean, not the Android four-mode selector. [Released UI](https://github.com/moonlight-stream/moonlight-qt/blob/f786e94c7b2f943e24e65d7d74deb539b827fc84/app/gui/SettingsView.qml#L808-L822), [development UI](https://github.com/moonlight-stream/moonlight-qt/blob/032529d782242e3833e0b3b147dbbf96e878e3ca/app/gui/SettingsView.qml#L819-L850).

The generic Pacer creates a VsyncSource for Windows/Wayland, not macOS, in both inspected versions. Therefore the checkbox does not activate that generic display-paced queue on Mac. This does NOT mean Mac has no pacing or V-Sync: Metal independently manages presentation. [Released platform switch](https://github.com/moonlight-stream/moonlight-qt/blob/f786e94c7b2f943e24e65d7d74deb539b827fc84/app/streaming/video/ffmpeg-renderers/pacer/pacer.cpp#L264-L311), [development platform switch](https://github.com/moonlight-stream/moonlight-qt/blob/032529d782242e3833e0b3b147dbbf96e878e3ca/app/streaming/video/ffmpeg-renderers/pacer/pacer.cpp#L262-L303).

Pinned development Metal uses CAMetalDisplayLink on Apple Silicon/macOS 14+ when V-Sync is enabled, requesting preferredFrameLatency=1. This is controlled by the renderer/V-Sync path, not the generic Frame pacing checkbox. It is development code, not evidence that v6.1.0 ships the same implementation. [Display-link setup](https://github.com/moonlight-stream/moonlight-qt/blob/032529d782242e3833e0b3b147dbbf96e878e3ca/app/streaming/video/ffmpeg-renderers/vt_metal.mm#L810-L824). See existing moonlight-latency-research.md for timer boundaries and backend differences.

## Android: four modes with real platform-specific behavior

Official FAQ describes Lowest latency, Balanced, Balanced with FPS limit, and Smoothest video. Lowest latency favors immediate release/latest frames; Balanced uses display callbacks and small buffering; FPS limit can request slightly below display refresh; Smoothest may accumulate substantial OS buffering. These are Android semantics, not portable desktop presets. [Official FAQ](https://github.com/moonlight-stream/moonlight-docs/wiki/Frequently-Asked-Questions#what-do-the-frame-pacing-options-on-the-android-client-mean).

Source checked at Android commit `b48494cb96bff23d8886c4775cc4f39a1075495d`:

- Balanced uses Choreographer and an output queue capped at two buffers; overflow discards oldest. The cap is not a requirement to wait until two frames accumulate. [Callback](https://github.com/moonlight-stream/moonlight-android/blob/b48494cb96bff23d8886c4775cc4f39a1075495d/app/src/main/java/com/limelight/binding/video/MediaCodecDecoderRenderer.java#L948-L993), [bounded enqueue](https://github.com/moonlight-stream/moonlight-android/blob/b48494cb96bff23d8886c4775cc4f39a1075495d/app/src/main/java/com/limelight/binding/video/MediaCodecDecoderRenderer.java#L1056-L1080).
- Non-Balanced modes first drain available decoder outputs, discarding older outputs. Lowest latency releases the latest buffer with current time; Smoothest/cap-FPS releases it with zero presentation timestamp to avoid downstream dropping. Thus FAQ wording about never dropping is not a literal guarantee of zero drops throughout the entire pipeline. [Exact branch](https://github.com/moonlight-stream/moonlight-android/blob/b48494cb96bff23d8886c4775cc4f39a1075495d/app/src/main/java/com/limelight/binding/video/MediaCodecDecoderRenderer.java#L1031-L1055).
- FPS cap changes requested stream refresh to rounded display refresh minus one in supported conditions. It falls back to Balanced when requested FPS exceeds display by more than three or detected refresh is implausibly low. Merely rendering locally at 59 Hz while continuing to receive 60 fps is not equivalent. [Host stream configuration](https://github.com/moonlight-stream/moonlight-android/blob/b48494cb96bff23d8886c4775cc4f39a1075495d/app/src/main/java/com/limelight/Game.java#L440-L470).

## Fit to current XFrame

Verified current code: Streaming/LiveVideo.swift limits decoded queue to two frames, discards frames older than 50 ms, and catches up to a newer ready frame when the head exceeds 25 ms. MetalRenderer.swift drives MTKView, requests 120 callbacks/s (actual depends on display), allows three GPU in-flight commands, and releases permits at GPU completion. Current policy is analogous in intent to Balanced, not a copy of Android Choreographer.

Saved final controller-connected measurements: OUT about 59.6 fps, skips 0.224–0.439/s, recent local presentation means 29.5–39.1 ms. GPU about 0.4 ms versus post-GPU display wait about 22.9 ms. See latency-optimization-validation.md. Most remaining time is scheduling/display; shortening only the decoded queue cannot be assumed to remove compositor waiting.

Prior 16.7 ms catch-up increased skips to 1.51/s; CAMetalDisplayLink and arrival-driven experiments also worsened local presentation and were reverted. These results do not prove all implementations fail, but they rule out treating an aggressive threshold or different driver as an already validated Low latency mode.

## Proposed implementation and acceptance boundary

1. Preserve current Balanced default and current V-Sync policy. Separate queue policy from display scheduling; test one change at a time.
2. Add an internal reversible Low latency candidate first, bounded in frame count and age. Evaluate fresher-frame selection without reintroducing per-frame observable UI updates.
3. Use same-session repeated A/B/A intervals, same display/window/controller/scene. Compare actual presentedTime mean/p95, displayed-frame interval distribution and long gaps, output coverage and skip reasons. Do not use OUT average alone or Moonlight renderer-call timings as proof.
4. Expose two user modes only if Low latency has repeatable benefits. Keep Balanced default; document potential motion unevenness. Include active mode in detailed HUD and exported reports; switching must safely trim excess queue entries.
5. Defer Smoothness-first until bounded extra buffering demonstrably improves cadence. Do not implement unbounded/no-drop queues, a 59 Hz local cap pretending to control xCloud host FPS, or promise a fixed 16.7 ms saving.

Decision record: issues/03-frame-pacing-options.md (needs-triage). Research completes the current request; a production setting is not yet implemented or performance-validated.
