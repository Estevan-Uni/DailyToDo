#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
developer_dir="$(xcode-select -p)"
framework_dir="$developer_dir/Library/Developer/Frameworks"
if [[ -d "$framework_dir/Testing.framework" ]]; then
  # CLT ships Swift Testing but omits XCTest and the Foundation overlay module.
  # Disable only cross-import overlays; production modules retain full Foundation.
  swift test --disable-xctest \
    -Xswiftc -F -Xswiftc "$framework_dir" \
    -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
    -Xlinker -rpath -Xlinker "$framework_dir" "$@"
else
  swift test --disable-xctest "$@"
fi
