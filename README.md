# XFrame

A native Xbox streaming client for Apple Silicon Macs, under development.

The current increment connects xCloud sessions to native H.264 video through WebRTC, verified VideoToolbox hardware decoding, and Metal rendering, with receive-only game audio through WebRTC's native output. Local H.264 playback and a fixed 1920 × 1080 test pattern remain available. Rendering uses Aspect Fit, black bars, Retina backing pixels, native full-screen support, and window resizing. Console remote play, controller input, and MetalFX are not implemented yet.

## Requirements

- An Apple Silicon Mac running macOS 27 or later.
- Swift 6.4 and the macOS 27 SDK (Command Line Tools or Xcode).

## Build and Run

```sh
bash scripts/build-app.sh
open .build/XFrame.app
```

The script builds a release executable, bundles its shader resource and the pinned WebRTC 153.0.0 framework, and signs both framework and app. The first build requires network access to fetch the checksummed SwiftPM binary dependency. This is a development app, not a notarized distribution build.

For stable local signing, run the following **only if you want to create/import a local signing certificate into your login Keychain** (requires OpenSSL 3):

```sh
bash scripts/setup-development-signing.sh
```

This creates `XFrame Local Development`, does not change system trust, and does not store private key material in the repo. Builds automatically use it when present. Set `XFRAME_SIGNING_IDENTITY` to select another certificate-backed identity. Otherwise the build warns and falls back to ad-hoc signing, which changes the application's Keychain identity after code changes. Moving from an ad-hoc build to the certificate may require a new Always Allow approval. Do not allow all applications to read your stored login just to suppress prompts.

Known limitation: the self-signed certificate stabilizes the designated requirement, but the legacy Keychain partition restriction remains tied to the binary's code directory hash. Changed builds can therefore prompt again despite Always Allow. It is not a complete repeated-authorization fix. See [the diagnosis](.scratch/keychain-access/diagnosis.md).

The script explicitly selects SwiftPM's native build engine because the default `swiftbuild` engine fails to initialize with the standalone Command Line Tools on the development machine. That engine is deprecated; revisit this workaround with future toolchain updates.

Use **View → Toggle Full Screen** or **Control-Command-F** to toggle native full-screen mode. Closing all windows quits the app.

## Xbox Account

The account window opens at startup. Reopen it with **Account → Xbox Account…** or **Shift-Command-A**.

1. Choose **Sign In with Microsoft** and open the Microsoft sign-in link.
2. Enter the displayed code in your browser and complete sign-in using a personal Microsoft account with an Xbox profile. Never share the code with anyone else.
3. XFrame exchanges the authorization for Xbox and xCloud credentials, then shows the gamertag, offering, available regions, and credential expiration. This does not yet start a game or prove that every catalog title is playable.

Development builds currently save only the Microsoft refresh token in `~/Library/Application Support/XFrame/Credentials/microsoft-refresh-token`, outside the repository. This is an **unencrypted file**, with an owner-only directory (0700) and file (0600); other processes running as the same user may still read it. Writes use a private temporary file and atomic replacement. Unsafe file ownership/permissions and file symlinks are rejected when reading. Other tokens stay in memory. Startup restores the saved sign-in; **Check Access Again** refreshes it manually. **Sign Out** removes the local token file, but does not sign out your browser or revoke Microsoft's server-side grants. **Cancel** preserves any previously saved sign-in.

The default credential store does not access Keychain, including for migration. Switching from an older build therefore requires one Microsoft sign-in if no local file exists. Old Keychain entries are left untouched, including by Sign Out in this mode. Signing the app may still use a Keychain-backed signing private key; that is separate from login storage. This temporary development exception must be removed before release; see [the migration-back issue](.scratch/keychain-access/issues/01-restore-keychain.md).

This development implementation follows [XStreaming's authentication flow](https://github.com/Geocld/XStreaming/blob/383e19d324f2d3029d1c304752f4d38a9360bb95/src/xal/msal.ts), including its public Microsoft client identifier. It is not an XFrame-owned app registration, and Microsoft's consent screen may identify the public client rather than XFrame. Service compatibility is not guaranteed. No region-spoofing headers are sent. A rejected catalog offering (HTTP 403) triggers a separate free-to-play check, clearly labeled in the UI.

Earlier builds verified real account login and Keychain restoration. File-store tests verify private permissions, refresh-token replacement, fresh-instance restoration, deletion, and rejection of unsafe paths. Real Microsoft login, on-disk owner-only permissions, and automatic file-backed account restoration across both a same-build restart and a changed-binary rebuild have been verified. Automated authentication tests use stubbed services. See [the authentication specification](.scratch/xcloud-auth/spec.md) and [validation record](.scratch/xcloud-auth/validation.md).

## Cloud Games and Sessions

Open **Account → Cloud Games…** (**Shift-Command-G**), choose **Load Games**, select a game card or list row, and choose **Start Selected Game**. The account's title list is hydrated with English names, optional poster artwork, categories and publisher from Microsoft's public catalog; it may not be exhaustive, and launch eligibility is ultimately checked by the service.

Switch between **Grid** and **List**, search titles, filter by **Category** or **Favorites**, and sort **A–Z** or **Z–A**. Search ignores case/diacritics and matches every whitespace-separated term. Choose 24, 48 or 96 games per page. Pagination is local over the loaded catalog, not separate server requests. Query/page changes clear the old selection so a hidden title cannot be launched accidentally. Missing artwork uses a local placeholder.

Stars save title IDs in device-local preferences across restarts. Favorites are not account-synced and do not establish ownership or subscription eligibility; only favorites present in the current account/region catalog appear. Region changes clear the catalog. The library uses a window-local dark appearance, collection sidebar, adaptive portrait artwork and restrained selection/play accents. Query/metadata logic has automated coverage; real catalog loading, search, category switching and grid/list appearance have been inspected on the development Mac. See [the library specification](.scratch/game-library/spec.md) and [visual validation](.scratch/ui-polish/validation.md).

The **Region** picker defaults to the service-selected region and offers only regions returned for the signed-in account. Choosing a region clears the old catalog; load games again before starting. Selection is locked while loading or owning a session. **Requested region** identifies the chosen service endpoint, not a guaranteed physical streaming location: the service may redirect the session. The selection is kept for the current app run, not saved across restarts. No region spoofing or latency-based automatic selection is performed.

The window distinguishes waiting for resources, provisioning, video negotiation, and streaming. Once provisioned, the native rendering window displays received H.264 video and WebRTC plays received game audio through the default output. Cloud Games provides mute and 0–100% volume controls; preferences are retained in memory across sessions, independently of mute. Microphone/camera capture and controller input remain disabled. Audio packet and energy diagnostics show incoming media, not proof of audible output or A/V synchronization. Choose **End Session**, press **Command-0**, or close the rendering window to stop audio/video and release the session. Keep XFrame running until it reports **Session ended**; failed cleanup retains a retry button and blocks normal quitting and account changes. Closing the library window alone does not end a stream.

After stopping, expand **Last stream diagnostics** to inspect the latest 128 numeric/typed events, retained only in memory until the next session, catalog reset or app exit. **Export JSON…** saves a user-selected report containing allowlisted counters and events, without account identity, game title, credentials, session URLs, SDP, addresses or media. Exported files persist until you remove them; nothing is uploaded automatically. The report's outcome describes the local video pipeline, not confirmation of remote session deletion. The overlay distinguishes actual decode errors from frames skipped while waiting for a recovery keyframe, and shows sampled video RTP loss and NACK counts. Unavailable network counters display `n/a`; a zero decoder missing-frame hint does not prove zero network loss.

For repeatable, non-interactive regression checks, run `bash scripts/check-headless.sh 3` after generating the local fixtures. It runs three serial full-suite rounds and a release build, preserves logs under `.build/headless-checks/`, stops on failure, and never launches the app or changes power settings. This verifies code while a display is unavailable; it does not replace visual, audio or controller acceptance.

This is a supervised video-preview increment, not a playable client. The stream keeps one latest decoded frame and uses the existing zero-pixel-copy Metal surface import. Startup without video and prolonged frame stalls trigger cleanup. Crash/force-quit recovery, reconnect, TURN fallback, and renewal of credentials during long sessions are deferred. A failed creation request without a returned session address can have an uncertain server outcome, which is reported explicitly. See [the session specification](.scratch/cloud-sessions/spec.md) and [video specification](.scratch/cloud-video/spec.md).

## Diagnostics and Offline Groundwork

Playback diagnostics now include bounded recent p95 timings for decode submission-to-callback, decoded-frame waiting, GPU execution and receipt-to-presentation. JSON stream reports use schema version 2 and retain at most 256 samples per stage. Missing GPU/display timestamps remain `n/a`; these overlapping local intervals are not network or controller-to-photon latency. See [timing definitions and regression results](.scratch/playback-performance/validation.md).

The library caches derived query results, supports page-local arrow selection, and provides **Reload Artwork** in a card's context menu. The underlying model has automated coverage; keyboard focus and real failed-image retry still need supervised UI acceptance.

Controller groundwork is available as a pure, reference-tested packet encoder, but is deliberately not wired to GameController or the live input channel. Microphone and controller input therefore remain disabled. See [the input boundary and hardware checklist](.scratch/controller-input/spec.md).

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

Open `.build/fixtures/h264-1080p60.mp4` in XFrame to exercise a 12-second, 720-frame 1080p60 fixture with B frames. The fixture script also produces an Annex B `.h264` file for the WebRTC decoder adapter. Hardware integration checks require Apple Silicon and verify frame coverage and order, IOSurface/NV12 output, bounded buffering, cancellation, and visible failure state.

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
- `Auth/`: device-code authentication, Xbox/xCloud exchanges, temporary private-file storage, retained legacy Keychain implementation, and account UI.
- `Cloud/`: authenticated title discovery, public title metadata, session ownership/cleanup, and searchable game UI.
- `Streaming/`: SDP/ICE exchange, WebRTC control handshake, hardware H.264 decoder, and the single-frame live display source.

The static view redraws on invalidation. Video playback uses MTKView display callbacks and pauses its drawing loop after EOF or failure. CPU drawing is used only to create the static fixture once. Adaptive streaming frame pacing belongs to a later increment.

See [the first-slice specification](.scratch/native-rendering/spec.md) and [the full requirements](xframe_requirement.md).
