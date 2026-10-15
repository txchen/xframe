# Distributing XFrame

XFrame currently supports Apple Silicon and macOS 27 or later. The release is a Developer ID signed, notarized ZIP. These commands build and package the app without installing, opening, or registering it with Launch Services. They do not access Microsoft account tokens.

Use an Apple Silicon Mac with the macOS 27 SDK, Swift 6.4, the project's build dependencies, and the Developer ID Application certificate and private key installed in Keychain.

```sh
export XFRAME_SIGNING_IDENTITY='Developer ID Application: Double Jump Academy (24HJJ8KB69)'
bash scripts/release-app.sh prepare
```

Preparation creates a unique directory under `.build/releases/`. It retains the signed `XFrame.app`, `build.log`, verification output, `submission.zip`, and its SHA-256. It requires bundle identifier `win.xframe.app`, version `0.1.0` build `1`, minimum macOS `27.0`, and arm64 binaries. There is no ad hoc release fallback. A failed preparation retains its directory and logs.

Create the `xframe-notary` Keychain profile separately using `xcrun notarytool store-credentials`. Keep credentials out of shell history and the repository. Then pass the exact prepared directory printed above.

```sh
bash scripts/release-app.sh notarize "$PWD/.build/releases/xframe-XXXXXXXX"
```

An optional third argument selects another Keychain profile. This step submits the immutable prepared ZIP, saves its submission receipt and ID, waits for acceptance, and downloads Apple's log. Retrying the same command reuses the saved ID and verifies the archive checksum. If a submission receipt exists without an ID, inspect the receipt before recovering the ID manually. Do not submit a changed archive under an old ID.

After acceptance, the script extracts the submitted ZIP into a fresh directory, staples the app, creates a new ZIP, extracts it again, and verifies signatures, signing team, runtime, secure timestamps, architecture, bundle identity, staple, and Gatekeeper acceptance. Only then does it publish `XFrame-0.1.0-macos27-arm64.zip` and its `.sha256` alongside the logs. Existing final ZIPs are never overwritten. Failed attempts retain staging files. A lock prevents simultaneous notarization of the same directory; remove a stale `notarize.lock` only after confirming the previous command has stopped.

Distribute the final versioned ZIP and checksum. The submission ZIP predates stapling and is retained as evidence, not as the download artifact. Gatekeeper checks on the extracted final app establish distribution validation; they do not establish Xbox streaming or physical device acceptance.

For development, `bash scripts/build-app.sh` retains its existing signing selection, `.build/XFrame.app` output, and Launch Services registration. `XFRAME_APP_OUTPUT` overrides the output path and `XFRAME_SKIP_REGISTRATION=1` skips registration.
