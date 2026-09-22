# Persistent window placement

Use separate native AppKit frame autosave names for library and playback. Restore before showing, use a larger first-run library size, then constrain the frame to the visible screen with the greatest intersection (or the main screen when disconnected). Recheck on display configuration changes. Do not reposition fullscreen windows.

## Validation

- 64 tests passed; signed production build succeeded.
- Geometry tests cover unchanged valid placement, negative-coordinate secondary screens, disconnected screens, oversized frames, Dock overlap, and no available screens.
- Live first-run library frame was 1240×852 including the title bar.
- Native zoom changed its saved frame to 1920×1050; quitting and relaunching restored the enlarged main window, verified visually.
- Playback has a separate autosave name but was not launched in this pass. Physical display disconnect and fullscreen transitions were not exercised.
