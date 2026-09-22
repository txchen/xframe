# Verify higher negotiated quality for HQ

Status: needs-triage
Type: task

## Evidence

The HQ selector, persistent configuration and outbound client-profile request are implemented and tested. Two Palworld main-menu sessions connected, but received video remained 1920x1080 and approximately 14.4–14.5 Mbps, similar to earlier Standard observations. The final request includes the full pinned XStreaming tizen device profile. See ../validation.md and ../xstream-research.md.

## Remaining question

Determine whether this account/title/region offers higher quality and whether native negotiation needs an additional supported bandwidth/capability request. Do not assume a successful create response proves the service honored HQ. Do not conflate a client profile, requested bitrate, actual bitrate or host GPU allocation.

## Follow-up acceptance

Use controlled comparable scenes and record received dimensions/bitrate for Standard versus HQ. Inspect only sanitized capability/codec/bandwidth fields if adding instrumentation; do not log authenticated payloads or raw SDP. If adding numerical custom bitrate, validate native negotiation independently: upstream native WebRTC does not consume that setting, whereas its WebView backend modifies SDP. Preserve bounded native hardware decoding and current input/session lifecycle. Keep HQ labeled experimental until stronger live evidence is available.

## Comments

- 2026-09-22: Black Flag failed to deliver a decoded first frame in two HQ starts, while a subsequent Standard start produced 1080p60 stream output. See [compatibility evidence](03-black-flag-hq-no-video.md). HQ remains experimental; no universal quality or compatibility claim is supported.

- 2026-09-22: Recorded after feature implementation. No higher-quality result is claimed for Palworld. Simplified Chinese language switching passed independently.
