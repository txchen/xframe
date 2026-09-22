# Restart playback in a normal window

Status: needs-info
Type: task

User observed that ending a fullscreen cloud session from the library hides the playback window while retaining its fullscreen state. A subsequent session cannot reveal the window predictably and eventually reappears fullscreen. Start every new playback in a normal window; users may then enter fullscreen explicitly.

## Reproduction and diagnosis

Extracted the existing show/hide calls into PlaybackWindowPresentation without changing their behavior. `bash scripts/test.sh --filter 'endingFullscreen|newPlayback'` failed both tests: ending emitted only `hide`, restart emitted `hide, show`, with no fullscreen exit. This reproduces the retained-state bug at the actual presentation-call boundary; native Space/animation behavior still requires UI validation.

Ranked hypotheses: retained fullscreen state; asynchronous transition races; retained minimization. The first is confirmed by the failing tests and the original call path. Handle asynchronous enter/exit completion before applying the latest visibility request; normal display deminiaturizes and constrains placement.

## Comments

- User confirmed controller reconnection and fullscreen input work; the defect concerns window lifecycle, not controller transport.
- Regression fix: exit fullscreen before hiding/showing windowed, defer through native transition callbacks, apply the newest request, preserve explicit in-session fullscreen, and do not loop on failed exit.
- Five window presentation regressions pass. Full suite: 74 tests passed (`.build/window-lifecycle-tests.log`); signed build and strict signature verification passed (`.build/window-lifecycle-build.log`). Native cloud lifecycle verification is in progress.
- Native validation passed: started Palworld windowed, entered fullscreen (3840×2160), opened the library with Shift-Command-G, ended the session and observed Session ended, then started Palworld again. The second stream displayed with title bar/window controls at 3840×2036 rather than returning to fullscreen. No save was entered or modified. Awaiting the user's subjective UX confirmation.
