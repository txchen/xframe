# xCloud Authentication Slice

## Goal

Start with Xbox Cloud Gaming for testability; console remote play follows later. Deliver the smallest useful network slice: Microsoft sign-in, Xbox identity, persisted refresh credentials, and an xCloud authorization check. This slice does not establish a streaming session.

## Behavior

- Native account window with Microsoft device-code sign-in, cancellation, expiration, and actionable sanitized errors.
- Browser-based authorization; XFrame never collects the Microsoft password.
- Xbox gamertag and xCloud offering, region names, and credential lifetime after successful authorization.
- Try `xgpuweb` first; on HTTP 403 only, try `xgpuwebf2p` and distinguish free-to-play access.
- Save only the Microsoft refresh token in local Keychain. Persist token rotation before downstream Xbox requests.
- Restore saved sign-in at startup and support manual rechecking. Do not silently erase saved credentials on service failures.
- Sign-out cancels in-flight work, clears in-memory credentials, and removes only XFrame's Keychain entry. It is local sign-out, not browser sign-out or grant revocation.
- Preserve local video and static rendering behavior. macOS 27+, Apple Silicon only.

## Security Boundaries

HTTPS API requests use an ephemeral session without cookies or cache. Credential-bearing redirects are refused. Browser verification destinations are restricted to known Microsoft hosts. Returned regional service URLs must be HTTPS Xbox Live hosts. Raw service errors and tokens never enter UI errors or logs. No region spoofing, password collection, or client secret is used.

The public client identifier comes from XStreaming, not an XFrame-owned registration. This is an explicit development dependency, not a claim of production approval or long-term compatibility. Device-code authorization should be initiated by the user; codes should not be shared.

## Protocol Reference

Reference: [Geocld/XStreaming](https://github.com/Geocld/XStreaming), commit `383e19d324f2d3029d1c304752f4d38a9360bb95`, `src/xal/msal.ts` and `src/MsalAuthentication.ts`. See `THIRD_PARTY_NOTICES.md` for its MIT notice.

1. Microsoft consumers OAuth device-code endpoint, followed by token polling respecting the interval, pending, slow-down, denial, and expiration responses.
2. Xbox RPS user authentication using the Microsoft access token.
3. XSTS authorization for Xbox identity and separately for `http://gssv.xboxlive.com/`.
4. `https://{offering}.gssv-play-prod.xboxlive.com/v2/login/user` for the selected xCloud offering.

The current reference uses device-code authentication; its older signed-device/SISU documentation is not the implementation path used here. Unlike the reference's broad fallback, transport and server errors do not trigger a different offering.

Protocol guidance: [Microsoft device authorization](https://learn.microsoft.com/en-ie/entra/identity-platform/v2-oauth2-device-code), [RFC 8628](https://www.rfc-editor.org/rfc/rfc8628.html).

## Acceptance

Automated checks cover polling, rejection of untrusted URLs, denial, safe errors, form encoding, refresh rotation, downstream failure, offering fallback, and sign-out cancellation. Existing hardware video tests must pass.

Manual checks require a user-owned Microsoft/Xbox account: complete authorization, see identity and access results, restart and restore, cancel a new attempt, sign out, and restart without restored credentials. Unsupported eligibility must be clearly reported rather than presented as streaming readiness.

## Deferred

Game catalog, game launch, queue/session lifecycle, WebRTC signaling, audio/video transport, controller input, automatic streaming credential renewal, console remote play, and production identity registration/distribution.
