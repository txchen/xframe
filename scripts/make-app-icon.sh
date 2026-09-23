#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

iconset="$(mktemp -d "${TMPDIR:-/tmp}/xframe-icon.XXXXXX")/AppIcon.iconset"
trap 'rm -rf "$(dirname "$iconset")"' EXIT
mkdir -p "$iconset"

for size in 16 32 128 256 512; do
    sips -s format png -z "$size" "$size" Resources/AppIcon.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
    double_size=$((size * 2))
    sips -s format png -z "$double_size" "$double_size" Resources/AppIcon.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$iconset" -o Resources/AppIcon.icns
