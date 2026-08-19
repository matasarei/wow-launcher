#!/bin/bash
# Build the WoW Launcher manager GUI and install it into the app bundle.
# Usage: ./build.sh [path-to-WoW.app]   (default: ~/Applications/WoW.app)
set -e
SRC="$(cd "$(dirname "$0")" && pwd)"
APP="${1:-$HOME/Applications/WoW.app}"
[ -d "$APP/Contents" ] || { echo "app bundle not found: $APP"; exit 1; }
mkdir -p "$SRC/build" "$APP/Contents/Resources/bin"
swiftc -swift-version 5 -parse-as-library -O -target arm64-apple-macos14.0 \
  -o "$SRC/build/WoW Launcher" "$SRC/main.swift"
codesign --force --sign - "$SRC/build/WoW Launcher"
rm -f "$APP/Contents/MacOS/WoW335"
cp "$SRC/build/WoW Launcher" "$APP/Contents/MacOS/WoW Launcher"
install -m 755 "$SRC/scripts/wow-"* "$APP/Contents/Resources/bin/"
# UI translations (macOS picks the app language from the system, fallback en)
for d in "$SRC/assets/lproj/"*.lproj; do
  ditto "$d" "$APP/Contents/Resources/$(basename "$d")"
done
echo "installed into $APP"
