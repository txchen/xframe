# Streaming reliability

Scope: remaining P0 in the 2026-09-22 roadmap. Preserve the native media pipeline and opt-in controller behavior.

- Allow temporary ICE disconnection / video interruption to recover within 15 seconds. Show recovery status, release input, and request a keyframe at bounded intervals while waiting for fresh frames. Never create a replacement cloud session automatically.
- Keep heartbeat HTTP requests off the media watchdog path. Input-send backpressure uses the same 15-second recovery budget; transient heartbeat retries wait 1/2/4/8 seconds so a few immediate network errors cannot preempt a brief-outage recovery. Retry transient network failures with a bounded budget; stop on terminal service failures. Cancellation closes local resources promptly.
- On system sleep, stop local playback/input and end the owned session. On wake, retry outstanding cleanup if necessary; require explicit Play/Retry to allocate again.
- Preserve typed, privacy-safe terminal failure events and distinguish negotiation/transport/first-frame/stall/decode/heartbeat failures. Do not relabel startup failures as decode errors.
- Retry a failed game only after confirmed remote cleanup. Preserve the session handle on cleanup failure, including cancellation during create and transfer.

## Acceptance

Deterministic policy tests plus real library lifecycle tests, full test suite, signed development build. Live acceptance remains separate: repeated starts, 30+ minute play with A/V sync, short/long outages, fullscreen/window transitions and subsequent retry. Original intermittent VT bad-data root cause requires a failing live timeline; synthetic tests cannot close that issue.

2026-09-22 user scope update: sleep/wake physical acceptance is deferred as low priority and is not a gate for this iteration. Keep the implemented cleanup behavior and deterministic coverage.
