# Exportable stream diagnostics and unattended regression checks

## Scope

Make completed native stream diagnostics exportable as a user-selected JSON file, without opening a cloud session or requiring an attached controller for verification. Keep the current in-memory event display. No automatic uploads, recordings or persistent background collection.

Use an explicit versioned allowlist of video/audio counters, numeric local duration, local video pipeline outcome, and the latest 128 typed events. Never serialize arbitrary status/error text, account identity, game title, session address, SDP, ICE addresses, credentials or media. Missing metrics are omitted, not represented as zero. Audio fields describe the last observed track/settings, not physical output after cleanup. The local pipeline outcome does not certify remote session deletion.

Capture after local peer cleanup; retain the immutable report through a remote cleanup retry. Clear it for the next session or account/catalog reset. Freeze duration and ignore late presentation/hardware callbacks after terminal state. Do not hide a decoder failure when normal cleanup follows.

Add a bounded serial regression runner that verifies fixtures and runs tests repeatedly without launching the app, authenticating, requesting UI access or changing power settings. Store logs only under ignored .build directories. Stop immediately on failure and preserve logs.

## Acceptance

- JSON schema, private-text exclusion, missing/nonfinite metrics, event bounds and terminal snapshot stability have automated coverage.
- Export data can be written/read without UI; the native save dialog remains a manual UI acceptance item.
- Full test suite and release build pass with no display interaction.
- Repeated suite results are recorded with exact totals; do not claim a long-duration soak from a short run.

## HUD bitrate increment

Schema version 3 adds optional video.bitrateMbps to the allowlist, sanitized to finite nonnegative values. It measures received video RTP payload, not all network traffic. Live stats expire after three seconds; missing/first/new-report-ID/reset samples remain unavailable. HUD visibility does not stop diagnostic collection.

- 2026-09-22: Schema 4 adds bounded numeric pacing summaries under timings.pacing (arrival/draw/drawable waits and categorized render/inbox counters); top-level privacy allowlist remains unchanged.

Schema 5 adds numeric gpuQueue/displayWait timing windows and a notPresented pacing counter. Failed drawable presentation timestamps are excluded from displayed-frame counts. The explicit export allowlist still excludes identifiers, URLs, addresses, tokens and video content.

Schema 6 adds the allowlisted framePacing enum (balanced/lowLatency), captured from the active video source rather than next-session preferences.
