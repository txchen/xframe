# Series X LAN validation, 2026-10-16

Status: real Series X video and keyboard control verified; audio and physical controller acceptance pending.

## Environment and baseline

The user confirmed a Series X on the Mac's LAN with remote features enabled. The existing app restored the Xbox account and listed one associated XboxSeriesX as ConnectedStandby. No credential values were printed or copied.

The agent clicked Wake Console. The user confirmed that the console stayed asleep, then manually turned it on. The app eventually reported that wake was sent but the console was not visible on the LAN. This does not establish a network timeout root cause or successful wake.

With the console awake, an independent UDP 5050 discovery probe received ten 652-byte `dd01` replies over three seconds. The name length was 4 at byte 12 and 22594 at byte 14. The original `ConsoleDiscovery.discover()` implementation, compiled into a small local probe, returned zero consoles. This reproduces the parser defect on the actual Series X. Raw console IDs, certificates, and network addresses were not retained.

Baseline `bash scripts/test.sh` passed all 167 tests. Baseline tests included a discovery fixture with the same incorrect offset as the parser; they did not detect the real-console incompatibility.

## Corrected discovery

After integrating discovery commit `d3109e3`, the same compiled probe returned **1 parsed LAN console**. This is real-console discovery evidence, not yet streaming evidence. The isolated discovery/wake suite passed all 168 tests with `--no-parallel`; the initial parallel run encountered existing auth teardown/timing failures under concurrent build load.

## Actual stream

The signed release app `.build/XFrame-LAN-Diagnostic.app` listed **1 associated console and 1 on the LAN**, with `On`, `Found on this LAN`, and a separate Connect button. Connect created the home session and displayed the actual Series X dashboard. The view reported H.264 at **1920 × 1080**. Several short HUD observations showed received stream cadence around 60 fps. This is a single dashboard session observation, not a benchmark, game-render FPS, or a long-run stability claim.

Sanitized transport logs accepted two remote UDP host candidates, rejected seven remote unsupported-address candidates, and recorded `home gate waiting -> verified`. The gate checks the selected direct endpoint pair against the current physical IPv4 subnet. No STUN server is configured for this session. These are selected-path and application-policy evidence, not packet-firewall proof.

The agent enabled keyboard input and sent the D-pad-right mapping (`H`). The dashboard selection visibly moved from The Crew Motorfest to Forza Horizon 6. No game was launched. Controller input was then enabled for user testing. Audible audio and physical rumble cannot be inferred from the picture or capability checks.

After the final inline-SDP admission correction, `bash scripts/test.sh` passed **174 tests without skips**. The release app built and passed `codesign --verify --deep --strict`. Packaging first exposed an existing macOS Bash empty-array/nounset error; guarded array expansion fixed it in the actual successful build.

## Development app network observation

The `.build/XFrame-LAN.app` variant failed six discovery sends with errno 65 while the system Local Network pane showed its switch enabled. `.build/XFrame-LAN-Diagnostic.app` consistently sent six requests, received six replies, parsed one console, and matched it to the account. Both have the same designated signing requirement. The cause of the variant-specific network failure is unresolved; do not label it an account mismatch or claim a permission fix. The successful app was registered with LaunchServices. Temporary identifier-format logging was removed; retained discovery logging includes counts and errno only.

## Remaining physical verification

- Audible menu/game audio and user-observed physical controller response/rumble.
- Explicit wake from standby with the new payload and response handling.
- Same-session recovery from a brief network interruption.
- Disconnect leaves the console powered on and reconnect succeeds without changing its game.

Candidate admission and sampled selected-pair verification do not constitute a packet firewall. Keep observed route evidence separate from stronger claims about every possible host routing or ICE behavior.
