# XFrame

A native Xbox streaming client for Apple Silicon Macs, under development.

The current increment connects xCloud sessions to native H.264 video through WebRTC, verified VideoToolbox hardware decoding, and Metal rendering, with receive-only game audio through WebRTC's native output. Local H.264 playback and a fixed 1920 × 1080 test pattern remain available. Rendering uses Aspect Fit, black bars, Retina backing pixels, native full-screen support, and window resizing. Single-controller input and an opt-in keyboard gamepad fallback are implemented. Optional MetalFX Spatial and integer scaling are implemented; console remote play remains pending.

## Requirements

Development priorities and remaining features: [Feature roadmap](.scratch/roadmap/spec.md).

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

Controller input enablement is remembered across app restarts (first launch defaults to off); focus loss still releases game input. The controller toggle stays in the View menu so a controller user cannot disable their own navigation from the playback panel.

For game input, choose **View → Enable Controller Input** or **View → Enable Keyboard Input** (both can be enabled; the last device with a fresh button press or deliberate stick/trigger motion takes control). Keyboard mode maps physical key positions to the Xbox controller: WASD moves, arrows look, J/Space=A, K=B, U=X, I=Y, Q/E=LB/RB, Z/C=LT/RT, F/T/H/G=D-pad, L/O=stick clicks, Return=Menu and Tab=View. **View → Keyboard Controls…** shows the mapping. Only the focused cloud playback window captures game keys; Command/Control/Option shortcuts remain available. Keyboard sticks/triggers are digital, and custom bindings/mouse look are not implemented. See [keyboard validation](.scratch/keyboard-input/validation.md) for the current live acceptance limits.

## Xbox Account

The main library window opens at startup and restores saved sign-in. When cloud access is unavailable, it shows the Microsoft sign-in flow in place. Open account management from the sidebar profile button or **Account → Xbox Account…** (**Shift-Command-A**); it is a sheet in the same window, not a separate account window. Development credential-storage details are collapsed under **Development details**. Video playback retains its dedicated native rendering window.

The rendering window stays hidden until cloud video connects, a local video is opened/replayed, or the test pattern is explicitly requested. Stopping cloud video hides it and returns to the library, where session cleanup status remains visible. Closing local playback stops its decoder and returns to the library. Canceling the local-file picker does not reveal the rendering window.

Library and playback windows independently remember their size and position through AppKit frame autosave. On first launch the library prefers 1240×820 content points; playback prefers 960×540. Frames are constrained to a current screen's visible area on restore and display changes, excluding fullscreen windows. This saves normal window geometry, not an instruction to launch in fullscreen.

1. Choose **Sign In with Microsoft** and open the Microsoft sign-in link.
2. Enter the displayed code in your browser and complete sign-in using a personal Microsoft account with an Xbox profile. Never share the code with anyone else.
3. XFrame exchanges the authorization for Xbox and xCloud credentials, then shows the gamertag, offering, available regions, and credential expiration. This does not yet start a game or prove that every catalog title is playable.

Development builds currently save only the Microsoft refresh token in `~/Library/Application Support/XFrame/Credentials/microsoft-refresh-token`, outside the repository. This is an **unencrypted file**, with an owner-only directory (0700) and file (0600); other processes running as the same user may still read it. Writes use a private temporary file and atomic replacement. Unsafe file ownership/permissions and file symlinks are rejected when reading. Other tokens stay in memory. Startup restores the saved sign-in; **Check Access Again** refreshes it manually. **Sign Out** removes the local token file, but does not sign out your browser or revoke Microsoft's server-side grants. **Cancel** preserves any previously saved sign-in.

The default credential store does not access Keychain, including for migration. Switching from an older build therefore requires one Microsoft sign-in if no local file exists. Old Keychain entries are left untouched, including by Sign Out in this mode. Signing the app may still use a Keychain-backed signing private key; that is separate from login storage. This temporary development exception must be removed before release; see [the migration-back issue](.scratch/keychain-access/issues/01-restore-keychain.md).

This development implementation follows [XStreaming's authentication flow](https://github.com/Geocld/XStreaming/blob/383e19d324f2d3029d1c304752f4d38a9360bb95/src/xal/msal.ts), including its public Microsoft client identifier. It is not an XFrame-owned app registration, and Microsoft's consent screen may identify the public client rather than XFrame. Service compatibility is not guaranteed. No region-spoofing headers are sent. A rejected catalog offering (HTTP 403) triggers a separate free-to-play check, clearly labeled in the UI.

Earlier builds verified real account login and Keychain restoration. File-store tests verify private permissions, refresh-token replacement, fresh-instance restoration, deletion, and rejection of unsafe paths. Real Microsoft login, on-disk owner-only permissions, and automatic file-backed account restoration across both a same-build restart and a changed-binary rebuild have been verified. Automated authentication tests use stubbed services. See [the authentication specification](.scratch/xcloud-auth/spec.md) and [validation record](.scratch/xcloud-auth/validation.md).

## Cloud Games and Sessions

The library defaults to **Playable games**, using the account-specific `hasEntitlement` value from the authenticated cloud title response. **All cloud games** also shows titles marked **No entitlement** or **Access unverified**; their Play button is disabled, including a model-level launch guard. Game Pass and free filters intersect catalog classification with confirmed account access. A missing entitlement field stays unknown, not denied. A `NoEntitlement` launch rejection revokes the cached access flag until the next refresh. Refresh after changing purchases or subscriptions.

**Playable** does not mean **Purchased**: the current response does not establish the source of every grant, so XFrame does not invent an Owned badge or ownership filter. Purchased cloud-supported games with confirmed entitlement are included in Playable games. The Game Pass badge describes catalog membership, not a verified subscription tier. Service-side launch checks remain authoritative.

Open **Account → Cloud Games…** (**Shift-Command-G**), choose **Load Games**, select a game card or list row, and choose **Start Selected Game**. The account's title list is hydrated with English names, optional poster artwork, categories and publisher from Microsoft's public catalog; it may not be exhaustive, and launch eligibility is ultimately checked by the service.

Switch between **Grid** and **List**, search titles, filter by **Category** or **Favorites**, and sort **A–Z** or **Z–A**. Search ignores case/diacritics and matches every whitespace-separated term. Choose 24, 48 or 96 games per page. Pagination is local over the loaded catalog, not separate server requests. Query/page changes clear the old selection so a hidden title cannot be launched accidentally. Missing artwork uses a local placeholder.

Stars save title IDs in device-local preferences across restarts. Favorites are not account-synced and do not establish ownership or subscription eligibility; only favorites present in the current account/region catalog appear. Region changes clear the catalog. The library uses a window-local dark appearance, collection sidebar, adaptive portrait artwork and restrained selection/play accents. Query/metadata logic has automated coverage; real catalog loading, search, category switching and grid/list appearance have been inspected on the development Mac. See [the library specification](.scratch/game-library/spec.md) and [visual validation](.scratch/ui-polish/validation.md).

The **Region** picker defaults to the service-selected region and offers only regions returned for the signed-in account. Choosing a region clears the old catalog; load games again before starting. Selection is locked while loading or owning a session. **Requested region** identifies the chosen service endpoint, not a guaranteed physical streaming location: the service may redirect the session. The selection is kept for the current app run, not saved across restarts. No region spoofing or latency-based automatic selection is performed.

The window distinguishes waiting for resources, provisioning, video negotiation, and streaming. Once provisioned, the native rendering window displays received H.264 video and WebRTC plays received game audio through the default output. Cloud Games and the in-picture Playback Settings panel provide mute and 0–100% volume controls. Volume and mute are saved independently across games and app launches; changing volume while muted leaves mute enabled. Microphone/camera capture remains disabled. For supervised controller testing, enable **View → Enable Controller Input**; input is limited to the focused playback window. Audio packet and energy diagnostics show incoming media, not proof of audible output or A/V synchronization. Choose **End Session**, press **Command-0**, or close the playback window (including **Command-W**) to open an in-picture confirmation with **Cancel** selected. Confirming stops audio/video and starts session cleanup. The playback window shows progress until cleanup succeeds; failure keeps **Retry End Session** available, including controller navigation. Focus loss cancels an unconfirmed request; confirmed cleanup continues. Keep XFrame running until it reports **Session ended**; failed cleanup blocks normal quitting and account changes. Closing the library window alone does not end a stream. Ending fullscreen playback exits native fullscreen before hiding the window; each new playback opens windowed at its saved normal size. Use Control-Command-F to enter fullscreen again.

After stopping, expand **Last stream diagnostics** to inspect the latest 128 numeric/typed events, retained only in memory until the next session, catalog reset or app exit. **Export JSON…** saves a user-selected report containing allowlisted counters and events, without account identity, game title, credentials, session URLs, SDP, addresses or media. Exported files persist until you remove them; nothing is uploaded automatically. The report's outcome describes the local video pipeline, not confirmation of remote session deletion. The overlay distinguishes actual decode errors from frames skipped while waiting for a recovery keyframe, and shows sampled video RTP loss and NACK counts. Unavailable network counters display `n/a`; a zero decoder missing-frame hint does not prove zero network loss.

For repeatable, non-interactive regression checks, run `bash scripts/check-headless.sh 3` after generating the local fixtures. It runs three serial full-suite rounds and a release build, preserves logs under `.build/headless-checks/`, stops on failure, and never launches the app or changes power settings. This verifies code while a display is unavailable; it does not replace visual, audio or controller acceptance.

Physical controller integration is available for supervised acceptance; full playable-client acceptance remains pending. The stream keeps one latest decoded frame and uses the existing zero-pixel-copy Metal surface import. Startup without video and prolonged frame stalls trigger cleanup. Crash/force-quit recovery, reconnect, TURN fallback, and renewal of credentials during long sessions are deferred. A failed creation request without a returned session address can have an uncertain server outcome, which is reported explicitly. See [the session specification](.scratch/cloud-sessions/spec.md) and [video specification](.scratch/cloud-video/spec.md).

## Diagnostics and Offline Groundwork

Playback diagnostics now include bounded recent p95 timings for decode submission-to-callback, decoded-frame waiting, GPU execution and receipt-to-presentation. JSON stream reports use schema version 6 and retain at most 256 samples per stage. Live playback keeps up to two decoded frames to absorb short delivery bursts. At consumption it catches up to a fresher ready frame when the head is older than 25 ms (1.5 intervals at 60 Hz), and discards frames older than 50 ms after stalls. Detailed HUD labels skipped frames as cumulative and separates inbox loss, renderer replacement, busy ticks, unavailable drawables and drawable callbacks that were not actually displayed; reports include bounded arrival/draw/drawable-wait timing distributions. Missing GPU/display timestamps remain `n/a`; these overlapping local intervals are not network or controller-to-photon latency. See [timing definitions and regression results](.scratch/playback-performance/validation.md).

Open **Streaming Settings** in the cloud library sidebar to select **Standard** or **HQ (experimental)** and a **Game language** (including 简体中文 and 繁體中文). Settings save automatically and apply to newly started sessions. For an active game, use **End Session**, then start it again; changing settings does not alter the current session. Standard preserves the existing client profile. HQ requests the XStreaming-style higher-quality profile, with automatic bitrate negotiation; actual resolution/bitrate depend on the service, subscription and title. Check the Detailed HUD for received resolution and Mbps. Game-language support depends on the title; app and catalog language remain English. A numerical custom bitrate override is not implemented.

The performance overlay defaults to **Compact**. **Command-Shift-D** cycles Compact → Detailed → Hidden; **View → Performance Overlay** selects a preset directly. The choice persists across app launches. The panel uses a 28% black background and lets mouse clicks pass through. In cloud playback, press **View + Menu together** on an enabled controller to open **Playback Settings**, which includes HUD choices and all three scaling modes; both buttons must start within 300 ms. Release the chord before navigating. Standalone View/Menu still reach the game after the short recognition window; quick taps retain their press/release. Chords are local and work only while playback owns input. While focused controller input is enabled, XFrame requests direct View/Menu input without macOS capture gestures; the previous per-button preferences are restored on focus loss, disable, controller replacement and shutdown.

**VIDEO Mbps** is measured incoming video RTP payload throughput over the latest statistics interval (about one second), not a requested limit or total audio/network bandwidth. Initial/missing/reset/stale samples display `n/a`. STREAM/OUT FPS are stream decode/presentation averages, not independently measured game FPS; 60 video frames can contain repeated game images. Detailed mode explicitly marks game FPS as unmeasured. Game startup language and HQ preferences are available in Streaming Settings; see the [profile research](.scratch/stream-settings/xstream-research.md).

The library caches derived query results, supports page-local arrow selection, and provides **Reload Artwork** in a card's context menu. The underlying model has automated coverage; keyboard focus and real failed-image retry still need supervised UI acceptance.

Controller input now connects one physical GameController extended gamepad to the cloud input channel. **Xbox One over Bluetooth is tested and accepted in Palworld; PS4 / DualShock 4 and other controller models are not tested.** Enable **View → Enable Controller Input** for the current app run, focus the playback window and release all controls before playing. Buttons, D-pad, Menu/View, stick clicks, sticks and triggers are mapped; Home is mapped when the OS exposes it. The overlay reports discovery, focus, release gating and packets accepted by the local transport (not host acknowledgements). Losing focus, disabling input or disconnecting clears queued input and sends neutral. Reconnect/focus reacquisition requires returning controls to neutral. A bounded queue retains button/trigger edges and coalesces continuous analog motion. Persistent input transport backpressure terminates the session through normal cleanup. Rumble is not implemented. See [the input boundary and hardware checklist](.scratch/controller-input/spec.md).

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

**Right-click the playback picture** to open **Playback Settings** without leaving fullscreen. Choose a scaling mode, HUD preset, or Enter/Exit Fullscreen. During cloud playback, the panel also provides volume, mute, and End Session. With controller input enabled during cloud playback, **View + Menu** opens the same panel; use **D-pad ↑/↓**, **A** to apply and **B** to close. On the volume row, **←/→** adjusts by 5 percentage points; holding repeats. Keyboard arrows, **Return** and **Esc** also work, and the mouse can drag the volume slider. Fullscreen switching keeps the panel open and the same row selected. Right-click again, click the surrounding picture, or choose Close to dismiss. Video/audio continue, but game input is released and locally intercepted while the panel is open; the remote game is not paused. Release held controls before resuming gameplay. Ordinary settings and unconfirmed termination close on focus loss; confirmed termination progress and cleanup failure remain until resolved. See [validation](.scratch/playback-settings/validation.md) for the remaining new-build physical-controller and live acceptance checks.

**View → Video Scaling** switches immediately between **Original**, **Integer Scaling**, and **MetalFX Spatial**, including during an active stream. The selection persists across launches and applies to cloud video, local video, and the test pattern. Original (bilinear Aspect Fit) is the first-launch default.

Integer Scaling uses nearest-neighbor pixel replication only in fullscreen when the fitted picture is an exact integer enlargement (1080p → 3840×2160 is 2×). Windowed/noninteger output temporarily uses Original; returning to eligible fullscreen automatically restores Integer Scaling. It does not force extra borders to fit a smaller integer image.

MetalFX Spatial follows the actual Aspect Fit picture area in backing pixels, preserving black bars. It bypasses when no enlargement is needed, the GPU is unsupported, or scaler initialization fails. The HUD reports the effective mode, source/output dimensions and any bypass reason. It does not change the received stream resolution. Spatial processing uses the current frame only; additional sharpening, frame interpolation and neural enhancement are deferred.

The Detailed HUD reports **MetalFX GPU span** mean/p95 separately from whole-frame GPU and actual presentation timings. This timestamp interval runs from source-color conversion completion to final composition's fragment start, including MetalFX and inter-pass scheduling; it is not pure kernel time or added input latency. Missing counters remain `n/a`. Scaler samples reset on mode/extent changes; other timings retain their recent 256-sample windows, so allow a warm-up interval before comparison. Static patterns have no video timing stream. Schema-8 diagnostic reports include the selected/effective mode, extents, bypass reason and scaler timing. See [implementation validation](.scratch/4k-post-processing/spatial-validation.md) for measured results and remaining acceptance.

## Implementation

- `XFrameApp.swift`: native AppKit lifecycle, menus, window, and Metal view backing-size updates.
- `MetalRenderer.swift`: Metal pipeline and centered Aspect Fit viewport in actual drawable pixels.
- `TestPattern.swift`: one-time test image generation and texture upload.
- `Shaders.metal`: bilinear and nearest-neighbor sampling with SDR NV12 conversion.
- `VideoScaling.swift` / `SpatialUpscaler.swift`: scaling policy, native MetalFX resources and GPU timestamp sampling.
- `LocalVideo.swift`: compressed file reading, hardware decoding, bounded frame queue, playback clock, and counters.
- `Auth/`: device-code authentication, Xbox/xCloud exchanges, temporary private-file storage, retained legacy Keychain implementation, and account UI.
- `Cloud/`: authenticated title discovery, public title metadata, session ownership/cleanup, and searchable game UI.
- `Streaming/`: SDP/ICE exchange, WebRTC control handshake, hardware H.264 decoder, and the bounded two-frame live display source.

The static view redraws on invalidation. Video playback uses MTKView display callbacks and pauses its drawing loop after EOF or failure. CPU drawing is used only to create the static fixture once. Adaptive streaming frame pacing belongs to a later increment.

See [the first-slice specification](.scratch/native-rendering/spec.md) and [the full requirements](xframe_requirement.md).

The HUD refreshes at most once per second; hidden mode skips text formatting and layout. Controller packet counters stay out of the observable library status so input traffic does not repeatedly invalidate the game library. SQ/HQ describes the active session’s requested profile, separately from received resolution. `Latency est.` adds network RTT, interval-average receiver buffering, local decode mean and post-decode presentation mean; host processing and input/display hardware are not measured, so this is not measured input-to-photon latency. Missing or stale components remain unavailable. Window titles distinguish logical `View … pt` from Retina drawable `Canvas … px`; neither is the incoming stream resolution.

Presentation callbacks with zero/invalid display timestamps no longer inflate OUT. The detailed HUD and schema-6 report also separate same-frame queue-to-submit, GPU queue, GPU execution and GPU-complete-to-display intervals; the end-to-end local presentation interval contains all four and must not be added to them again. GPU/display callbacks can arrive in either order. Counter/timing work is bounded; summaries remain 1 Hz. The [latency investigation](.scratch/playback-performance/issues/02-local-presentation-latency.md) records measured experiments, rejected display drivers and remaining acceptance.

Frame pacing is selectable in Streaming Settings and saved for the next session. Balanced (default) retains two-frame jitter buffering; Low latency (experimental) retains only the newest waiting decoded frame, with the same 50 ms stale limit and display synchronization. It may skip more frames and does not guarantee lower latency. Detailed HUD and schema-6 JSON reports include the active pacing mode.
