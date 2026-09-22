# In-picture playback settings

Status: needs-info
Implementation: complete
Acceptance: windowed and 4K fullscreen mouse/keyboard verified; physical controller and live input isolation pending

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
