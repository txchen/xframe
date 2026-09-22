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

## Original panel acceptance handoff (historical)

Still pending: small-window scrolling; physical View + Menu and D-pad/A/B; game-input isolation and post-dismissal rearm during a real session. Unit tests do not establish physical-controller acceptance. These observations apply to the panel build tested above, not a claim about the current live session.

## Controller preference follow-up

User requested persistent controller enablement and explicitly rejected an input toggle inside the controller-operated panel. Added preference restoration and initial View-menu checkmark synchronization; existing focus-loss release and neutral rearm remain. A regression verifies enable and disable across library recreation and verifies focus is never restored. The existing keyboard/controller coexistence test now uses isolated preferences.

Full suite: 133 tests passed (`.build/controller-persistence-tests.log`). Signed app build and strict/deep verification passed (`.build/controller-persistence-build.log`). The currently playing game was not interrupted to install this follow-up in the running process; it takes effect on the next app launch.


## P1 controls extension — 2026-09-22

Implemented the approved grill-with-docs decisions:

- Cloud-only volume and mute controls, independent application-wide persistence, 5-percentage-point horizontal steps, bounded controller hold repeat (400 ms initial delay, 100 ms repeat), and a mouse slider. Adjusting volume does not unmute.
- Enter/Exit Fullscreen remains inside the panel, preserves the selected row, and disables repeated activation during native transitions. Existing windowed session-start behavior is retained.
- Panel End Session, playback close/Command-W, library End Session, and the existing Command-0 cloud-stop shortcut route through a default-Cancel confirmation.
- Confirmed termination releases media/input immediately and keeps progress in the playback surface until cleanup succeeds. Failure keeps controller-accessible Retry End Session. Duplicate requests are suppressed at the library boundary.
- Confirmation is dismissed on focus loss; confirmed termination and failure state survive. An unknown allocation after a failed creation remains reported as unconfirmed in the library, never as successful cleanup.
- Panel controller navigation polls locally without replacing streaming controller handlers, so it remains available after transport/media teardown. Focus and controller opt-in still gate local navigation.
- Local video/test pattern hide cloud audio and termination controls. Input-toggle placement and streaming preferences retain their agreed scope.

### Automated/build evidence

- Full suite: **141 tests passed**, `.build/p1-controls-tests.log`.
- After the final small-window label-width adjustment, **12 focused tests passed**, `.build/p1-controls-focused.log`.
- Coverage includes repeat timing and confirmation edges, volume bounds/mute independence, preference restoration, fullscreen selection/transition gating, local-source control visibility, small-panel scroll-to-selection geometry, delayed service cleanup, duplicate termination suppression, and failed-cleanup retry.
- Release app: `.build/XFrame.app`; build plus deep/strict signature verification passed, `.build/p1-controls-build.log`.
- `git diff --check` passed.

### Pre-acceptance handoff (historical)

The running application was observed streaming a real cloud session during this work. It was not deliberately ended or restarted to activate the new build. Automated AppKit checks are not native interactive or physical-controller acceptance.

On the next safe launch of the built app, verify:

1. Controller View+Menu opens settings; D-pad/A/B, volume hold repeat, mute, and neutral-before-rearm work in a real game without leaking navigation to gameplay.
2. Mouse/keyboard/physical-controller controls remain usable in a small window and 4K fullscreen; fullscreen transition retains the panel and selection.
3. Audio preferences survive relaunch and switching games; local-video/test-pattern controls omit cloud-only actions.
4. All termination entry points default to Cancel. Focus loss cancels only unconfirmed requests. Confirmed cleanup remains visible through focus changes and closes only after success; failure/retry remains operable using the controller.

At this handoff, P1 remained unchecked. No real service failure was injected during implementation.


## User acceptance — 2026-09-22

Implementation commit: `627d54a` — Add playback audio, fullscreen, and confirmed session controls.

After the requested commit and application restart, the user reported: “我测了一下都不错, 我觉得验收通过” (“I tested it and everything looks good; I consider acceptance passed.”).

This is the user's practical acceptance of the agreed Playback controls and settings increment. The roadmap item is complete. The user did not provide a per-scenario test transcript, so this does not assert that every device, boundary case, or real service-failure scenario was individually exercised. Existing automated failure/retry evidence remains distinct from live fault injection.

Numeric custom bitrate, extended streaming-reliability acceptance, frame-pacing comparisons, and other roadmap items remain separately tracked; this acceptance does not complete them.
