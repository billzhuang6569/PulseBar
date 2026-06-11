#!/usr/bin/env bash
set -euo pipefail

APP_NAME="PulseBar"
VERSION="0.2.4"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
ZIP_PATH="$DIST_DIR/$APP_NAME-$VERSION.zip"

cd "$ROOT_DIR"

./script/build_and_run.sh --verify
pkill -x "$APP_NAME" >/dev/null 2>&1 || true

rm -f "$ZIP_PATH"
cd "$DIST_DIR"
/usr/bin/ditto -c -k --keepParent "$APP_NAME.app" "$ZIP_PATH"

echo "$ZIP_PATH"
