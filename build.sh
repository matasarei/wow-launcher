#!/bin/bash
# Build the WoW335 manager GUI and install it into the app bundle.
# Usage: ./build.sh [path-to-WoW335.app]   (default: ~/Applications/WoW335.app)
set -e
SRC="$(cd "$(dirname "$0")" && pwd)"
APP="${1:-$HOME/Applications/WoW335.app}"
[ -d "$APP/Contents" ] || { echo "app bundle not found: $APP"; exit 1; }
mkdir -p "$SRC/build" "$APP/Contents/Resources/bin"
swiftc -swift-version 5 -parse-as-library -O -target arm64-apple-macos14.0 \
  -o "$SRC/build/WoW335" "$SRC/main.swift"
codesign --force --sign - "$SRC/build/WoW335"
cp "$SRC/build/WoW335" "$APP/Contents/MacOS/WoW335"
install -m 755 "$SRC/scripts/wow-"* "$APP/Contents/Resources/bin/"
echo "installed into $APP"
