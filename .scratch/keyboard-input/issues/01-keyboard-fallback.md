# Opt-in keyboard gamepad

Status: ready-for-human
Type: task

Implement [spec](../spec.md), then verify real game menu interaction and focus release in the signed app. Record live scope and limits separately from unit tests.

## Comments

2026-09-22: 114 tests and signed build pass. Live Forza J/A advanced the title screen; E/RB and K/B navigation were observed, but several computer-use K taps did not change the map/playlist screen. Do not call keyboard acceptance complete yet. Need to distinguish very short keypress delivery, local event routing, and game transition/input sampling. Physical keyboard comparison remains useful.

2026-09-22: User requested simultaneous enablement with last-active-device takeover. Implemented neutral handoff, fresh-edge ownership, drift filtering, HUD owner label, and 50 ms keyboard tap hold. 119 tests and signed build pass; physical alternation still needs live verification.

2026-09-22: Basic bidirectional takeover passed live: user confirmed Xbox takeover, independently observed in HUD; subsequent tool K/B switched to Keyboard and returned to garage menu. Extended physical keyboard/focus/held-control acceptance remains separate.
