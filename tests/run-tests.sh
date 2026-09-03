#!/bin/bash
# Hermetic test suite for the wrapper scripts — no game data, no real wine,
# no network. Builds a fake wrapper (scripts + stub wine + dummy payloads)
# and fake clients out of empty files, then exercises version detection,
# install validation/patching, verify totals, and launch behavior.
# Run: make test   (or bash tests/run-tests.sh)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d /tmp/wow-tests.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAILED=0
ok()   { PASS=$((PASS+1)); }
bad()  { FAILED=$((FAILED+1)); echo "  ✗ $*"; }
assert_eq()       { [ "$1" = "$2" ]           && ok || bad "$3 — expected '$2', got '$1'"; }
assert_contains() { echo "$1" | grep -qF -- "$2" && ok || bad "$3 — output missing '$2'"; }
assert_file()     { [ -f "$1" ]               && ok || bad "missing file: ${1#$TMP/}"; }
assert_nofile()   { [ ! -e "$1" ]             && ok || bad "unexpected file: ${1#$TMP/}"; }
section() { echo "== $*"; }

# deterministic display for wow-settings (retina 3456x2234 / 1728x1117)
export WOW_TEST_DISPLAY="3456x2234 1728x1117 yes"

# ---------------------------------------------------------------- fake wrapper
APP="$TMP/WoW.app"; RES="$APP/Contents/Resources"; BIN="$RES/bin"
mkdir -p "$BIN" "$RES/games" "$RES/logs" "$RES/wine/bin" "$RES/wine/lib/wine/x86_64-unix" \
         "$RES/prefix/dosdevices" \
         "$RES/patch-kit/mods" "$RES/patch-kit/rosettax87" "$RES/patch-kit/x87sidecar" \
         "$RES/patch-kit/libSiliconPatch/vanilla" "$RES/patch-kit/libSiliconPatch/wotlk"
cp "$ROOT/scripts/"wow-* "$BIN/"; chmod +x "$BIN"/wow-*
printf 'AUTO_RES=1\nCHAT_CP=\n' > "$RES/launcher.conf"   # CHAT_CP= opts out (hermetic)
echo d3d9    > "$RES/patch-kit/d3d9.dll"
echo dllldr  > "$RES/patch-kit/libDllLdr.dll"
echo winero  > "$RES/patch-kit/mods/winerosetta.dll"
echo sil-van > "$RES/patch-kit/libSiliconPatch/vanilla/libSiliconPatch.dll"
echo sil-lk  > "$RES/patch-kit/libSiliconPatch/wotlk/libSiliconPatch.dll"
echo vtweaks > "$RES/patch-kit/vanilla-tweaks.exe"
echo rx87    > "$RES/patch-kit/rosettax87/rosettax87"
echo librx87 > "$RES/patch-kit/rosettax87/libRuntimeRosettax87"
echo rxshim  > "$RES/patch-kit/rosettax87/rosettax87-shim"
echo sidecar > "$RES/patch-kit/x87sidecar/x87sidecar"
chmod +x "$RES/patch-kit/x87sidecar/x87sidecar" "$RES/patch-kit/rosettax87/"*

# stub wine: logs every invocation + interesting env, answers registry queries
WINELOG="$TMP/wine.log"; : > "$WINELOG"
cat > "$RES/wine/bin/wine" <<'STUB'
#!/bin/bash
echo "WINE ARGS: $* | OVR=${WINEDLLOVERRIDES:-} SIDECAR=${X87_SIDECAR_PATH:-} ROSETTA=${ROSETTA_X87_PATH:-} LOADER=${WINELOADER:-}" >> "$WINE_STUB_LOG"
case "$*" in
  *"reg query"*RetinaMode*)  printf '    RetinaMode    REG_SZ    Y\r\n' ;;
  *"reg query"*ProxyServer*) printf '    ProxyServer    REG_SZ    127.0.0.1:1\r\n' ;;
  *"reg query"*ProxyEnable*) printf '    ProxyEnable    REG_DWORD    0x1\r\n' ;;
  *"reg query"*ACP*)         printf '    ACP    REG_SZ    1252\r\n' ;;
esac
exit 0
STUB
chmod +x "$RES/wine/bin/wine"
cp "$RES/wine/bin/wine" "$RES/wine/bin/wineserver"
ln -s wine "$RES/wine/lib/wine/x86_64-unix/WoW"
export WINE_STUB_LOG="$WINELOG"

# native font tool: compiled once into build/ (rebuilt when its source changes)
TOOL_SRC="$ROOT/tools/wow-client-fonts.swift"; TOOL="$ROOT/build/wow-client-fonts"
if [ ! -x "$TOOL" ] || [ "$TOOL_SRC" -nt "$TOOL" ]; then
  mkdir -p "$ROOT/build"
  swiftc -swift-version 5 -O -target arm64-apple-macos14.0 -o "$TOOL" "$TOOL_SRC" || { echo "cannot compile wow-client-fonts"; exit 1; }
fi
cp "$TOOL" "$BIN/wow-client-fonts"

# ---------------------------------------------------------------- fake clients
mk_wotlk() {  # complete 3.3.5a client with enUS locale
  local D="$1"; mkdir -p "$D/Data/enUS"
  touch "$D/Wow.exe" "$D/ijl15.dll" "$D/dbghelp.dll" "$D/unicows.dll" "$D/Battle.net.dll" "$D/Scan.dll"
  for m in common common-2 expansion lichking patch patch-2 patch-3; do touch "$D/Data/$m.MPQ"; done
  for m in locale speech base backup expansion-locale expansion-speech lichking-locale lichking-speech; do
    touch "$D/Data/enUS/$m-enUS.MPQ"; done
  touch "$D/Data/enUS/patch-enUS.MPQ" "$D/Data/enUS/patch-enUS-2.MPQ" "$D/Data/enUS/patch-enUS-3.MPQ"
  printf 'set realmlist logon.example.com\r\n' > "$D/Data/enUS/realmlist.wtf"
  echo origdivx > "$D/DivxDecoder.dll"
}
mk_tbc() {  # complete 2.4.3 client with enUS locale
  local D="$1"; mkdir -p "$D/Data/enUS"
  touch "$D/Wow.exe" "$D/ijl15.dll" "$D/unicows.dll"
  for m in common expansion patch; do touch "$D/Data/$m.MPQ"; done
  for m in locale-enUS expansion-locale-enUS patch-enUS speech-enUS; do touch "$D/Data/enUS/$m.MPQ"; done
  printf 'set realmlist logon.example.com\r\n' > "$D/Data/enUS/realmlist.wtf"
}
mk_vanilla() {  # complete 1.12 client (no locale folder, root realmlist)
  local D="$1"; mkdir -p "$D/Data" "$D/WDB"
  touch "$D/Wow.exe" "$D/ijl15.dll" "$D/unicows.dll"
  for m in dbc interface model texture; do touch "$D/Data/$m.MPQ"; done
  printf 'set realmlist logon.example.com\r\n' > "$D/realmlist.wtf"
}
mk_custom() {  # Sirus-style 3.3.5a client: run.exe entrypoint, no Wow.exe
  local D="$1"; mk_wotlk "$D"
  mv "$D/Wow.exe" "$D/run.exe"
  rm -f "$D/Scan.dll"          # custom clients do not always ship the full set
}
mk_wotlk_ru() {  # same build, ruRU locale
  local D="$1"; mk_wotlk "$D"
  mv "$D/Data/enUS" "$D/Data/ruRU"
  for f in "$D/Data/ruRU/"*enUS*; do
    mv "$f" "$(echo "$f" | sed s/enUS/ruRU/g)"; done
  echo ru-exe > "$D/Wow.exe"
  cp "$ROOT/tests/fixtures/locale-ruRU.MPQ" "$D/Data/ruRU/locale-ruRU.MPQ"
}
mk_wotlk   "$TMP/client-wotlk"
mk_wotlk_ru "$TMP/client-wotlk-ru"
mk_tbc     "$TMP/client-tbc"
mk_vanilla "$TMP/client-vanilla"

reset_conf() { printf 'AUTO_RES=1\nCHAT_CP=\n' > "$RES/launcher.conf"; }

# ============================================================ version detection
section "wow-game-version"
assert_eq "$("$BIN/wow-game-version" "$TMP/client-wotlk")"   "3.3.5a" "wotlk fingerprint"
assert_eq "$("$BIN/wow-game-version" "$TMP/client-tbc")"     "2.4.3"  "tbc fingerprint"
assert_eq "$("$BIN/wow-game-version" "$TMP/client-vanilla")" "1.12"   "vanilla fingerprint"
mkdir -p "$TMP/client-junk/Data"; touch "$TMP/client-junk/Wow.exe"
assert_eq "$("$BIN/wow-game-version" "$TMP/client-junk" || true)" "unknown" "unknown fingerprint"

# ============================================================ install: rejections
section "wow-install-client rejections (nothing changed)"
OUT="$("$BIN/wow-install-client" "$TMP/nonexistent" 2>&1)"
assert_contains "$OUT" "not a WoW client" "missing client rejected"
OUT="$("$BIN/wow-install-client" "$TMP/client-junk" 2>&1)"
assert_contains "$OUT" "unrecognized client version" "unknown version rejected"
rm "$TMP/client-tbc/Data/expansion.MPQ"; mkdir -p "$TMP/client-tbc2"; cp -R "$TMP/client-tbc/" "$TMP/client-tbc2/"; touch "$TMP/client-tbc/Data/expansion.MPQ"
mkdir -p "$TMP/client-nl/Data"; touch "$TMP/client-nl/Wow.exe" "$TMP/client-nl/Data/common.MPQ" "$TMP/client-nl/Data/expansion.MPQ" "$TMP/client-nl/Data/patch.MPQ"
OUT="$("$BIN/wow-install-client" "$TMP/client-nl" 2>&1)"
assert_contains "$OUT" "no locale folder" "tbc without locale rejected"
rm "$TMP/client-vanilla/Data/texture.MPQ"
OUT="$("$BIN/wow-install-client" "$TMP/client-vanilla" 2>&1)"
assert_contains "$OUT" "incomplete 1.12 client" "incomplete vanilla rejected"
touch "$TMP/client-vanilla/Data/texture.MPQ"
assert_eq "$(ls "$RES/games" | wc -l | tr -d ' ')" "0" "games dir untouched by rejections"

# ============================================================ install: wotlk
section "install 3.3.5a"
# kit references for the Divx fast path
cp "$TMP/client-wotlk/DivxDecoder.dll" "$RES/patch-kit/DivxDecoder.dll.3.3.5a.orig"
echo patcheddivx > "$RES/patch-kit/DivxDecoder.dll.3.3.5a.patched"
OUT="$("$BIN/wow-install-client" "$TMP/client-wotlk" 2>&1)"
assert_contains "$OUT" "detected client version: 3.3.5a" "version detected"
assert_contains "$OUT" "game installed (3.3.5a)" "install completed"
G="$RES/games/main"
assert_contains "$OUT" "patch level: all" "PATCHES defaults to all"
assert_eq "$(cat "$G/mods/libSiliconPatch.dll")" "sil-lk" "libSiliconPatch installed by default"
assert_eq "$(cat "$G/dlls.txt")" "$(printf 'mods/winerosetta.dll\nmods/libSiliconPatch.dll')" "wotlk dlls.txt (both mods by default)"
assert_eq "$(cat "$G/DivxDecoder.dll")" "patcheddivx" "DivxDecoder patched from kit"
assert_eq "$(cat "$G/DivxDecoder.dll.bak")" "origdivx" "DivxDecoder backup kept"
assert_nofile "$G/vanilla-tweaks.exe"
CONF="$(cat "$RES/launcher.conf")"
assert_contains "$CONF" "GAME_VERSION=3.3.5a" "GAME_VERSION recorded"
assert_contains "$CONF" "AUTO_RES=1" "AUTO_RES reset"
assert_contains "$(cat "$G/WTF/Config.wtf")" "videoOptionsVersion" "wotlk-only cvars seeded"
assert_contains "$(cat "$G/WTF/Config.wtf")" 'SET gxResolution "3456x2234"' "resolution auto-matched at install"

# ============================================================ verify: wotlk
section "verify 3.3.5a"
OUT="$("$BIN/wow-verify-game" 2>&1)"
assert_contains "$OUT" "RESULT: OK — all checks passed" "wotlk verify clean"
assert_eq "$(echo "$OUT" | grep -c '^PROGRESS ')" "43" "wotlk step count"
assert_eq "$(echo "$OUT" | awk '/^PROGRESS/ {print $3}' | sort -u)" "43" "wotlk TOTAL matches"
rm "$G/Data/lichking.MPQ"
OUT="$("$BIN/wow-verify-game" 2>&1)"
assert_contains "$OUT" "REINSTALL" "missing MPQ -> REINSTALL"
touch "$G/Data/lichking.MPQ"
echo corrupted > "$G/d3d9.dll"
OUT="$("$BIN/wow-verify-game" 2>&1)"
assert_contains "$OUT" "CANFIX" "corrupt d3d9 -> CANFIX"
OUT="$("$BIN/wow-verify-game" --fix 2>&1)"
assert_contains "$OUT" "RESULT: OK" "--fix repairs"
assert_eq "$(cat "$G/d3d9.dll")" "d3d9" "d3d9 restored from kit"

# ============================================================ PATCHES levels
section "PATCHES levels (all | no-silicon | winerosetta | none)"
OUT="$("$BIN/wow-verify-game" 2>&1)"
assert_contains "$OUT" "RESULT: OK" "default level (all) verifies clean"

echo 'PATCHES=no-silicon' >> "$RES/launcher.conf"
OUT="$("$BIN/wow-verify-game" 2>&1)"
assert_contains "$OUT" "CANFIX" "no-silicon with libSiliconPatch listed -> CANFIX"
OUT="$("$BIN/wow-verify-game" --fix 2>&1)"
assert_contains "$OUT" "RESULT: OK" "--fix drops the libSiliconPatch entry"
assert_contains "$OUT" "ok: libSiliconPatch off (patch level: no-silicon)" "verify names the level"
assert_eq "$(cat "$G/dlls.txt")" "mods/winerosetta.dll" "no-silicon dlls.txt"
assert_eq "$(echo "$OUT" | grep -c '^PROGRESS ')" "43" "no-silicon keeps the step count"

# winerosetta: the mod loader stays, the cosmetic icon patch is reverted
printf 'origexe\n' > "$G/Wow.exe.icon-backup"; printf 'iconexe\n' > "$G/Wow.exe"
sed -i '' 's/^PATCHES=.*/PATCHES=winerosetta/' "$RES/launcher.conf"
OUT="$("$BIN/wow-verify-game" 2>&1)"
assert_contains "$OUT" "CANFIX" "winerosetta level with an icon-patched exe -> CANFIX"
OUT="$("$BIN/wow-verify-game" --fix 2>&1)"
assert_contains "$OUT" "RESULT: OK" "--fix reverts the icon patch"
assert_eq "$(cat "$G/Wow.exe")" "origexe" "Wow.exe restored from the backup"
assert_eq "$(cat "$G/dlls.txt")" "mods/winerosetta.dll" "winerosetta level keeps the DLL"
assert_eq "$(cat "$G/DivxDecoder.dll")" "patcheddivx" "winerosetta level keeps the mod loader"
assert_eq "$(echo "$OUT" | grep -c '^PROGRESS ')" "43" "winerosetta level keeps the step count"

# none: the client goes back to exactly what it shipped
sed -i '' 's/^PATCHES=.*/PATCHES=none/' "$RES/launcher.conf"
OUT="$("$BIN/wow-verify-game" 2>&1)"
assert_contains "$OUT" "CANFIX" "none with the loader in place -> CANFIX"
OUT="$("$BIN/wow-verify-game" --fix 2>&1)"
assert_contains "$OUT" "RESULT: OK" "--fix strips every client patch"
assert_eq "$(cat "$G/DivxDecoder.dll")" "origdivx" "DivxDecoder restored from the backup"
assert_nofile "$G/dlls.txt"
assert_contains "$OUT" "ok: winerosetta.dll not loaded (no patches)" "winerosetta reported inert"
assert_eq "$(echo "$OUT" | grep -c '^PROGRESS ')" "43" "none keeps the step count"

# the cosmetic icon patch must converge UP as well as down (kit fast path)
printf 'origexe\n' > "$RES/patch-kit/Wow.exe.orig"
printf 'iconexe\n' > "$RES/patch-kit/Wow.exe.icon-patched"
printf 'origexe\n' > "$G/Wow.exe"; rm -f "$G/Wow.exe.icon-backup"
sed -i '' 's/^PATCHES=.*/PATCHES=all/' "$RES/launcher.conf"
OUT="$("$BIN/wow-verify-game" 2>&1)"
assert_contains "$OUT" "CANFIX" "unpatched icon at level all -> CANFIX"
OUT="$("$BIN/wow-verify-game" --fix 2>&1)"
assert_eq "$(cat "$G/Wow.exe")" "iconexe" "icon patch re-applied moving back up"
assert_eq "$(cat "$G/Wow.exe.icon-backup")" "origexe" "backup written when re-applying"
sed -i '' 's/^PATCHES=.*/PATCHES=winerosetta/' "$RES/launcher.conf"
OUT="$("$BIN/wow-verify-game" --fix 2>&1)"
assert_eq "$(cat "$G/Wow.exe")" "origexe" "and reverted again going down"
rm -f "$RES/patch-kit/Wow.exe.orig" "$RES/patch-kit/Wow.exe.icon-patched" "$G/Wow.exe.icon-backup"
: > "$G/Wow.exe"
sed -i '' 's/^PATCHES=.*/PATCHES=none/' "$RES/launcher.conf"

# with no original copy anywhere, "no patches" must not be claimed as verified
mv "$G/DivxDecoder.dll.bak" "$TMP/divx.bak.keep"
mv "$RES/patch-kit/DivxDecoder.dll.3.3.5a.orig" "$TMP/divx.orig.keep"
printf 'patcheddivx\n' > "$G/DivxDecoder.dll"
OUT="$("$BIN/wow-verify-game" 2>&1)"
assert_contains "$OUT" "ok: DivxDecoder.dll never patched by the launcher" "unverifiable DivxDecoder states only what is true"
assert_eq "$(echo "$OUT" | grep -c '^WARN:')" "0" "no unactionable warnings at level none"
mv "$TMP/divx.bak.keep" "$G/DivxDecoder.dll.bak"
mv "$TMP/divx.orig.keep" "$RES/patch-kit/DivxDecoder.dll.3.3.5a.orig"
OUT="$("$BIN/wow-verify-game" --fix 2>&1)"
assert_eq "$(cat "$G/DivxDecoder.dll")" "origdivx" "restored once the backup is back"

# a reinstall at PATCHES=none must leave the client unpatched too
OUT="$("$BIN/wow-install-client" "$TMP/client-wotlk" 2>&1)"
assert_contains "$OUT" "patch level: none" "installer reports the level"
assert_contains "$OUT" "icon patch skipped (patch level: none)" "installer skips the icon patch"
assert_eq "$(cat "$G/DivxDecoder.dll")" "origdivx" "reinstall at none leaves DivxDecoder original"
assert_file "$G/DivxDecoder.dll.bak"
assert_nofile "$G/dlls.txt"
assert_nofile "$G/mods/winerosetta.dll"

# a fresh install at PATCHES=winerosetta: loader in, libSiliconPatch out, icon skipped
sed -i '' '/^PATCHES=/d' "$RES/launcher.conf"; echo 'PATCHES=winerosetta' >> "$RES/launcher.conf"
OUT="$("$BIN/wow-install-client" "$TMP/client-wotlk" 2>&1)"
assert_contains "$OUT" "patch level: winerosetta" "installer reports the winerosetta level"
assert_contains "$OUT" "icon patch skipped (patch level: winerosetta)" "winerosetta install skips the icon"
assert_eq "$(cat "$G/mods/winerosetta.dll")" "winero" "winerosetta level ships the DLL"
assert_nofile "$G/mods/libSiliconPatch.dll"
assert_eq "$(cat "$G/dlls.txt")" "mods/winerosetta.dll" "winerosetta level dlls.txt"
assert_eq "$(cat "$G/DivxDecoder.dll")" "patcheddivx" "winerosetta level patches the loader"
OUT="$("$BIN/wow-verify-game" 2>&1)"
assert_contains "$OUT" "RESULT: OK" "winerosetta level verifies clean"

# older clients ship DivxTac.dll instead of / besides DivxDecoder.dll
printf 'origtac\n' > "$G/DivxTac.dll.bak"; printf 'patchedtac\n' > "$G/DivxTac.dll"
sed -i '' 's/^PATCHES=.*/PATCHES=none/' "$RES/launcher.conf"
OUT="$("$BIN/wow-verify-game" --fix 2>&1)"
assert_eq "$(cat "$G/DivxTac.dll")" "origtac" "DivxTac.dll restored at level none"
rm -f "$G/DivxTac.dll" "$G/DivxTac.dll.bak"

# the pre-2.4 SILICON= toggle still migrates, then the default takes over again
sed -i '' '/^PATCHES=/d' "$RES/launcher.conf"
echo 'SILICON=0' >> "$RES/launcher.conf"
OUT="$("$BIN/wow-verify-game" --fix 2>&1)"
assert_contains "$OUT" "ok: libSiliconPatch off (patch level: no-silicon)" "SILICON=0 migrates to no-silicon"
sed -i '' '/^SILICON=/d' "$RES/launcher.conf"
OUT="$("$BIN/wow-verify-game" --fix 2>&1)"
assert_contains "$OUT" "RESULT: OK" "--fix restores the default level"
assert_eq "$(cat "$G/dlls.txt")" "$(printf 'mods/winerosetta.dll\nmods/libSiliconPatch.dll')" "default (all) restores libSiliconPatch"
assert_eq "$(cat "$G/DivxDecoder.dll")" "patcheddivx" "default restores the mod loader"

# ============================================================ custom entrypoint
section "custom client (run.exe entrypoint)"
mk_custom "$TMP/client-custom"
sed -i '' '/^PATCHES=/d' "$RES/launcher.conf"; echo 'PATCHES=none' >> "$RES/launcher.conf"
OUT="$("$BIN/wow-install-client" "$TMP/client-custom" 2>&1)"
assert_contains "$OUT" "game installed (3.3.5a)" "run.exe client installs"
assert_contains "$OUT" "icon patch skipped (run.exe is a custom client entrypoint)" "no icon patch for run.exe"
assert_file "$G/run.exe"
assert_nofile "$G/Wow.exe"
OUT="$("$BIN/wow-verify-game" 2>&1)"
assert_contains "$OUT" "ok: run.exe present" "verify finds the run.exe entrypoint"
assert_contains "$OUT" "ok: run.exe is a custom client entrypoint" "no build comparison for run.exe"
assert_contains "$OUT" "RESULT: OK" "custom client verifies"
assert_eq "$(echo "$OUT" | grep -c '^WARN:')" "0" "a custom client at level none raises no warnings"
assert_eq "$(echo "$OUT" | grep -c '^FAIL:')" "0" "and no failures for the missing Scan.dll"
assert_eq "$(echo "$OUT" | grep -c '^PROGRESS ')" "43" "step count unchanged for run.exe"
: > "$WINELOG"; "$BIN/wow-launch"; sleep 0.3
assert_contains "$(cat "$WINELOG")" "games/main/run.exe" "launches run.exe"
OUT="$("$BIN/wow-language" list 2>&1 || true)"
assert_contains "$OUT" "custom entrypoint" "language packs refused for a custom client"

# missing support DLLs are only tolerated for custom/unpatched clients
sed -i '' 's/^PATCHES=.*/PATCHES=all/' "$RES/launcher.conf"
OUT="$("$BIN/wow-verify-game" 2>&1)"
assert_contains "$OUT" "ok: run.exe is a custom client entrypoint" "run.exe still recognised at level all"

# restore a stock wotlk client for the remaining sections
sed -i '' '/^PATCHES=/d' "$RES/launcher.conf"
OUT="$("$BIN/wow-install-client" "$TMP/client-wotlk" 2>&1)"
assert_contains "$OUT" "game installed (3.3.5a)" "stock client reinstalled"

# ============================================================ launch: wotlk
section "launch 3.3.5a"
rm -f "$RES/prefix/dosdevices/z:"
: > "$WINELOG"; "$BIN/wow-launch"; sleep 0.3
assert_contains "$(cat "$WINELOG")" "games/main/Wow.exe" "launches Wow.exe"
assert_contains "$(cat "$WINELOG")" "OVR=d3d9=n,b" "DXVK override by default"
assert_contains "$(cat "$WINELOG")" "ROSETTA=$G/rosettax87/rosettax87-shim" "rosettax87 shim engine by default"
[ -L "$RES/prefix/dosdevices/z:" ] && ok || bad "z: drive link not recreated"
printf 'RENDERER=mtld3d\nX87=sidecar\n' >> "$RES/launcher.conf"
: > "$WINELOG"; "$BIN/wow-launch"; sleep 0.3
assert_contains "$(cat "$WINELOG")" "OVR=d3d9=b" "mtld3d override"
assert_contains "$(cat "$WINELOG")" "SIDECAR=$RES/patch-kit/x87sidecar/x87sidecar" "sidecar engine"

# ============================================================ language packs
section "wow-language (3.3.5a)"
OUT="$("$BIN/wow-language" import "$TMP/client-tbc" 2>&1)"
assert_contains "$OUT" "version mismatch" "cross-version import rejected"
OUT="$("$BIN/wow-language" import "$TMP/client-wotlk" 2>&1)"
assert_contains "$OUT" "already the active language" "same-locale import rejected"
OUT="$("$BIN/wow-language" import "$TMP/client-wotlk-ru" 2>&1)"
assert_contains "$OUT" "language pack imported: ruRU" "ruRU pack imported"
assert_file "$G/locales/ruRU/pack/locale-ruRU.MPQ"
assert_eq "$(cat "$G/locales/ruRU/Wow.exe")" "ru-exe" "pack carries its own exe"
assert_contains "$OUT" "Cyrillic fonts extracted and stashed" "ruRU pack yields the fonts"
for f in FRIZQT__.TTF ARIALN.TTF MORPHEUS.TTF skurri.ttf; do assert_file "$RES/patch-kit/fonts-client/$f"; done
"$BIN/wow-client-fonts" check "$RES/patch-kit/fonts-client/"* >/dev/null && ok || bad "stashed fonts not remapped"
assert_file "$G/Fonts/FRIZQT__.TTF"
assert_contains "$("$BIN/wow-language" list)" "* enUS" "list marks active"
mkdir -p "$G/Cache"; touch "$G/Cache/stale.wdb"
ENUS_EXE="$(cat "$G/Wow.exe")"
OUT="$("$BIN/wow-language" switch ruRU 2>&1)"
assert_contains "$OUT" "language switched to ruRU" "switch runs"
assert_file "$G/Data/ruRU/locale-ruRU.MPQ"
assert_nofile "$G/Data/enUS"
assert_eq "$(cat "$G/Wow.exe")" "ru-exe" "active exe swapped"
assert_eq "$(cat "$G/locales/enUS/Wow.exe")" "$ENUS_EXE" "previous exe stashed"
assert_nofile "$G/Cache"
assert_contains "$(grep "SET locale" "$G/WTF/Config.wtf")" 'SET locale "ruRU"' "locale cvar set"
# an icon-patched exe carries its pre-patch original in Wow.exe.icon-backup;
# a language switch must stash THAT (not the patched exe), or PATCHES=winerosetta|none
# would later restore the wrong language's executable
printf 'ru-exe-original\n' > "$G/Wow.exe.icon-backup"
printf 'ru-exe-iconpatched\n' > "$G/Wow.exe"
OUT="$("$BIN/wow-language" switch enUS 2>&1)"
assert_contains "$OUT" "language switched to enUS" "switch back runs"
assert_eq "$(cat "$G/locales/ruRU/Wow.exe")" "ru-exe-original" "switch stashes the unpatched exe"
assert_nofile "$G/Wow.exe.icon-backup"
assert_eq "$(cat "$G/Wow.exe")" "$ENUS_EXE" "enUS exe restored unpatched"
assert_file "$G/Data/enUS/locale-enUS.MPQ"
assert_contains "$(grep "SET locale" "$G/WTF/Config.wtf")" 'SET locale "enUS"' "locale cvar restored"

# ============================================================ Cyrillic fonts
section "wow-client-fonts (native tool)"
mkdir -p "$TMP/fx-enUS/Data/enUS"; cp "$ROOT/tests/fixtures/locale-enUS.MPQ" "$TMP/fx-enUS/Data/enUS/"
OUT="$("$BIN/wow-client-fonts" "$TMP/fx-enUS" "$TMP/fx-out" 2>&1)"; RC=$?
assert_eq "$RC" "1" "enUS fonts rejected (no Cyrillic glyphs)"
assert_contains "$OUT" "no Cyrillic glyphs" "reason printed"
assert_nofile "$TMP/fx-out"
OUT="$("$BIN/wow-client-fonts" "$TMP/client-tbc" "$TMP/fx-out" 2>&1)"; RC=$?
assert_eq "$RC" "1" "empty MPQ rejected"
assert_nofile "$TMP/fx-out"
OUT="$("$BIN/wow-client-fonts" check "$TMP/nonexistent.ttf" 2>&1)"; RC=$?
assert_eq "$RC" "1" "check fails on unreadable font"
OUT="$("$BIN/wow-client-fonts" "$ROOT/tests/fixtures/locale-ruRU.MPQ" "$TMP/fx-out" 2>&1)"; RC=$?
assert_eq "$RC" "0" "a locale MPQ path works directly"
for f in FRIZQT__.TTF ARIALN.TTF MORPHEUS.TTF skurri.ttf; do assert_file "$TMP/fx-out/$f"; done
"$BIN/wow-client-fonts" check "$TMP/fx-out/"* >/dev/null && ok || bad "extracted fixture fonts not remapped"
rm -rf "$TMP/fx-out"

section "install: Cyrillic font flow"
rm -rf "$RES/patch-kit/fonts-client"
printf 'AUTO_RES=1\nCHAT_CP=1251\n' > "$RES/launcher.conf"
OUT="$("$BIN/wow-install-client" "$TMP/client-wotlk" 2>&1)"
assert_contains "$OUT" "NOTE: Cyrillic fonts unavailable" "enUS install without a stash warns"
assert_nofile "$G/Fonts"
OUT="$("$BIN/wow-install-client" "$TMP/client-wotlk-ru" 2>&1)"
assert_contains "$OUT" "Cyrillic fonts extracted from the client and stashed" "ruRU install extracts"
assert_contains "$OUT" "installed Cyrillic input fonts" "ruRU install installs the fonts"
assert_file "$G/Fonts/skurri.ttf"
assert_nofile "$RES/patch-kit/fonts-client.new"
echo junk > "$RES/patch-kit/fonts-client/ARIALN.TTF"      # stale/corrupt stash → refreshed from a ruRU source
OUT="$("$BIN/wow-install-client" "$TMP/client-wotlk-ru" 2>&1)"
assert_contains "$OUT" "extracted from the client and stashed" "stale stash refreshed"
"$BIN/wow-client-fonts" check "$RES/patch-kit/fonts-client/"* >/dev/null && ok || bad "refreshed stash not remapped"
OUT="$("$BIN/wow-install-client" "$TMP/client-wotlk" 2>&1)"
assert_contains "$OUT" "installed Cyrillic input fonts (original client fonts" "enUS install reuses the stash"
assert_file "$G/Fonts/FRIZQT__.TTF"
[ "$(grep -c "extracted" <<< "$OUT")" = 0 ] && ok || bad "enUS install must not re-extract"
reset_conf

# ============================================================ install: tbc
section "install 2.4.3 (replaces wotlk)"
printf 'RENDERER=mtld3d\n' >> "$RES/launcher.conf"
OUT="$("$BIN/wow-install-client" "$TMP/client-tbc" 2>&1)"
assert_contains "$OUT" "game installed (2.4.3)" "install completed"
assert_nofile "$G/mods/libSiliconPatch.dll"
assert_eq "$(cat "$G/dlls.txt")" "mods/winerosetta.dll" "tbc dlls.txt (winerosetta only)"
CONF="$(cat "$RES/launcher.conf")"
assert_contains "$CONF" "GAME_VERSION=2.4.3" "GAME_VERSION replaced"
echo "$CONF" | grep -q "RENDERER=" && bad "RENDERER not reset on install" || ok
grep -q "videoOptionsVersion" "$G/WTF/Config.wtf" && bad "wotlk cvars leaked into tbc config" || ok

section "verify 2.4.3"
OUT="$("$BIN/wow-verify-game" 2>&1)"
assert_contains "$OUT" "RESULT: OK" "tbc verify passes"
assert_eq "$(echo "$OUT" | grep -c '^PROGRESS ')" "29" "tbc step count"
assert_eq "$(echo "$OUT" | awk '/^PROGRESS/ {print $3}' | sort -u)" "29" "tbc TOTAL matches"
assert_contains "$OUT" "ok: libSiliconPatch not used for 2.4.3 clients" "tbc has no libSiliconPatch build"
echo 'PATCHES=none' >> "$RES/launcher.conf"
OUT="$("$BIN/wow-verify-game" --fix 2>&1)"
assert_contains "$OUT" "RESULT: OK" "tbc verifies at level none"
assert_nofile "$G/dlls.txt"
assert_eq "$(echo "$OUT" | grep -c '^PROGRESS ')" "29" "tbc step count holds at level none"
sed -i '' '/^PATCHES=/d' "$RES/launcher.conf"
OUT="$("$BIN/wow-verify-game" --fix 2>&1)"
assert_eq "$(cat "$G/dlls.txt")" "mods/winerosetta.dll" "tbc back to default (no libSiliconPatch build)"

# ============================================================ install: vanilla
section "install 1.12"
OUT="$("$BIN/wow-install-client" "$TMP/client-vanilla" 2>&1)"
assert_contains "$OUT" "game installed (1.12)" "install completed"
assert_eq "$(cat "$G/mods/libSiliconPatch.dll")" "sil-van" "vanilla libSiliconPatch build"
assert_file "$G/vanilla-tweaks.exe"
assert_file "$G/realmlist.wtf"
assert_contains "$(cat "$RES/launcher.conf")" "GAME_VERSION=1.12" "GAME_VERSION recorded"

section "verify 1.12"
OUT="$("$BIN/wow-verify-game" 2>&1)"
assert_contains "$OUT" "RESULT: OK" "vanilla verify passes"
assert_eq "$(echo "$OUT" | grep -c '^PROGRESS ')" "25" "vanilla step count"
assert_eq "$(echo "$OUT" | awk '/^PROGRESS/ {print $3}' | sort -u)" "25" "vanilla TOTAL matches"
echo 'PATCHES=winerosetta' >> "$RES/launcher.conf"
OUT="$("$BIN/wow-verify-game" --fix 2>&1)"
assert_eq "$(cat "$G/dlls.txt")" "mods/winerosetta.dll" "vanilla winerosetta level drops libSiliconPatch"
assert_contains "$OUT" "ok: libSiliconPatch off (patch level: winerosetta)" "vanilla names the level"
sed -i '' '/^PATCHES=/d' "$RES/launcher.conf"
OUT="$("$BIN/wow-verify-game" --fix 2>&1)"
assert_eq "$(cat "$G/mods/libSiliconPatch.dll")" "sil-van" "vanilla default restores libSiliconPatch"

section "no language packs on 1.12"
OUT="$("$BIN/wow-language" list 2>&1)"
assert_contains "$OUT" "1.12 clients have no language packs" "vanilla gate"

section "launch 1.12"
mkdir -p "$G/WDB"; touch "$G/WDB/creaturecache.wdb"
: > "$WINELOG"; "$BIN/wow-launch"; sleep 0.3
assert_nofile "$G/WDB"
assert_contains "$(cat "$WINELOG")" "games/main/Wow.exe" "launches Wow.exe"
touch "$G/WoW_tweaked.exe"
: > "$WINELOG"; "$BIN/wow-launch"; sleep 0.3
assert_contains "$(cat "$WINELOG")" "games/main/WoW_tweaked.exe" "prefers WoW_tweaked.exe"
rm "$G/WoW_tweaked.exe"

# ============================================================ self-install guard
section "self-install guard"
OUT="$("$BIN/wow-install-client" "$G" 2>&1)"
assert_contains "$OUT" "the source is the installed game itself" "guard triggers"
assert_file "$G/Wow.exe"

# ================================================================== summary
echo ""
echo "passed: $PASS, failed: $FAILED"
[ "$FAILED" = 0 ] || exit 1
