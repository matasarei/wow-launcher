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
mk_wotlk   "$TMP/client-wotlk"
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
assert_eq "$(cat "$G/mods/libSiliconPatch.dll")" "sil-lk" "wotlk libSiliconPatch build"
assert_eq "$(cat "$G/dlls.txt")" "$(printf 'mods/winerosetta.dll\nmods/libSiliconPatch.dll')" "wotlk dlls.txt"
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
