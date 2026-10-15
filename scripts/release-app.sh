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
    [[ "${XFRAME_SIGNING_IDENTITY:-}" == 'Developer ID Application: '* ]] || fail 'Set XFRAME_SIGNING_IDENTITY to a Developer ID Application identity'
    mkdir -p "$PWD/.build/releases"
    release="$(mktemp -d "$PWD/.build/releases/xframe-XXXXXXXX")"
    echo "Release work directory: $release"
    trap 'echo "Release files retained at $release" >&2' EXIT
    XFRAME_APP_OUTPUT="$release/XFrame.app" XFRAME_SKIP_REGISTRATION=1 bash scripts/build-app.sh > "$release/build.log" 2>&1
    bash scripts/verify-release.sh "$release/XFrame.app" > "$release/verification.log" 2>&1
    cp "$release/XFrame.app/Contents/Info.plist" "$release/release-info.plist"
    ditto -c -k --sequesterRsrc --keepParent "$release/XFrame.app" "$release/submission.zip"
    checksum "$release/submission.zip" > "$release/submission.sha256"
    echo "Prepared $release"
    ;;
notarize)
    [[ $# == 2 || $# == 3 ]] || fail 'Usage: release-app.sh notarize prepared-directory [keychain-profile]'
    release="$(cd "$2" && pwd)"
    profile="${3:-xframe-notary}"
    version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$release/release-info.plist")"
    build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$release/release-info.plist")"
    [[ "$version" =~ ^[0-9]+(\.[0-9]+)*$ && "$build" =~ ^[0-9]+(\.[0-9]+)*$ ]] || fail 'Invalid release version'
    final="$release/XFrame-$version-$build-macos27-arm64.zip"
    [[ ! -e "$final" ]] || fail 'Final ZIP already exists'
    [[ ! -d "$release/notarize.lock" ]] || fail 'Notarization already running; inspect notarize.lock before retrying'
    mkdir "$release/notarize.lock"
    trap 'rmdir "$release/notarize.lock"; echo "Release files retained at $release" >&2' EXIT
    verify_archive
    if [[ ! -f "$release/submission-id" ]]; then
        if [[ -e "$release/submission.json" && ! -s "$release/submission.json" ]]; then
            mv "$release/submission.json" "$release/submission.failed.json"
        fi
        [[ ! -e "$release/submission.json" ]] || fail 'Submission receipt exists without saved ID; inspect it before retrying'
        xcrun notarytool history --keychain-profile "$profile" --output-format json > "$release/notary-preflight.json"
        if ! xcrun notarytool submit "$release/submission.zip" --keychain-profile "$profile" --output-format json > "$release/submission.pending.json" 2> "$release/submission.stderr.log"; then
            mv "$release/submission.pending.json" "$release/submission.failed.json"
            fail 'Submission failed; inspect submission.failed.json and submission.stderr.log before retrying'
        fi
        mv "$release/submission.pending.json" "$release/submission.json"
        submission_id="$(json_value "$release/submission.json" id)"
        [[ "$submission_id" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] || fail 'Invalid submission receipt ID'
        printf '%s\n' "$submission_id" > "$release/submission-id.pending"
        mv "$release/submission-id.pending" "$release/submission-id"
    fi
    submission_id="$(cat "$release/submission-id")"
    [[ "$submission_id" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] || fail 'Invalid saved submission ID'
    [[ "$(json_value "$release/submission.json" id)" == "$submission_id" ]] || fail 'Submission receipt ID mismatch'
    xcrun notarytool wait "$submission_id" --timeout 5m --keychain-profile "$profile" --output-format json > "$release/notary-status.json"
    xcrun notarytool log "$submission_id" --keychain-profile "$profile" "$release/notary-log.json"
    [[ "$(json_value "$release/notary-status.json" id)" == "$submission_id" && "$(json_value "$release/notary-status.json" status)" == Accepted ]] || fail 'Notarization was not accepted; inspect logs'
    verify_archive
    [[ "$(json_value "$release/notary-log.json" jobId)" == "$submission_id" && "$(json_value "$release/notary-log.json" status)" == Accepted ]] || fail 'Notary log does not match accepted submission'
    [[ "$(json_value "$release/notary-log.json" sha256)" == "$(checksum "$release/submission.zip")" ]] || fail 'Notary log archive checksum mismatch'
    extraction="$(mktemp -d "$release/staple-XXXXXXXX")"
    ditto -x -k "$release/submission.zip" "$extraction"
    bash scripts/verify-release.sh "$extraction/XFrame.app" signed "$release/release-info.plist" > "$release/verification-before-staple.log" 2>&1
    xcrun stapler staple "$extraction/XFrame.app" > "$release/stapler.log" 2>&1
    candidate="$extraction/final.zip"
    ditto -c -k --sequesterRsrc --keepParent "$extraction/XFrame.app" "$candidate"
    mkdir "$extraction/verify"
    ditto -x -k "$candidate" "$extraction/verify"
    bash scripts/verify-release.sh "$extraction/verify/XFrame.app" notarized "$release/release-info.plist" > "$release/verification-final.log" 2>&1
    printf '%s  %s\n' "$(checksum "$candidate")" "$(basename "$final")" > "$extraction/final.sha256"
    mv "$extraction/final.sha256" "$final.sha256"
    ln "$candidate" "$final"
    echo "Verified release: $final"
    ;;
*) fail 'Usage: release-app.sh prepare | notarize prepared-directory [keychain-profile]' ;;
esac
