# Upstream playback pacing and HUD research

Verified 2026-09-22 against upstream HEAD using `git ls-remote`:

- Better xCloud: `redphx/better-xcloud`, `f8397043f6d2148d2345d508902a38c69cf1ee20`; read-only checkout `.build/references/better-xcloud-f839704`.
- XStreaming: `Geocld/XStreaming`, `383e19d324f2d3029d1c304752f4d38a9360bb95`; existing reference `.build/references/XStreaming-383e19d` matches current upstream HEAD.

No upstream code was executed. These findings describe the inspected implementation, not a reproduced upstream performance benchmark or an exhaustive issue-history audit.

## UI updates and rendering

Better xCloud refreshes its stats overlay once per second. Hiding it clears the interval. An update writes individual stats spans rather than rebuilding a whole application view. This is a useful design precedent for keeping frequently changing diagnostics out of XFrame's broad SwiftUI observation graph. It does not prove that Better xCloud previously hit the same macOS bug. [Stats overlay, lines 19, 86–114, 145–175](https://github.com/redphx/better-xcloud/blob/f8397043f6d2148d2345d508902a38c69cf1ee20/src/modules/stream/stream-stats.ts#L86-L175).

XStreaming's native screen samples `getStreamState()` at 1 Hz, calls React `setPerformance` only while the performance panel is shown, and separately records session diagnostics. Controller packet flushing defaults to 62.5 Hz and occurs in the input channel, independently of the performance state. [NativeStream 2096–2142](https://github.com/Geocld/XStreaming/blob/383e19d324f2d3029d1c304752f4d38a9360bb95/src/pages/NativeStream.tsx#L2096-L2142), [Input 106–144](https://github.com/Geocld/XStreaming/blob/383e19d324f2d3029d1c304752f4d38a9360bb95/src/webrtc/Channel/Input.ts#L106-L144).

The native XStreaming screen gives the media stream to `RTCView` (or its native FSR view); it does not push every decoded video frame through React state. [NativeStream 2820–2856](https://github.com/Geocld/XStreaming/blob/383e19d324f2d3029d1c304752f4d38a9360bb95/src/pages/NativeStream.tsx#L2820-L2856).

Better xCloud's ordinary video player leaves frame rendering to the browser video element. Its custom canvas pipeline prefers `requestVideoFrameCallback`, falls back to animation callbacks, and always draws at a target of 60 FPS or higher; intentional skipping only implements lower target FPS. There is no directly transferable native two-slot Metal queue algorithm in these inspected paths. [VideoPlayer 9–49](https://github.com/redphx/better-xcloud/blob/f8397043f6d2148d2345d508902a38c69cf1ee20/src/modules/player/video/video-player.ts#L9-L49), [BaseCanvasPlayer 25–32 and 80–122](https://github.com/redphx/better-xcloud/blob/f8397043f6d2148d2345d508902a38c69cf1ee20/src/modules/player/base-canvas-player.ts#L80-L122).

XStreaming does have Android-specific low-latency decoder tuning, including `low-latency`, `priority`, `operating-rate`, `allow-frame-drop` and vendor parameters. This explicitly permits drops to keep latency low; it is not evidence that sustained ~7 dropped frames/s is normal or desirable, and these MediaCodec settings are not VideoToolbox settings. [LowLatencyVideoDecoder 184–209](https://github.com/Geocld/XStreaming/blob/383e19d324f2d3029d1c304752f4d38a9360bb95/android/app/src/main/java/com/xstreaming/webrtc/LowLatencyVideoDecoder.java#L184-L209).

## HQ indicator

XStreaming displays actual inbound resolution, then appends `(HQ)` when requested settings have `resolution === 1081`. Thus HQ describes the requested profile, not a verified host class, actual resolution upgrade, or guaranteed bitrate. XFrame should expose the active session's captured SQ/HQ request separately from actual received dimensions; changing next-session preferences must not relabel an existing session. [PerfPanel 60–74](https://github.com/Geocld/XStreaming/blob/383e19d324f2d3029d1c304752f4d38a9360bb95/src/components/PerfPanel.tsx#L60-L74).

## Latency metrics and honest overall display

Both implementations expose separate network RTT, jitter-buffer delay and decode time. Their jitter label is the average buffer residence time from interval deltas, not raw RTP `jitter`; decode time is interval `totalDecodeTime / framesDecoded`. Better xCloud chooses the transport's selected candidate pair for RTT. XStreaming takes succeeded candidate pairs and applies Android-specific subtraction to decode values over thresholds; that heuristic must not be copied to macOS. Neither inspected HUD computes full input-to-photon latency. [Better xCloud collector 227–301](https://github.com/redphx/better-xcloud/blob/f8397043f6d2148d2345d508902a38c69cf1ee20/src/utils/stream-stats-collector.ts#L227-L301), [XStreaming stats 642–703](https://github.com/Geocld/XStreaming/blob/383e19d324f2d3029d1c304752f4d38a9360bb95/src/webrtc/index.ts#L642-L703).

The WebRTC stats standard defines candidate-pair RTT using STUN, jitter-buffer residence before decoding, and total processing delay from first received packet until decode completion. Processing delay already contains receive-side buffering and decoding, so adding all three double-counts. These fields do not measure game simulation, server encoding, controller transport or display scan-out. [W3C jitter/processing definitions](https://www.w3.org/TR/webrtc-stats/#dom-rtcinboundrtpstreamstats-totalprocessingdelay), [W3C RTT](https://www.w3.org/TR/webrtc-stats/#dom-rtcicecandidatepairstats-currentroundtriptime).

Recommendation (engineering inference): an easy-to-read summary can say `Overall latency (estimate)` only with its scope explicit, e.g. estimated network transit plus receiver processing plus local presentation. RTT/2 assumes symmetric network paths and estimates video one-way transit; RTT instead approximates the two network legs of an input-response path but still excludes remote processing and device/display latency. Do not label either formula measured end-to-end. Keep unknown/stale components unavailable, not zero; use interval averages consistently rather than summing unrelated P95 values. A more defensible interim label is `Network + client estimate`, accompanied by `Input-to-photon not measured`.

## Recommended XFrame experiment

1. Separate raw controller packet counts from the observable management-window state; emit stable connection/input-state changes only to that view. Leave live counters in a narrowly scoped, low-frequency HUD path.
2. Preserve the current bounded video queue during the first experiment so the UI effect is isolated. Compare the same active controller, focused playback, visible/hidden management window and HUD modes over equal windows.
3. Record incoming/output interval FPS, queue skips by reason, draw-callback interval, main-thread layout cost and presentation latency. A low decode/GPU time alone does not prove smooth scheduling.
4. Do not infer an upstream precedent for the identical failure: the sources support separation of rendering and UI updates, but the suspected SwiftUI update storm still requires XFrame A/B evidence.
