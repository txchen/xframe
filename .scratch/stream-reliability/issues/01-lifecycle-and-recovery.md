# Bounded recovery and session lifecycle

Status: needs-info
Type: task

Implement the behavior in [spec](../spec.md). Record automated evidence and outstanding live acceptance in ../validation.md. Keep the P0 checkbox open until live acceptance is met.

## Comments

2026-09-22: Implementation started. Existing controller acceptance is retained. No unattended cloud sessions or host sleep/network changes are required for automated verification.

2026-09-22: Implementation and 109 automated tests complete. Awaiting the live acceptance evidence in [validation](../validation.md), including original VT bad-data reproduction. No completion claim for the P0 checkbox.

2026-09-22: Live short outage initially failed, then passed after input backpressure budget and heartbeat retry fixes. User confirmed recovered audio/controller; timeline proves original-session recovery. 124 tests and signed build pass. Sleep/wake deferred by user and removed from this iteration gate; 30-minute soak and long-outage acceptance remain.
