# Local Video Playback

Scope approved by the user on 2026-09-21.

## Outcome

Open a local H.264 video and play it through hardware decoding and the existing native Metal window. Validate the video path before adding Xbox services or network transport.

## Scope

- macOS 27 and Apple Silicon.
- File picker for MP4/MOV video, replay from the beginning, and stop back to the static test pattern.
- Explicit VideoToolbox hardware H.264 decoder, verified by querying the active session.
- NV12 CVPixelBuffer surfaces imported using CVMetalTextureCache; YCbCr conversion runs in a Metal shader.
- Timestamp-based playback driven by MTKView's display refresh callbacks.
- Aspect Fit, Retina backing pixels, native full-screen, and resizing.
- Diagnostics for hardware status, average decoded and actually presented video FPS, skipped decoded frames, and queue occupancy.
- Clear loading, playing, ended, and failed states.

## Boundaries

- SDR BT.601/BT.709 video, square pixels, no rotation or clean-aperture crop. Unsupported inputs must fail visibly.
- Presentation timestamps must not precede decode timestamps. Invalid decode timestamps are interpreted as presentation order, following CoreMedia's convention.
- Audio, seeking, pause, HDR, MetalFX, Xbox login, WebRTC, and adaptive streaming frame pacing are deferred.
- A 16-frame sorted lookahead supports H.264 B-frame ordering with bounded local-file read-ahead. The producer waits when full; GPU work is independently capped at three submissions. This local-file buffer is not the future low-latency streaming queue.
- A decode-timestamp watermark keeps pending B frames ahead of future reference frames when recovering from display stalls. Selection tolerates half a source-frame interval of callback jitter, capped at 16.67 ms.
- FPS values are playback-to-date averages, not rolling measurements or estimates of unique game content. Presented frames are counted through drawable presentation callbacks, not redraws or command submission.
- Local playback does not establish end-to-end streaming latency.

## Acceptance

- Play a generated 1080p60 H.264 file with B frames through EOF.
- Verify hardware decoding, monotonic output timestamps, exact decoded frame coverage, NV12 IOSurface output, bounded queue occupancy, and cancellation.
- Inspect moving video and diagnostics in the native window; verify replay and stopping.
- Exercise malformed or unsupported input without a blank, unexplained screen.
