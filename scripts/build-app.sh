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
app_dir="$PWD/.build/XFrame.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
mkdir -p "$app_dir/Contents/Frameworks"
cp "$binary_dir/XFrame" "$app_dir/Contents/MacOS/XFrame"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
cp Resources/AppIcon.icns "$app_dir/Contents/Resources/AppIcon.icns"
cp THIRD_PARTY_NOTICES.md "$app_dir/Contents/Resources/"
cp -R "$binary_dir/XFrame_XFrame.bundle" "$app_dir/Contents/Resources/"
cp -R "$binary_dir/WebRTC.framework" "$app_dir/Contents/Frameworks/"
cp .build/artifacts/webrtc/WebRTC/WebRTC.xcframework/LICENSE "$app_dir/Contents/Resources/WebRTC-LICENSE.txt"
bash scripts/prepare-benchmark-mlx.sh "$app_dir/Contents/MacOS"
signing_identity="${XFRAME_SIGNING_IDENTITY:-}"
if [[ -z "$signing_identity" ]]; then
    if security find-certificate -c "XFrame Local Development" >/dev/null 2>&1; then
        signing_identity="XFrame Local Development"
    else
        signing_identity="-"
        echo "Warning: ad-hoc signing changes Keychain identity after rebuilds." >&2
    fi
fi
codesign --force --sign "$signing_identity" "$app_dir/Contents/Frameworks/WebRTC.framework"
codesign --force --sign "$signing_identity" "$app_dir/Contents/MacOS/mlxdlss-benchmark"
codesign --force --sign "$signing_identity" "$app_dir/Contents/MacOS/mlx.metallib"
codesign --force --sign "$signing_identity" "$app_dir"
codesign --verify --deep --strict "$app_dir"
touch "$app_dir"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app_dir"
echo "Built $app_dir"
