# 0.1.4 / build 5 publication verification

Published 2026-11-16 from source commit `0db794c`, tag `v0.1.4`.

- Release: https://github.com/txchen/xframe/releases/tag/v0.1.4
- Archive: `XFrame-0.1.4-5-macos27-arm64.zip`
- SHA-256: `d9bdeb6878a0294f56635a153f7bd2e342318b1fd6e461f0600a70eceaef7232`
- Signing identity: Developer ID Application: Double Jump Academy (24HJJ8KB69).
- Apple submission `72eefa9e-502c-4c49-9715-1b15f4519f41`: Accepted. Staple validation and Gatekeeper assessment passed.
- Anonymous public download matched the final archive checksum; extracted public app passed signature, bundle version, architecture, stapling and Gatekeeper verification again.
- Homebrew `txchen/tap/xframe` updated to `0.1.4,5`, tap commit `70530b0`; `brew fetch --cask txchen/tap/xframe` passed.
- Full suite: 213 tests passed. Release boundary contract checks and trace analyzer timing/missing-stage checks passed.
- Release work and logs retained locally at `.build/releases/xframe-DjgJkurq/`. The submission ZIP was not published; the stapled final archive was.
- M1 live acceptance of the production code is recorded in the research document. This publication does not claim M5 acceptance or a universal one-refresh reduction. No local installed app was replaced or user session stopped during release delivery.

Remaining questions and suggested user checks: [presentation latency research](../../docs/presentation-latency-research.md).
