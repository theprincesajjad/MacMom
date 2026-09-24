#!/bin/bash
# Build a release Appfold.app next to the package (or at the path in $1).
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
BIN="$(swift build -c release --show-bin-path)/Appfold"
APP_DIR="${1:-$PWD/.build/Appfold.app}"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
cp "$BIN" "$APP_DIR/Contents/MacOS/Appfold"
cp Info.plist "$APP_DIR/Contents/Info.plist"
codesign --force --sign - "$APP_DIR"
echo "$APP_DIR"
