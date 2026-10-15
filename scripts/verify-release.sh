#!/bin/bash
set -euo pipefail
app="${1:?Usage: verify-release.sh app-path [notarized]}"
fail() { echo "$*" >&2; exit 1; }
plist="$app/Contents/Info.plist"
value() { /usr/libexec/PlistBuddy -c "Print :$1" "$plist"; }
[[ "$(value CFBundleIdentifier)" == win.xframe.app ]] || fail 'Unexpected bundle identifier'
[[ "$(value CFBundleExecutable)" == XFrame ]] || fail 'Unexpected executable'
[[ "$(value CFBundlePackageType)" == APPL ]] || fail 'Unexpected package type'
expected_plist="${3:-Resources/Info.plist}"
for key in CFBundleShortVersionString CFBundleVersion; do
    [[ "$(value "$key")" == "$(/usr/libexec/PlistBuddy -c "Print :$key" "$expected_plist")" ]] || fail "Unexpected $key"
done
[[ "$(value LSMinimumSystemVersion)" == 27.0 ]] || fail 'Unexpected minimum macOS version'
codesign --verify --deep --strict --verbose=2 "$app"
for target in "$app" "$app/Contents/MacOS/XFrame" "$app/Contents/MacOS/mlxdlss-benchmark" "$app/Contents/Frameworks/WebRTC.framework"; do
    details="$(codesign -d --verbose=4 "$target" 2>&1)"
    [[ "$details" == *'TeamIdentifier=24HJJ8KB69'* ]] || fail "Unexpected signing team: $target"
    [[ "$details" == *'Authority=Developer ID Application: '* ]] || fail "Unexpected signing authority: $target"
    [[ "$details" == *'runtime'* && "$details" == *'Timestamp='* ]] || fail "Missing runtime or timestamp: $target"
done
metal_details="$(codesign -d --verbose=4 "$app/Contents/MacOS/mlx.metallib" 2>&1)"
[[ "$metal_details" == *'TeamIdentifier=24HJJ8KB69'* && "$metal_details" == *'Timestamp='* ]] || fail 'Unexpected Metal library signature'
codesign --verify --strict "$app/Contents/MacOS/mlx.metallib"
for binary in "$app/Contents/MacOS/XFrame" "$app/Contents/MacOS/mlxdlss-benchmark"; do
    [[ "$(lipo -archs "$binary")" == arm64 ]] || fail "Expected arm64 only: $binary"
done
framework_archs=" $(lipo -archs "$app/Contents/Frameworks/WebRTC.framework/WebRTC") "
[[ "$framework_archs" == *' arm64 '* ]] || fail 'WebRTC is missing arm64'
build_version="$(xcrun vtool -show-build "$app/Contents/MacOS/XFrame")"
[[ "$(awk '$1 == "platform" {print $2}' <<< "$build_version")" == MACOS ]] || fail 'Unexpected executable platform'
[[ "$(awk '$1 == "minos" {print $2}' <<< "$build_version")" == 27.0 ]] || fail 'Unexpected executable minimum macOS version'
if [[ "${2:-}" == notarized ]]; then
    xcrun stapler validate "$app"
    spctl --assess --type execute --verbose=2 "$app"
fi
