# Keychain probe

Checks that changed builds signed by the same Apple team read XFrame's Keychain
item without an authorization prompt. It compiles the app's real
`KeychainCredentialStore` and stores only a synthetic token under a probe-only
account, so it never reads or modifies the actual Microsoft sign-in.

```sh
export XFRAME_SIGNING_IDENTITY='Developer ID Application: Double Jump Academy (24HJJ8KB69)'
bash tools/keychain-probe/build.sh A /tmp/probe-a
bash tools/keychain-probe/build.sh B /tmp/probe-b
account="probe-$(uuidgen)"
/tmp/probe-a save "$account" synthetic-token
/tmp/probe-b load "$account"     # changed cdhash, same team: expect no prompt
/tmp/probe-b delete "$account"
```

A prompt blocks the command, so wrap runs in a timeout. Unteamed (ad hoc or
self-signed) builds are expected to prompt; that is why XFrame keeps the file
store for them.
