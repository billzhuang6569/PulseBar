#!/usr/bin/env bash
set -euo pipefail

EXECUTABLE_NAME="PulseBar"
APP_NAME="庄Sir的状态栏"
VERSION="0.3.1"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
ZIP_PATH="$DIST_DIR/$APP_NAME-$VERSION.zip"

cd "$ROOT_DIR"

./script/build_and_run.sh --verify
pkill -x "$EXECUTABLE_NAME" >/dev/null 2>&1 || true

rm -f "$ZIP_PATH"
cd "$DIST_DIR"
/usr/bin/ditto -c -k --keepParent "$APP_NAME.app" "$ZIP_PATH"

echo "$ZIP_PATH"
