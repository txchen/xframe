# Keyboard gamepad fallback

Requested 2026-09-22 during P0 live acceptance. Provide a usable, opt-in keyboard fallback for controller-only cloud games. This maps local keyboard events to the existing single Xbox gamepad wire protocol; it is not native game keyboard/mouse support.

- View > Enable Keyboard Input and Enable Controller Input are independent and can both be enabled. The last device with fresh intentional input owns the virtual controller. Both start off; no global keyboard capture or input-monitoring permission.
- Capture mapped keys only for the active, focused cloud playback window. Library search, dialogs, local videos and application shortcuts keep their normal behavior.
- Physical ANSI key positions: WASD left stick, arrows right stick, J/Space A, K B, U X, I Y, Q/E LB/RB, Z/C LT/RT, F/T/H/G D-pad left/up/right/down, L/O stick clicks, Return Menu, Tab View. Show a Keyboard Controls help action.
- Digital sticks/triggers are full scale (diagonal stick magnitude normalized), not analog aim or mouse look. Custom remapping remains future work.
- Release held keyboard input on focus loss, mode change, teardown and recovery. Ignore auto-repeat so a key held across loss of focus cannot reappear without a fresh keydown. Preserve short down/up edges through the existing bounded gamepad scheduler.
- Validate mapping, aliases, opposite axes, repeat/shortcut behavior and concurrent enablement offline; then use computer-use keyboard events in a different game for real protocol/UI acceptance. Preserve the previous physical Xbox acceptance as separate evidence.

- Automatic ownership: mapped fresh keydown takes keyboard ownership; new controller buttons or stick/trigger transitions outside a 0.25 dead zone take controller ownership. Releases, repeated held states and keyboard auto-repeat cannot claim. Switches discard queued old input and send neutral before the new state. HUD names the active device.
- Keyboard button/trigger taps have a 50 ms minimum wire hold; explicit focus/device release bypasses that hold. Physical controller timing remains unchanged.
