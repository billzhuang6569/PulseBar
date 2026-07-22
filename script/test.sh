#!/usr/bin/env bash
set -euo pipefail

DEVELOPER_DIR="$(xcode-select -p)"
FRAMEWORK_DIR="$DEVELOPER_DIR/Library/Developer/Frameworks"
LIBRARY_DIR="$DEVELOPER_DIR/Library/Developer/usr/lib"

if [ -d "$FRAMEWORK_DIR/Testing.framework" ]; then
  swift test \
    -Xswiftc -F -Xswiftc "$FRAMEWORK_DIR" \
    -Xlinker -rpath -Xlinker "$FRAMEWORK_DIR" \
    -Xlinker -rpath -Xlinker "$LIBRARY_DIR" \
    "$@"
else
  swift test "$@"
fi
