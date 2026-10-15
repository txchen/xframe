#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
fail() { echo "$*" >&2; exit 1; }
checksum() { shasum -a 256 "$1" | awk '{print $1}'; }
json_value() { /usr/bin/plutil -extract "$2" raw -o - "$1"; }
verify_archive() {
    [[ -f "$release/submission.zip" && -f "$release/submission.sha256" ]] || fail 'Missing prepared archive or checksum'
    [[ "$(checksum "$release/submission.zip")" == "$(cat "$release/submission.sha256")" ]] || fail 'Submission archive changed; prepare a new release'
}
case "${1:-}" in
prepare)
    [[ $# == 1 ]] || fail 'Usage: release-app.sh prepare'
    [[ "${XFRAME_SIGNING_IDENTITY:-}" == 'Developer ID Application: Double Jump Academy (24HJJ8KB69)' ]] || fail 'Set XFRAME_SIGNING_IDENTITY to Developer ID Application: Double Jump Academy (24HJJ8KB69)'
    mkdir -p "$PWD/.build/releases"
    release="$(mktemp -d "$PWD/.build/releases/xframe-XXXXXXXX")"
    echo "Release work directory: $release"
    trap 'echo "Release files retained at $release" >&2' EXIT
    XFRAME_APP_OUTPUT="$release/XFrame.app" XFRAME_SKIP_REGISTRATION=1 bash scripts/build-app.sh > "$release/build.log" 2>&1
    bash scripts/verify-release.sh "$release/XFrame.app" > "$release/verification.log" 2>&1
    ditto -c -k --sequesterRsrc --keepParent "$release/XFrame.app" "$release/submission.zip"
    checksum "$release/submission.zip" > "$release/submission.sha256"
    echo "Prepared $release"
    ;;
notarize)
    [[ $# == 2 || $# == 3 ]] || fail 'Usage: release-app.sh notarize prepared-directory [keychain-profile]'
    release="$(cd "$2" && pwd)"
    profile="${3:-xframe-notary}"
    [[ ! -e "$release/XFrame-0.1.0-macos27-arm64.zip" ]] || fail 'Final ZIP already exists'
    [[ ! -d "$release/notarize.lock" ]] || fail 'Notarization already running; inspect notarize.lock before retrying'
    mkdir "$release/notarize.lock"
    trap 'rmdir "$release/notarize.lock"; echo "Release files retained at $release" >&2' EXIT
    verify_archive
    if [[ ! -f "$release/submission-id" ]]; then
        [[ ! -e "$release/submission.json" ]] || fail 'Submission receipt exists without saved ID; inspect it before retrying'
        xcrun notarytool submit "$release/submission.zip" --keychain-profile "$profile" --output-format json > "$release/submission.json"
        submission_id="$(json_value "$release/submission.json" id)"
        [[ "$submission_id" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] || fail 'Invalid submission receipt ID'
        printf '%s\n' "$submission_id" > "$release/submission-id"
    fi
    submission_id="$(cat "$release/submission-id")"
    [[ "$submission_id" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] || fail 'Invalid saved submission ID'
    [[ "$(json_value "$release/submission.json" id)" == "$submission_id" ]] || fail 'Submission receipt ID mismatch'
    xcrun notarytool wait "$submission_id" --keychain-profile "$profile" --output-format json > "$release/notary-status.json"
    xcrun notarytool log "$submission_id" --keychain-profile "$profile" "$release/notary-log.json"
    [[ "$(json_value "$release/notary-status.json" id)" == "$submission_id" && "$(json_value "$release/notary-status.json" status)" == Accepted ]] || fail 'Notarization was not accepted; inspect logs'
    verify_archive
    extraction="$(mktemp -d "$release/staple-XXXXXXXX")"
    ditto -x -k "$release/submission.zip" "$extraction"
    bash scripts/verify-release.sh "$extraction/XFrame.app" > "$release/verification-before-staple.log" 2>&1
    xcrun stapler staple "$extraction/XFrame.app" > "$release/stapler.log" 2>&1
    final="$release/XFrame-0.1.0-macos27-arm64.zip"
    candidate="$extraction/final.zip"
    ditto -c -k --sequesterRsrc --keepParent "$extraction/XFrame.app" "$candidate"
    mkdir "$extraction/verify"
    ditto -x -k "$candidate" "$extraction/verify"
    bash scripts/verify-release.sh "$extraction/verify/XFrame.app" notarized > "$release/verification-final.log" 2>&1
    ln "$candidate" "$final"
    (cd "$release" && shasum -a 256 "$(basename "$final")" > "$(basename "$final").sha256")
    echo "Verified release: $final"
    ;;
*) fail 'Usage: release-app.sh prepare | notarize prepared-directory [keychain-profile]' ;;
esac
