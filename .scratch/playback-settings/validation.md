# Playback settings validation

Date: 2026-09-22.

## Implemented

Right-click toggles an overlay inside the playback window. It exposes the three scaling modes and three performance-HUD presets, with immediate application and existing preference persistence. The selected row and active setting have separate arrow/checkmark indicators. A scroll view bounds the panel in small windows.

The user approved replacing View + Menu's previous HUD-cycle action with opening this panel. D-pad up/down selects, A applies, B closes; the opening chord must be released first. Standalone View/Menu behavior retains the existing 300 ms recognition and tap forwarding. Command-Shift-D still cycles HUD directly.

Opening and closing release the cloud input scheduler and clear pending game actions. While open, controller states are routed locally and gameplay receives neutral state. Ordinary keyboard input is consumed locally; app/system modifier shortcuts remain available. Closing uses the existing neutral-before-rearm gate. Focus loss, session source replacement and playback hiding close the panel. Video/audio continue; the remote game is not paused.

## Verification

- Full suite: 132 tests passed, including view callbacks and a title-visibility layout regression; log `.build/playback-settings-tests.log`.
- Focused checks include chord release gating, preservation of standalone button taps/holds, menu navigation edges, neutral rearm, and direct view keyboard callbacks; log `.build/playback-settings-focused.log`.
- Signed release build succeeded and passed deep/strict signature verification; log `.build/playback-settings-build.log`.
- User explicitly approved ending the active session and restarting. Ended the session through the library and relaunched the signed app.
- Native right-click opening and mouse scaling selection verified. Found and fixed title clipping by replacing manual stack sizing with Auto Layout document width and content insets. Regression failed before the fix and passed afterward; actual screenshot confirms the complete title and controls.
- Keyboard Up/Return selected Integer Scaling, Escape closed the panel. Entering fullscreen produced 1920×1080 → 3840×2160 Integer Scaling. Right-click panel layout verified in 4K fullscreen; returning to a window showed Original with the fullscreen-required reason while retaining Integer Scaling selection.

## Pending device acceptance

Still pending: small-window scrolling; physical View + Menu and D-pad/A/B; game-input isolation and post-dismissal rearm during a real session. Unit tests do not establish physical-controller acceptance. These observations apply to the panel build tested above, not a claim about the current live session.

## Controller preference follow-up

User requested persistent controller enablement and explicitly rejected an input toggle inside the controller-operated panel. Added preference restoration and initial View-menu checkmark synchronization; existing focus-loss release and neutral rearm remain. A regression verifies enable and disable across library recreation and verifies focus is never restored. The existing keyboard/controller coexistence test now uses isolated preferences.

Full suite: 133 tests passed (`.build/controller-persistence-tests.log`). Signed app build and strict/deep verification passed (`.build/controller-persistence-build.log`). The currently playing game was not interrupted to install this follow-up in the running process; it takes effect on the next app launch.
