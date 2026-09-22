# XFrame

A native Xbox streaming client for Apple Silicon Macs, under development.

The current increment adds Microsoft device-code sign-in and an xCloud credential check. Local H.264 playback uses verified VideoToolbox hardware decoding and Metal rendering, alongside a fixed 1920 × 1080 test pattern. Both rendering paths use Aspect Fit, black bars, Retina backing pixels, native full-screen support, and window resizing. Actual cloud streaming, console connections, audio, and MetalFX are not implemented yet.

## Requirements

- An Apple Silicon Mac running macOS 27 or later.
- Swift 6.4 and the macOS 27 SDK (Command Line Tools or Xcode).

## Build and Run

```sh
bash scripts/build-app.sh
open .build/XFrame.app
```

The script builds a release executable, bundles its shader resource, and applies a local ad-hoc signature. This is a development app, not a notarized distribution build. No external dependencies are required.

The script explicitly selects SwiftPM's native build engine because the default `swiftbuild` engine fails to initialize with the standalone Command Line Tools on the development machine. That engine is deprecated; revisit this workaround with future toolchain updates.

Use **View → Toggle Full Screen** or **Control-Command-F** to toggle native full-screen mode. Closing all windows quits the app.

## Xbox Account

The account window opens at startup. Reopen it with **Account → Xbox Account…** or **Shift-Command-A**.

1. Choose **Sign In with Microsoft** and open the Microsoft sign-in link.
2. Enter the displayed code in your browser and complete sign-in using a personal Microsoft account with an Xbox profile. Never share the code with anyone else.
3. XFrame exchanges the authorization for Xbox and xCloud credentials, then shows the gamertag, offering, available regions, and credential expiration. This does not yet start a game or prove that every catalog title is playable.

Only the Microsoft refresh token is saved in macOS Keychain, without iCloud synchronization. Other tokens stay in memory. Startup restores the saved sign-in; **Check Access Again** refreshes it manually. **Sign Out** cancels pending requests and removes XFrame's saved sign-in, but does not sign out your browser or revoke Microsoft's server-side grants. **Cancel** preserves any previously saved sign-in.

This development implementation follows [XStreaming's authentication flow](https://github.com/Geocld/XStreaming/blob/383e19d324f2d3029d1c304752f4d38a9360bb95/src/xal/msal.ts), including its public Microsoft client identifier. It is not an XFrame-owned app registration, and Microsoft's consent screen may identify the public client rather than XFrame. Service compatibility is not guaranteed. No region-spoofing headers are sent. A rejected catalog offering (HTTP 403) triggers a separate free-to-play check, clearly labeled in the UI.

Real account login and Keychain restoration across a confirmed full process restart have been verified on the development Mac. Automated authentication tests use stubbed services. See [the authentication specification](.scratch/xcloud-auth/spec.md) and [validation record](.scratch/xcloud-auth/validation.md).

## Cloud Games and Sessions

Open **Account → Cloud Games…** (**Shift-Command-G**), choose **Load Games**, search, select a game, and choose **Start Session**. The account's title list is hydrated with English names from Microsoft's public catalog; it may not be exhaustive, and launch eligibility is ultimately checked by the service.

The window distinguishes waiting for resources, provisioning, and a provisioned session with configuration available. It does not connect WebRTC or display game audio/video. Choose **End Session** to cancel startup or release the session. Ready test sessions automatically end after 60 seconds. Keep XFrame running until it reports **Session ended**; failed cleanup retains a retry button and blocks normal quitting and account changes. Closing a window is not the same as ending a session.

This is a supervised session-lifecycle increment, not a playable client. Crash/force-quit recovery and renewal of credentials during a session are deferred. A failed creation request without a returned session address can have an uncertain server outcome, which is reported explicitly. See [the session specification](.scratch/cloud-sessions/spec.md).

## Local Video

- **Command-O**: open an H.264 MP4 or MOV file.
- **Command-R**: replay the last selected file from the beginning.
- **Command-0**: stop playback and return to the test pattern.

This increment supports SDR BT.601/BT.709, square-pixel, unrotated H.264 video. Unsupported codecs, HDR, rotation, cropped clean apertures, and decoder failures appear in the diagnostics overlay. Files containing audio play silently. Seeking and pause are deferred.

The overlay reports hardware decoder verification, average decoded and actually presented video FPS, skipped decoded frames, and queue occupancy. FPS is averaged over the current playback, rather than sampled over a rolling window. Presentation callbacks count video frames once, even when the display refreshes faster than the video.

Compressed samples are read with AVAssetReader, decoded with an explicitly required hardware VTDecompressionSession, and imported as NV12 Metal textures through CVMetalTextureCache. YCbCr conversion runs on the GPU; the playback path does not lock or copy pixel data on the CPU. CoreVideo surfaces and texture wrappers remain retained until GPU completion.

The local-file producer uses a maximum 16-frame sorted lookahead for H.264 B-frame ordering and blocks when full. A decode-timestamp watermark prevents reference frames from overtaking pending B frames after display stalls. Files with presentation timestamps earlier than their decode timestamps are rejected in this increment. Metal submissions are capped at three. This is bounded local-file read-ahead, not the shallow adaptive queue planned for live streaming. Display callbacks select frames using presentation timestamps, with up to half a source-frame interval of tolerance (capped at 16.67 ms), and skip stale frames if playback falls behind.

## Generate a Fixture and Run Checks

FFmpeg is only needed to generate the test fixture, not to build or run XFrame.

```sh
bash scripts/make-test-video.sh
bash scripts/test.sh
```

Open `.build/fixtures/h264-1080p60.mp4` in XFrame to exercise a 12-second, 720-frame 1080p60 fixture with B frames. The hardware integration checks require Apple Silicon and verify frame coverage and order, IOSurface/NV12 output, bounded buffering, cancellation, and visible failure state.

## Visual Acceptance Check

1. Launch the app. Confirm that TOP is at the top, text is upright, both circles are circular, and all four orange corner markers are visible.
2. Resize to a tall window. Expect black bars above and below the complete image.
3. Resize to a wide window. Expect black bars to the left and right.
4. Enter and exit full-screen mode. Confirm that the complete image and its proportions are preserved.
5. If another display is available, move the window between displays with different scale factors. Confirm that the drawable updates and that the image remains correctly fitted.

The fixed source image is scaled using bilinear filtering. Enlarging it does not add image detail. This increment verifies geometry and drawable sizing, not enhanced upscaling quality.

## Implementation

- `XFrameApp.swift`: native AppKit lifecycle, menus, window, and Metal view backing-size updates.
- `MetalRenderer.swift`: Metal pipeline and centered Aspect Fit viewport in actual drawable pixels.
- `TestPattern.swift`: one-time test image generation and texture upload.
- `Shaders.metal`: textured quad with bilinear sampling.
- `LocalVideo.swift`: compressed file reading, hardware decoding, bounded frame queue, playback clock, and counters.
- `Auth/`: device-code authentication, Xbox/xCloud exchanges, Keychain storage, and account UI.
- `Cloud/`: authenticated title discovery, public title metadata, session ownership/cleanup, and searchable game UI.

The static view redraws on invalidation. Video playback uses MTKView display callbacks and pauses its drawing loop after EOF or failure. CPU drawing is used only to create the static fixture once. Adaptive streaming frame pacing belongs to a later increment.

See [the first-slice specification](.scratch/native-rendering/spec.md) and [the full requirements](xframe_requirement.md).
