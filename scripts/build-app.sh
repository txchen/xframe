#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "$(uname -m)" != "arm64" ]]; then
    echo "XFrame requires an Apple Silicon Mac." >&2
    exit 1
fi

# The standalone macOS 27 Command Line Tools cannot initialize swiftbuild here.
swift build --build-system native -c release --arch arm64
binary_dir="$(swift build --build-system native -c release --arch arm64 --show-bin-path)"
app_dir="${XFRAME_APP_OUTPUT:-$PWD/.build/XFrame.app}"
rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources" "$app_dir/Contents/Frameworks"
cp "$binary_dir/XFrame" "$app_dir/Contents/MacOS/XFrame"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
cp Resources/AppIcon.icns "$app_dir/Contents/Resources/AppIcon.icns"
cp THIRD_PARTY_NOTICES.md "$app_dir/Contents/Resources/"
cp -R "$binary_dir/XFrame_XFrame.bundle" "$app_dir/Contents/Resources/"
rm -f "$app_dir/Contents/Resources/XFrame_XFrame.bundle/BigBuckBunny-1080p30.mp4"
cp -R "$binary_dir/WebRTC.framework" "$app_dir/Contents/Frameworks/"
# Strip unused Intel x86_64 slice and SDK headers from WebRTC.framework (XFrame is arm64-only).
webrtc_bin="$app_dir/Contents/Frameworks/WebRTC.framework/Versions/A/WebRTC"
if [[ "$(lipo -archs "$webrtc_bin")" == *"x86_64"* ]]; then
    lipo -thin arm64 "$webrtc_bin" -output "$webrtc_bin.arm64"
    mv "$webrtc_bin.arm64" "$webrtc_bin"
fi
rm -rf "$app_dir/Contents/Frameworks/WebRTC.framework/Headers" \
       "$app_dir/Contents/Frameworks/WebRTC.framework/Versions/A/Headers" \
       "$app_dir/Contents/Frameworks/WebRTC.framework/Modules" \
       "$app_dir/Contents/Frameworks/WebRTC.framework/Versions/A/Modules"
cp .build/artifacts/webrtc/WebRTC/WebRTC.xcframework/LICENSE "$app_dir/Contents/Resources/WebRTC-LICENSE.txt"
signing_identity="${XFRAME_SIGNING_IDENTITY:-}"
if [[ -z "$signing_identity" ]]; then
    if security find-certificate -c "XFrame Local Development" >/dev/null 2>&1; then
        signing_identity="XFrame Local Development"
    else
        signing_identity="-"
        echo "Warning: ad-hoc signing changes Keychain identity after rebuilds." >&2
    fi
fi
signing_options=()
if [[ "$signing_identity" == "Developer ID Application: "* ]]; then
    signing_options=(--options runtime --timestamp)
fi
codesign --force --sign "$signing_identity" ${signing_options[@]+"${signing_options[@]}"} "$app_dir/Contents/Frameworks/WebRTC.framework"
codesign --force --sign "$signing_identity" ${signing_options[@]+"${signing_options[@]}"} "$app_dir"
codesign --verify --deep --strict "$app_dir"
touch "$app_dir"
if [[ "${XFRAME_SKIP_REGISTRATION:-0}" != 1 ]]; then
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app_dir"
fi
echo "Built $app_dir"
