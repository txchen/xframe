#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
sandbox="$(mktemp -d "$PWD/.build/release-contract-XXXXXXXX")"
trap 'rm -rf "$sandbox"' EXIT
expect_failure() {
    local expected="$1"
    shift
    if "$@" > "$sandbox/output" 2>&1; then
        echo 'Expected command to fail' >&2
        exit 1
    fi
    grep -F "$expected" "$sandbox/output" >/dev/null
}
expect_failure 'Set XFRAME_SIGNING_IDENTITY' env XFRAME_SIGNING_IDENTITY= bash scripts/release-app.sh prepare
expect_failure 'Usage:' bash scripts/release-app.sh unsupported
mkdir "$sandbox/release"
cp Resources/Info.plist "$sandbox/release/release-info.plist"
printf original > "$sandbox/release/submission.zip"
printf wrong > "$sandbox/release/submission.sha256"
expect_failure 'Submission archive changed' bash scripts/release-app.sh notarize "$sandbox/release"
[[ ! -e "$sandbox/release/notarize.lock" ]]
touch "$sandbox/release/XFrame-0.1.0-1-macos27-arm64.zip"
expect_failure 'Final ZIP already exists' bash scripts/release-app.sh notarize "$sandbox/release"
rm "$sandbox/release/XFrame-0.1.0-1-macos27-arm64.zip"
mkdir "$sandbox/release/notarize.lock"
expect_failure 'Notarization already running' bash scripts/release-app.sh notarize "$sandbox/release"
echo 'Release boundary contract checks passed'
