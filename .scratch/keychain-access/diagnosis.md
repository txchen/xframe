# Repeated Keychain Authorization After Rebuild

## Evidence

The user confirmed a prompt for XFrame's Microsoft sign-in item after launching a changed build. Restarting the same previously approved binary succeeded without a prompt. A fixed self-signed certificate preserved the designated requirement but did not prevent the rebuild prompt.

`swift .scratch/keychain-access/inspect.swift` performs metadata-only inspection of the exact refresh-token item with user interaction disabled. It does not request password data or modify access. Both item and ACL metadata queries succeeded. The decrypt ACL contains XFrame trusted-application entries, but a separate partition ACL contains only `cdhash:8a614e9b2e896581e5abcbf60c310395577cecda`. This matches the currently approved app's code directory hash. Signing information reports XFrame Local Development and no TeamIdentifier.

Apple's published Security implementation uses Apple-verified team identity for qualifying developer signatures and falls back to the code directory hash for other signed applications. Thus a stable designated requirement from a self-signed certificate does not provide a stable partition identity across changed binaries.

Source: https://github.com/apple-oss-distributions/Security/blob/main/securityd/src/clientid.cpp (partitionIdForProcess).

## Conclusion and Boundary

The observed hash-bound partition restriction explains the same-binary/rebuilt-binary difference. This is not a Microsoft password challenge or codesign private-key authorization. The previous assumption that a self-signed certificate alone would solve repeat authorization was incomplete.

No ACL or trust settings were changed, no token was read, and no additional authorization prompt was deliberately triggered during this diagnosis. Metadata inspection is not an end-to-end no-prompt regression test. A changed-build acceptance test is still required after a fix.

The preferred next step is a suitable Apple-issued code-signing identity and a one-time migration authorization, followed by a changed-build test. This needs user-managed Apple developer signing setup; do not substitute a self-signed TeamIdentifier or broaden access to all applications. Do not delete the saved login, disable partition enforcement, or move tokens into plaintext to suppress prompts.
