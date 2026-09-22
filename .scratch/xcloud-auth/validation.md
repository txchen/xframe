# xCloud Authentication Validation

Date: 2026-09-21

## Automated

- `bash scripts/test.sh`: 11 tests passed, including 8 authentication tests and the existing local-video checks. Authentication uses URLProtocol fixtures and an in-memory credential store, not live Microsoft credentials.
- `bash scripts/build-app.sh`: release build and local ad-hoc app signing succeeded.
- Authentication checks cover pending/slow-down intervals, declined authorization, untrusted verification URL rejection, error sanitization, percent encoding, refresh-token rotation, explicit free-to-play fallback, preservation of rotated credentials after downstream failure, and cancellation on sign-out.

## UI Inspection Limitation

The UI automation service repeatedly returned `cgWindowNotFound`. Temporary lifecycle probes confirmed the launch callback completed and both native windows reported visible. The automation inventory also returned no windows for other running applications. This distinguishes app startup from the automation visibility failure, but does not establish correct visual layout or determine the external cause. The temporary probes were removed; no speculative window workaround was applied.

## Pending Manual Acceptance

- Visually inspect the account window and device-code state.
- Complete live Microsoft authorization and verify gamertag/xCloud credentials.
- Verify real Keychain save, restart restoration, and local sign-out.
- Confirm live unsupported-account errors and offering behavior.
- Recheck native rendering and local playback with the account window present.

No real account login or live xCloud streaming success is claimed by this record.

## Subsequent Live Verification

The user completed Microsoft sign-in. UI inspection confirmed the Xbox gamertag, `xCloud credentials verified`, catalog offering access, regions, and expiration. XFrame was then fully quit (process absence checked) and relaunched; the same account and newly refreshed cloud credentials appeared without another browser login. This verifies the real Keychain save/read and refresh path. Local sign-out and actual game streaming are still not claimed as verified.
