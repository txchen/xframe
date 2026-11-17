#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
app="$root/.build/render-path-probe/Render Path Probe.app"
mkdir -p "$app/Contents/MacOS"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -O "$root/tools/display-probe/main.swift" -o "$app/Contents/MacOS/RenderPathProbe" -framework AppKit -framework MetalKit
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>win.xframe.render-path-probe</string>
<key>CFBundleName</key><string>Render Path Probe</string>
<key>CFBundleExecutable</key><string>RenderPathProbe</string>
<key>CFBundleVersion</key><string>1</string>
<key>NSHighResolutionCapable</key><true/>
<key>LSMinimumSystemVersion</key><string>14.0</string>
</dict></plist>
PLIST
codesign --force --sign - "$app"
printf '%s\n' "$app"
