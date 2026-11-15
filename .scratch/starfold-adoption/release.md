# XFrame 0.1.1 (build 2)

Status: notarized; publishing

Prepared directory: `.build/releases/xframe-F2VbrUJf`.
Signed with `Developer ID Application: Double Jump Academy (24HJJ8KB69)`.
Preparation and signed bundle verification passed, including hardened runtime and secure timestamps.
Notary profile: `xframe-notary`.
Apple agreement blocker resolved. Submission 89adf86a-117d-405b-9526-8b99a1659134 accepted; staple and Gatekeeper verification passed.
Final notarized ZIP prepared for GitHub and Homebrew publication.
Existing Homebrew version remains 0.1.0,1.

After Account Holder resolves Apple agreement, resume:

```sh
bash scripts/release-app.sh notarize "$PWD/.build/releases/xframe-F2VbrUJf"
```

Then publish v0.1.1 GitHub release with final ZIP and checksum, update txchen/tap Casks/xframe.rb to 0.1.1,2 and final SHA256, and verify public download plus brew fetch. Never publish submission.zip.

Release notes:
- Refresh expired Xbox authorization with bounded retries and concurrent request coordination.
- Prevent held controller inputs from carrying across focus and settings transitions.
- Improve signaling response handling, failure messages and startup polling.
- Add opt-in Adaptive smoothing; Balanced remains default.
- Improve sign-in guidance and controller Home button capture from preceding local commit.

Validation: 203 full tests passed; final signaling hardening passed 5 targeted tests; release contract checks and Developer ID bundle verification passed. Physical Xbox/controller and network A/B remain unverified.
