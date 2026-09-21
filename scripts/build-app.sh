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
cp "$binary_dir/XFrame" "$app_dir/Contents/MacOS/XFrame"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
cp -R "$binary_dir/XFrame_XFrame.bundle" "$app_dir/Contents/Resources/"
codesign --force --sign - "$app_dir"
echo "Built $app_dir"
