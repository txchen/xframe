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
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Resources/Info.plist)"
final="$sandbox/release/XFrame-$version-$build-macos27-arm64.zip"
touch "$final"
expect_failure 'Final ZIP already exists' bash scripts/release-app.sh notarize "$sandbox/release"
rm "$final"
mkdir "$sandbox/release/notarize.lock"
expect_failure 'Notarization already running' bash scripts/release-app.sh notarize "$sandbox/release"
rmdir "$sandbox/release/notarize.lock"
shasum -a 256 "$sandbox/release/submission.zip" | awk '{print $1}' > "$sandbox/release/submission.sha256"
submission_id=11111111-1111-1111-1111-111111111111
printf '%s\n' "$submission_id" > "$sandbox/release/submission-id"
printf '{"id":"%s"}\n' "$submission_id" > "$sandbox/release/submission.json"
mkdir "$sandbox/bin"
cat > "$sandbox/bin/xcrun" <<'SH'
#!/bin/bash
case "$2" in
wait) printf '{"id":"%s","status":"Accepted"}\n' "$3" ;;
log) printf '{"jobId":"%s","status":"Accepted","sha256":"wrong"}\n' "$3" > "$6" ;;
*) exit 99 ;;
esac
SH
chmod +x "$sandbox/bin/xcrun"
expect_failure 'Notary log archive checksum mismatch' env PATH="$sandbox/bin:$PATH" bash scripts/release-app.sh notarize "$sandbox/release"
[[ ! -e "$final" ]]
echo 'Release boundary contract checks passed'
