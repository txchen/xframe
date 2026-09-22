# Cloud quality and startup language preferences

Status: needs-triage
Resolution: HQ and language controls implemented; zh-CN accepted by live observation
Type: task

## User request

On 2026-09-22 the user asked about XStreaming's high-bitrate option and selecting the game language at launch. Palworld displays XSS and feels closer to 30 fps despite XFrame's roughly 60 fps decode counter.

## Verified XFrame gaps

- CloudService.create hardcodes settings.locale=en-US. Catalog metadata separately uses language=en-US. A game language preference must remain independent of the application's English UI/catalog policy.
- Session device info advertises macOS desktop and a 1920×1080 display. No HQ preset or custom video bitrate setting is exposed; SDP is sent without a bitrate override.
- Decode avg counts incoming decoded RTCVideoFrame callbacks; Present avg counts new video frame presentation callbacks. Neither estimates distinct visual content. xframe_requirement.md section 20 explicitly distinguishes transport, unique-content and presented FPS; unique-content estimation remains unimplemented.

## Candidate acceptance for a later implementation

- Persistent game-language selection, applied when creating a new session, with en-US, zh-CN and zh-TW among supported preferences. Verify Palworld's actual language after a clean new session; preferences are requests, not proof a title supports a locale.
- Keep quality profile, bitrate limit and achieved video bitrate distinct. Reference XStreaming's session-profile and SDP paths separately. Never describe higher bitrate as an upgrade to host GPU or a guarantee of 60 unique frames/second.
- Add measured received Mbps and received dimensions so a requested HQ setting can be tested against actual transport results. Treat subscription/title/region/service constraints as authoritative.
- Label existing FPS clearly as stream decode/presentation rates. A future unique-content estimate must be bounded and must not add full-resolution CPU readback to the zero-copy media path.

## Comments

This issue records research and gaps; no stream preference, active session or production code was changed in this research pass. See ../xstream-research.md for pinned primary source findings.

- 2026-09-22: User explicitly requested implementation of high-bitrate controls and startup game language as important features. Before implementation, user asked for an explanation of STREAM approximately 60 versus OUT in the low 50s; answer this first.

- 2026-09-22: HQ and startup-language settings implemented per ../spec.md. 85 automated tests pass, including request body/device-header consistency, persistence with invalid-value fallback, and next-session snapshot isolation. Preparing signed UI and Palworld validation. Numeric custom bitrate and unique-content FPS remain separate future work.

- 2026-09-22: Signed UI, persistence across app restart, and Chinese Palworld title/menu verified. HQ connects but remains 1080p around 14.4 Mbps in this scene; no improvement claim. See ../validation.md and 02-hq-negotiation-validation.md. Numerical custom bitrate remains outside this increment.
