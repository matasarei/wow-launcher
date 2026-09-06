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
rm -f "$APP/Contents/MacOS/WoW335" "$APP/Contents/Resources/bin/wow-client-fonts.py"   # pre-native leftovers
cp "$SRC/build/WoW Launcher" "$APP/Contents/MacOS/WoW Launcher"
install -m 755 "$SRC/scripts/wow-"* "$APP/Contents/Resources/bin/"
# native font tool (MPQ extraction + CP1251 remap; no Python at run time)
# NB -Onone, deliberately. At -O this file is miscompiled by Swift 6.1.2 (the
# toolchain on macOS 15): the binary dies with EXC_BAD_ACCESS in
# swift_unknownObjectRetain on a garbage pointer before it extracts anything,
# while the same source at -Onone produces byte-identical output. macOS 15 is
# the minimum this app supports and the tool is what makes Cyrillic work, so it
# is not optional there. The cost is nothing that matters: 0.16 s instead of
# 0.02 s over a real 30 MB ruRU locale MPQ, once per install.
swiftc -swift-version 5 -Onone -target arm64-apple-macos14.0 \
  -o "$SRC/build/wow-client-fonts" "$SRC/tools/wow-client-fonts.swift"
codesign --force --sign - "$SRC/build/wow-client-fonts"
install -m 755 "$SRC/build/wow-client-fonts" "$APP/Contents/Resources/bin/wow-client-fonts"
# UI translations (macOS picks the app language from the system, fallback en)
for d in "$SRC/assets/lproj/"*.lproj; do
  ditto "$d" "$APP/Contents/Resources/$(basename "$d")"
done
echo "installed into $APP"
