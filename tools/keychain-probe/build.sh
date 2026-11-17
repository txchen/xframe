#!/bin/bash
# Usage: build.sh <variant> <output> [signing identity]
# Compiles the probe against Sources/XFrame/Auth/CredentialStore.swift. Each
# variant changes the binary (and cdhash) while keeping the signing identity.
set -euo pipefail
cd "$(dirname "$0")"
variant="$1" output="$2" identity="${3:-${XFRAME_SIGNING_IDENTITY:?set XFRAME_SIGNING_IDENTITY}}"
generated="$(mktemp -d)"
trap 'rm -rf "$generated"' EXIT
echo "let probeVariant = \"$variant\"" > "$generated/variant.swift"
swiftc -O -swift-version 6 -o "$output" main.swift stubs.swift "$generated/variant.swift" \
    ../../Sources/XFrame/Auth/CredentialStore.swift
codesign --force --sign "$identity" --identifier win.xframe.keychain-probe \
    --options runtime --timestamp "$output"
