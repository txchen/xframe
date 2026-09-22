# Performance HUD validation — 2026-09-22

## Automated checks

- `bash scripts/test.sh`: 80 tests passed (`.build/performance-hud-tests.log`).
- Six new tests cover native microsecond bitrate math, first/missing/reset/new-source/out-of-order counters, actual zero vs unavailable, LiveVideo/report propagation and terminal freeze, nonfinite export sanitization, preset cycling/labels, local controller chord suppression, standalone quick taps/holds and reset behavior.
- `bash scripts/build-app.sh`: release build, development signing and strict signature verification passed (`.build/performance-hud-build.log`).
- `git diff --check` passed.

## Behavior

- Default Compact; Command-Shift-D cycles Compact → Detailed → Hidden. Explicit choices are available under View > Performance Overlay and persist in local preferences.
- Panel background is 28% black (previously 80%), with text shadow and click-through hit testing. Compact uses two lines.
- The video bitrate meter uses inbound video RTP bytesReceived delta divided by native WebRTC timestamp_us delta; it resets with each session/report identity and rejects invalid deltas. Live values older than three seconds are unavailable. Audio/packet headers/total traffic and requested bitrate are not included.
- Diagnostic JSON schema 3 adds optional video.bitrateMbps to the existing numeric allowlist.
- View+Menu within 300 ms cycles locally and suppresses these two buttons until both are released. Standalone presses are delayed briefly for recognition; quick taps preserve press/release. The shortcut is disabled without playback input ownership and requires the existing neutral rearm after focus/device changes.

## Native acceptance

The signed build was launched and a Palworld session started. Compact displayed two lines over a translucent background with measured video rate samples 14.3–14.6 Mbps. Command-Shift-D was exercised through Detailed → Hidden → Compact: detailed text included the measured rate and game-FPS disclaimer; hidden removed the AX text and all visible overlay content; compact restored correctly. View menu exposed the cycle action and three explicit presets. Screenshots confirmed the smaller translucent panel preserves visible game content beneath it. Mouse click-through is implemented via the HUD hitTest override; a physical click-through check and relaunch-persistence UI check were not separately exercised.

Physical Xbox View+Menu cycling was subsequently accepted by the user; see the final acceptance below. No HQ request or game-language change was made during this HUD pass. Current stream throughput is observed baseline, not a guaranteed minimum/maximum or HQ comparison.

## View/Menu follow-up

User reported intermittent cycling and a recording confirmation dialog. Read-only physical capture (`diagnostics/main.swift`, `.build/hud-chord-probe.log`) confirmed both button mappings and multiple recognized chords. Two overlapping presses were separated by 128 ms, outside the initial 120 ms recognition window. The captured 24.957/25.085-second sequence was replayed in `gamepadHUDChordAcceptsCapturedXboxButtonStagger`; before the fix it failed both cycling and local-suppression assertions.

Recognition now allows 300 ms; individual holds still become normal game input after that delay. NativeGamepad requests `.disabled` system gestures on Menu/Options while focused input is enabled and restores exact previous preferences on focus loss, disable, device replacement and stop. Apple's local GCControllerElement.h documents that system gestures can delay or suppress Options events and specifically recommends this preference for remote gaming. The OS may decline this preference, so automated preference tests alone cannot prove the absence of recording dialogs.

82 tests passed (`.build/hud-chord-fix-tests.log`), including the captured timing regression and preference acquisition/restoration. At build time, physical acceptance was pending; it was subsequently supplied below. The read-only capture process has been stopped.

Release build and strict signature verification passed (`.build/hud-chord-fix-build.log`). User saved and ended the old session; the rebuilt app was restarted and a fresh Palworld session launched.

## Final Xbox One acceptance — 2026-09-22

After restarting the rebuilt app and launching Palworld, the user repeated the View+Menu test and reported: “这次正常了, 每次都能顺利切换” (“Normal this time; every attempt switches successfully”). Repeated physical HUD cycling is accepted. The test prompt also requested no recording/game-menu popups and standalone View/Menu checks; the reply gave an overall normal result without separately enumerating those checks. PS4 / DualShock 4 and other controller models remain untested.

## Recent FPS correction

121 tests pass (`.build/rolling-fps-tests.log`), including a 100-second 30 fps history followed by 60 fps, two-second convergence, stop-to-zero, recovery and fresh source warmup. Signed build: `.build/rolling-fps-build.log`. Live check passed in the signed app: recent rates labelled `2s` and separate `SESSION avg`; captured both a 30 fps and a 60 fps fresh cloud session. A 30-to-60 transition is verified by the deterministic meter test, not inferred from those separate live sessions.
