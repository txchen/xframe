# In-picture playback settings

Status: needs-info
Implementation: original panel and agreed P1 controls extension implemented
Acceptance: original panel mouse/keyboard verified; P1 extension automated checks/build passed; new native UI and physical/live acceptance pending

## Agreed scope

The user requested settings without leaving gameplay/fullscreen and approved replacing the existing View + Menu HUD-cycle action with this panel.

- Right-click the playback picture to toggle an in-window settings overlay.
- View + Menu on an enabled controller opens the same panel during cloud playback. Keep the existing 300 ms chord recognition and standalone-button behavior.
- Expose Original / Integer Scaling / MetalFX Spatial and Compact / Detailed / Hidden HUD choices. Apply choices immediately and preserve their existing persistence.
- D-pad up/down navigates, A applies, B closes. Keyboard arrows/Return/Escape and mouse buttons also work. Close button, right-click, or a click on the surrounding picture dismisses.
- Video and audio continue; opening releases pending/held game input. Panel navigation is local, and closing requires controls to return to neutral before gameplay resumes. This does not pause the remote game.
- Close the panel on focus loss, source/session teardown, or playback-window hiding. Keep the panel inside the current fullscreen surface. Scroll on small windows.
- Command-Shift-D and the View menu retain direct HUD cycling/selection. Controller input remains opt-in.

## Controller preference follow-up

The user requested remembering controller enablement across application restarts. Persist both explicit enable and disable choices; restore the selection without restoring playback focus or held buttons. Initialize the View menu checkmark from that restored preference. Keep existing focus-loss release and neutral-before-rearm behavior.

The user rejected adding a controller-input toggle to the playback panel: a controller user could disable the very device navigating the panel. Keep that toggle exclusively in the View menu. First launch remains opt-in.

## Validation

Test opening-chord release gating, edge navigation, game-input release/rearm, mouse/keyboard UI, scaling persistence, fullscreen layout, and live session behavior. Physical controller chord/navigation requires actual-device acceptance; synthetic state tests alone do not prove it.

## P1 completion scope — agreed 2026-09-22

The user approved this increment's boundary during grill-with-docs. The additions below are implemented. Their automated evidence and remaining physical/live acceptance are recorded in validation.md.

- Add volume, mute, enter/exit fullscreen, and End Session to the in-picture playback panel.
- Specify audio preference persistence and protection against accidental session termination before implementation.
- Complete physical-controller navigation, small-window scrolling, live game-input isolation, and neutral-before-rearm acceptance.
- Keep HQ, game language, and frame pacing in their existing Streaming Settings location. Track numeric custom bitrate separately; it is not a completion gate for this increment.
- Outcome: after entering a game, common playback operations are accessible with a controller without returning to the library window.

The interaction decisions below are approved. Scope approval does not mark implementation or acceptance complete.

### End Session — agreed

- Selecting End Session opens an in-picture confirmation with Cancel selected by default. Controller A activates the selected choice; B cancels. The initial activation must not also confirm termination.
- After confirmation, stop local audio/video and game input, and show termination progress in the playback window.
- Close the playback window and return to the library only after the service confirms successful session cleanup.
- On cleanup failure, keep the error and Retry End Session accessible in the playback window, including controller navigation.
- Playback-window dismissal now follows the cleanup result rather than local media teardown.
- During a cloud session, the playback window's red close button / Command-W and the library's End Session action use the same confirmation, progress, and failure/retry flow as the playback panel. Default confirmation selection remains Cancel. Local-video window closing retains its existing behavior.
- Losing application/window focus before confirmation dismisses the confirmation and cancels the termination attempt. The game continues and existing focus-loss input release applies.
- After confirmation, termination continues despite focus loss. Returning to the application exposes pending progress or failure/retry; successful cleanup returns to the library.
- While termination is in progress, prevent duplicate requests. B cannot revoke an already-submitted termination request.
- Ordinary settings and unconfirmed termination dialogs retain focus-loss dismissal. Confirmed termination progress and failure/retry are lifecycle state, not disposable settings-panel state.

### Audio preferences — agreed

- All cloud games share one application-wide volume and mute preference, restored across application launches.
- First-use defaults are 100% volume and unmuted.
- Persist volume and mute independently. Muting preserves the selected volume; unmuting uses that volume.
- Adjusting volume while muted keeps mute enabled. For example, 40% volume plus mute restores as 40% plus mute on the next launch.
- These controls affect XFrame game audio only, not macOS system volume.

### Audio interaction — agreed

- Up/down moves between settings rows. When the volume row is selected, left/right changes volume by 5 percentage points per step, clamped to 0–100%.
- Holding left/right repeats volume adjustment. No separate volume-edit mode is required.
- Mute is a separate row; A toggles it.
- Keyboard arrow keys follow the same navigation and adjustment rules; mouse users can drag a volume slider.
- Changes apply immediately. B closes the panel without reverting changes.

### Fullscreen interaction — agreed

- A activates Enter Fullscreen or Exit Fullscreen according to the current window state.
- Keep the settings panel open and its navigation selection on the fullscreen row after the transition; update the action label to reflect the new state.
- Prevent repeated fullscreen activation during a transition. B dismisses the panel and returns to gameplay.
- Do not persist fullscreen state. New sessions retain the existing windowed presentation behavior, with remembered window size and position.

### Playback-source boundary — agreed

- Cloud gameplay exposes all playback controls described in this increment.
- Local video and the static test pattern retain scaling, HUD, fullscreen, and panel dismissal. Hide cloud-game volume, mute, and End Session controls for these sources.
- Extending local-video audio functionality is outside this increment.

### P1 acceptance checklist

- Verify mouse, keyboard, and physical-controller navigation in windowed and fullscreen playback, including scrolling to every control in a small window.
- Verify 5-point volume steps, bounded held-button repeat, slider operation, independent mute, and restoration across games/application launches.
- Verify fullscreen transition gating, retained panel selection, accurate action labels, and windowed presentation for a new session.
- Verify all agreed termination entry points, default-Cancel confirmation, prevention of activation carry-through, progress, successful cleanup, failure/retry, and duplicate-request suppression.
- Verify focus loss before and after termination confirmation, including return to progress/retry and successful return to the library.
- Verify live input isolation while local controls own navigation and neutral-before-rearm after dismissal. Opening settings does not pause the remote game.
- Verify source-specific controls for cloud gameplay, local video, and the static test pattern.
- Record automated checks, signed-build verification, and physical/live acceptance separately. Do not mark the roadmap item complete while required device acceptance remains pending.

The user confirmed shared understanding and explicitly authorized implementation on 2026-09-22.
