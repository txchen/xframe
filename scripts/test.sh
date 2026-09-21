#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
developer_dir="$(xcode-select -p)"
framework_dir="$developer_dir/Library/Developer/Frameworks"
if [[ ! -d "$framework_dir/Testing.framework" ]]; then
    framework_dir="$developer_dir/Platforms/MacOSX.platform/Developer/Library/Frameworks"
fi
swift test --build-system native \
    -Xswiftc -F -Xswiftc "$framework_dir" \
    -Xlinker -rpath -Xlinker "$framework_dir" "$@"
