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
echo "WINE ARGS: $* | OVR=${WINEDLLOVERRIDES:-} SIDECAR=${X87_SIDECAR_PATH:-} ROSETTA=${ROSETTA_X87_PATH:-} LOADER=${WINELOADER:-} SPATIAL=${WOWSILICON_SPATIAL_AUDIO_MODE:-unset} NORM=${WOWSILICON_NORMALIZE_AUDIO:-unset} FOLLOW=${WOWSILICON_FOLLOW_SYSTEM_OUTPUT:-unset} ACTL=${WOWSILICON_SPATIAL_AUDIO_CONTROL:-} NCTL=${WOWSILICON_NORMALIZE_AUDIO_CONTROL:-} HOME=${HOME:-}" >> "$WINE_STUB_LOG"
case "$*" in
  *"reg query"*RetinaMode*)  [ -n "${WOW_TEST_RETINA-Y}" ] \
                               && printf '    RetinaMode    REG_SZ    %s\r\n' "${WOW_TEST_RETINA-Y}" ;;
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
  # -Onone matches build.sh — see the note there; at -O this file is
  # miscompiled by the Swift 6.1.2 toolchain and the tool segfaults.
  swiftc -swift-version 5 -Onone -target arm64-apple-macos14.0 -o "$TOOL" "$TOOL_SRC" || { echo "cannot compile wow-client-fonts"; exit 1; }
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
  echo origtac > "$D/DivxTac.dll"        # pre-wotlk clients carry the older name
  for m in common expansion patch; do touch "$D/Data/$m.MPQ"; done
  for m in locale-enUS expansion-locale-enUS patch-enUS speech-enUS; do touch "$D/Data/enUS/$m.MPQ"; done
  printf 'set realmlist logon.example.com\r\n' > "$D/Data/enUS/realmlist.wtf"
}
mk_vanilla() {  # complete 1.12 client (no locale folder, root realmlist)
  local D="$1"; mkdir -p "$D/Data" "$D/WDB"
  touch "$D/Wow.exe" "$D/ijl15.dll" "$D/unicows.dll"
  echo origtac > "$D/DivxTac.dll"
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

# A minimal but genuinely parseable PE: MZ, e_lfanew at 0x3C pointing at 0x40,
# the PE signature, the machine word — and, when a version is given, a UTF-16LE
# VS_VERSIONINFO blob of the shape the profile script reads out of Wow.exe.
# By default it is reachable through a one-entry section table naming .rsrc,
# which is the path the profile takes on a real client; pass "nosections" for a
# header the section walk cannot use, so the whole-file fallback gets exercised.
#
#   0..59 DOS header  60 e_lfanew=64  64 'PE\0\0'  68 machine  70 nsec
#   72..83 unused  84 SizeOfOptionalHeader=0  86 characteristics
#   88 section table (40 bytes)  128 the version blob
mk_pe() {  # mk_pe <path> <x86|x64> [<"3, 3, 5, 12340">] [nosections]
  { printf 'MZ'; head -c 58 /dev/zero
    printf '\100\000\000\000'                       # e_lfanew = 0x40
    printf 'PE\000\000'
    case "$2" in x64) printf '\144\206' ;; *) printf '\114\001' ;; esac
    if [ -n "${3:-}" ] && [ "${4:-}" != nosections ]; then
      printf '\001\000'; head -c 12 /dev/zero          # NumberOfSections = 1
      printf '\000\000\000\000'                      # no optional header
      printf '.rsrc\000\000\000'                      # section name
      head -c 8 /dev/zero                               # VirtualSize, VirtualAddress
      printf '\000\020\000\000'                      # SizeOfRawData  = 4096
      printf '\200\000\000\000'                      # PointerToRawData = 128
      head -c 16 /dev/zero
    else
      head -c 32 /dev/zero                              # NumberOfSections = 0
    fi
    if [ -n "${3:-}" ]; then
      printf 'FileVersion' | iconv -t UTF-16LE
      head -c 6 /dev/zero
      printf '%s' "$3" | iconv -t UTF-16LE
      head -c 8 /dev/zero
    fi
  } > "$1"
}
mk_post_wotlk() {  # Cataclysm/MoP-shaped: still MPQ, but expansion2/world
  local D="$1"; mkdir -p "$D/Data/enUS"
  mk_pe "$D/Wow.exe" x86 "4, 3, 4, 15595"
  for m in art expansion1 expansion2 expansion3 world world2; do touch "$D/Data/$m.MPQ"; done
  touch "$D/Data/enUS/locale-enUS.MPQ"
  echo origdivx > "$D/DivxDecoder.dll"
}
mk_casc() {  # Legion-shaped: 64-bit entrypoint, CASC storage, no MPQ at all
  local D="$1"; mkdir -p "$D/Data/data"
  mk_pe "$D/Wow.exe" x64 "7, 3, 5, 26972"
  touch "$D/.build.info" "$D/Data/data/0000000001.idx"
}

# ============================================================ client profile
section "wow-client-profile"
prof() { "$BIN/wow-client-profile" "$1" | grep -E "^$2=" | cut -d= -f2-; }

# the classic three keep today's answers even with an unreadable (empty) exe
assert_eq "$(prof "$TMP/client-wotlk" FAMILY)"      "wotlk"   "wotlk family"
assert_eq "$(prof "$TMP/client-wotlk" VERSION)"     "3.3.5a"  "wotlk version label"
assert_eq "$(prof "$TMP/client-wotlk" BUILD)"       ""        "no build from an unreadable exe"
assert_eq "$(prof "$TMP/client-wotlk" CONFIDENCE)"  "likely"  "layout alone is 'likely'"
assert_eq "$(prof "$TMP/client-wotlk" CAP_SILICON)" "wotlk"   "unknown build still gets libSiliconPatch"
assert_eq "$(prof "$TMP/client-wotlk" LEVELS)" "all no-silicon winerosetta none" "wotlk offers every level"
assert_eq "$(prof "$TMP/client-tbc" FAMILY)"        "tbc"     "tbc family"
assert_eq "$(prof "$TMP/client-tbc" CAP_SILICON)"   ""        "no libSiliconPatch build for tbc"
assert_eq "$(prof "$TMP/client-tbc" LEVELS)" "no-silicon winerosetta none" "tbc has no 'all'"
cp -R "$TMP/client-tbc" "$TMP/client-tbc-nodivx"; rm -f "$TMP/client-tbc-nodivx/DivxTac.dll"
assert_eq "$(prof "$TMP/client-tbc-nodivx" CAP_LOADER)" "0" "no Divx DLL means no mod loader"
assert_eq "$(prof "$TMP/client-tbc-nodivx" LEVELS)" "none" "and then nothing can be applied at all"
assert_eq "$(prof "$TMP/client-vanilla" FAMILY)"    "vanilla" "vanilla family"
assert_eq "$(prof "$TMP/client-vanilla" CAP_SILICON)" "vanilla" "vanilla libSiliconPatch"
assert_eq "$(prof "$TMP/client-vanilla" CAP_TWEAKS)" "1"      "vanilla-tweaks offered"
assert_eq "$(prof "$TMP/client-vanilla" LEVELS)" "all no-silicon winerosetta none" "vanilla offers every level"
# libSiliconPatch is loaded by the Divx mod loader, so it cannot outlive it
cp -R "$TMP/client-vanilla" "$TMP/client-van-nodivx"; rm -f "$TMP/client-van-nodivx/DivxTac.dll"
assert_eq "$(prof "$TMP/client-van-nodivx" CAP_SILICON)" "" "no loader means no libSiliconPatch"

# the version resource is what turns a family into a build
cp -R "$TMP/client-wotlk" "$TMP/client-12340"
mk_pe "$TMP/client-12340/Wow.exe" x86 "3, 3, 5, 12340"
assert_eq "$(prof "$TMP/client-12340" BUILD)"       "12340"   "build read from the exe"
assert_eq "$(prof "$TMP/client-12340" CONFIDENCE)"  "exact"   "resource + layout agree"
assert_eq "$(prof "$TMP/client-12340" VERSION)"     "3.3.5a"  "canonical label kept"
assert_eq "$(prof "$TMP/client-12340" CAP_SILICON)" "wotlk"   "12340 gets the hooks"
# the version blob is normally reached through the .rsrc section table; a header
# the section walk cannot use has to fall back to scanning the whole file
cp -R "$TMP/client-wotlk" "$TMP/client-nosect"
mk_pe "$TMP/client-nosect/Wow.exe" x86 "3, 3, 5, 12340" nosections
assert_eq "$(prof "$TMP/client-nosect" BUILD)"      "12340"   "build read without a section table"
assert_eq "$(prof "$TMP/client-nosect" CONFIDENCE)" "exact"   "and it is just as exact"

cp -R "$TMP/client-wotlk" "$TMP/client-309"
mk_pe "$TMP/client-309/Wow.exe" x86 "3, 0, 9, 9551"
assert_eq "$(prof "$TMP/client-309" BUILD)"         "9551"    "pre-3.3.5 build read"
assert_eq "$(prof "$TMP/client-309" VERSION)"       "3.0.9"   "declared version wins over the label"
assert_eq "$(prof "$TMP/client-309" CAP_SILICON)"   ""        "12340 hooks refused on 3.0.9"
assert_eq "$(prof "$TMP/client-309" LEVELS)" "no-silicon winerosetta none" "and 'all' is not offered"

# post-WotLK MPQ era: loader and DXVK apply, libSiliconPatch never does
mk_post_wotlk "$TMP/client-cata"
assert_eq "$(prof "$TMP/client-cata" FAMILY)"       "post-wotlk" "cata family"
assert_eq "$(prof "$TMP/client-cata" VERSION)"      "4.3.4"   "cata version from the resource"
assert_eq "$(prof "$TMP/client-cata" CAP_SILICON)"  ""        "no libSiliconPatch past wotlk"
assert_eq "$(prof "$TMP/client-cata" CAP_LOADER)"   "1"       "cata mod loader (Divx present)"
assert_eq "$(prof "$TMP/client-cata" CAP_CVARS)"    "1"       "cata still uses gx* cvars"
assert_eq "$(prof "$TMP/client-cata" CAP_LANGPACK)" "0"       "no language packs past tbc"

# 64-bit CASC client: nothing in the kit can load into it
mk_casc "$TMP/client-casc"
assert_eq "$(prof "$TMP/client-casc" FAMILY)"       "casc"    "casc family"
assert_eq "$(prof "$TMP/client-casc" ARCH)"         "x64"     "64-bit entrypoint detected"
assert_eq "$(prof "$TMP/client-casc" DATA)"         "casc"    "casc storage"
assert_eq "$(prof "$TMP/client-casc" CONFIDENCE)"   "guess"   "casc is a guess"
assert_eq "$(prof "$TMP/client-casc" CAP_LOADER)"   "0"       "no 32-bit mod loader"
assert_eq "$(prof "$TMP/client-casc" CAP_DXVK)"     "0"       "no 32-bit DXVK"
assert_eq "$(prof "$TMP/client-casc" CAP_CVARS)"    "0"       "no gx* cvar seeding"
assert_eq "$(prof "$TMP/client-casc" LEVELS)"       "none"    "only 'no patches' is offered"

# an unrecognised folder is an answer, not an error
mkdir -p "$TMP/client-generic/Data"; mk_pe "$TMP/client-generic/Wow.exe" x86
assert_eq "$(prof "$TMP/client-generic" FAMILY)"    "generic" "generic family"
assert_eq "$(prof "$TMP/client-generic" VERSION)"   "unknown" "generic version"
assert_eq "$(prof "$TMP/client-generic" CONFIDENCE)" "guess"  "generic is a guess"
"$BIN/wow-client-profile" "$TMP/client-generic" >/dev/null 2>&1 && ok || bad "profile must exit 0 on a generic client"

# the requested level is remembered; the effective one is clamped to the client
printf 'AUTO_RES=1\nPATCHES=all\n' > "$RES/launcher.conf"
assert_eq "$(prof "$TMP/client-casc" PATCHES_REQUESTED)" "all"  "request survives"
assert_eq "$(prof "$TMP/client-casc" PATCHES)"      "none"    "clamped to what the client can take"
assert_eq "$(prof "$TMP/client-cata" PATCHES)"      "no-silicon" "clamped to the best cata level"
assert_eq "$(prof "$TMP/client-wotlk" PATCHES)"     "all"     "wotlk is not clamped"
printf 'AUTO_RES=1\nPATCHES=winerosetta\n' > "$RES/launcher.conf"
assert_eq "$(prof "$TMP/client-wotlk" PATCHES)"     "winerosetta" "a lower request is never raised"
printf 'AUTO_RES=1\nSILICON=0\n' > "$RES/launcher.conf"
assert_eq "$(prof "$TMP/client-wotlk" PATCHES)"     "no-silicon" "pre-2.4 SILICON=0 still migrates"
reset_conf

# entrypoints
assert_eq "$("$BIN/wow-client-profile" --exe "$TMP/client-wotlk")" "Wow.exe" "--exe fast path"
cp -R "$TMP/client-wotlk" "$TMP/client-runexe"
mv "$TMP/client-runexe/Wow.exe" "$TMP/client-runexe/run.exe"
assert_eq "$(prof "$TMP/client-runexe" EXE)"        "run.exe" "run.exe entrypoint"
assert_eq "$(prof "$TMP/client-runexe" CAP_LANGPACK)" "0"     "no language packs for a custom entrypoint"
assert_eq "$(prof "$TMP/client-runexe" CAP_ICON)"   "0"       "no icon patch for a custom entrypoint"
cp -R "$TMP/client-wotlk" "$TMP/client-oddexe"
mv "$TMP/client-oddexe/Wow.exe" "$TMP/client-oddexe/Azeroth.exe"
head -c 4096 /dev/zero > "$TMP/client-oddexe/WowError.exe"
assert_eq "$(prof "$TMP/client-oddexe" EXE)"        "Azeroth.exe" "largest non-helper exe wins"
# The output is a line-oriented protocol callers parse with grep, so every key
# must appear exactly once whatever the folder holds — including a client whose
# only executable is named something that looks like a profile line itself.
cp -R "$TMP/client-wotlk" "$TMP/client-nlexe"
rm -f "$TMP/client-nlexe/Wow.exe"
head -c 4096 /dev/zero > "$TMP/client-nlexe/$(printf 'a\nCAP_SILICON=wotlk')-x.exe" 2>/dev/null || true
OUT="$("$BIN/wow-client-profile" "$TMP/client-nlexe")"
assert_eq "$(echo "$OUT" | grep -c '^CAP_SILICON=')" "1" "one CAP_SILICON line, always"
assert_eq "$(echo "$OUT" | grep -cE '^[A-Z_]+=')" "$(echo "$OUT" | grep -c .)" \
  "every line of the profile is a key=value pair"

# the icon patch keeps its level offered on both sides of the diff
cp -R "$TMP/client-wotlk" "$TMP/client-icon"
rm -f "$TMP/client-icon/DivxDecoder.dll"          # loader off, so only the icon can offer no-silicon
printf 'iconexe' > "$TMP/client-icon/Wow.exe"
IN_MD5="$(md5 -q "$TMP/client-icon/Wow.exe")"
touch "$RES/patch-kit/wow-icon-$IN_MD5-deadbeef.bsdiff"
assert_eq "$(prof "$TMP/client-icon" CAP_ICON)"     "1"       "icon diff matches the stock exe"
assert_eq "$(prof "$TMP/client-icon" LEVELS)" "no-silicon none" "the icon alone offers no-silicon"
printf 'patchediconexe' > "$TMP/client-icon/Wow.exe"
OUT_MD5="$(md5 -q "$TMP/client-icon/Wow.exe")"
mv "$RES/patch-kit/wow-icon-$IN_MD5-deadbeef.bsdiff" "$RES/patch-kit/wow-icon-cafe-$OUT_MD5.bsdiff"
assert_eq "$(prof "$TMP/client-icon" CAP_ICON)"     "1"       "an already-patched exe still counts"
rm -f "$RES/patch-kit/wow-icon-"*.bsdiff

# ============================================================ version detection
section "wow-game-version"
assert_eq "$("$BIN/wow-game-version" "$TMP/client-wotlk")"   "3.3.5a" "wotlk fingerprint"
assert_eq "$("$BIN/wow-game-version" "$TMP/client-tbc")"     "2.4.3"  "tbc fingerprint"
assert_eq "$("$BIN/wow-game-version" "$TMP/client-vanilla")" "1.12"   "vanilla fingerprint"
mkdir -p "$TMP/client-junk/Data"; touch "$TMP/client-junk/Wow.exe"
assert_eq "$("$BIN/wow-game-version" "$TMP/client-junk" || true)" "unknown" "unknown fingerprint"
assert_eq "$("$BIN/wow-game-version" "$TMP/client-cata")"    "4.3.4"  "post-wotlk reports its declared version"
"$BIN/wow-game-version" "$TMP/client-junk" >/dev/null 2>&1 && bad "unknown must still exit non-zero" || ok

# ============================================================ install: rejections
section "wow-install-client rejections (nothing changed)"
OUT="$("$BIN/wow-install-client" "$TMP/nonexistent" 2>&1)"
assert_contains "$OUT" "not a WoW client" "missing client rejected"
rm "$TMP/client-tbc/Data/expansion.MPQ"; mkdir -p "$TMP/client-tbc2"; cp -R "$TMP/client-tbc/" "$TMP/client-tbc2/"; touch "$TMP/client-tbc/Data/expansion.MPQ"
mkdir -p "$TMP/client-nl/Data"; touch "$TMP/client-nl/Wow.exe" "$TMP/client-nl/Data/common.MPQ" "$TMP/client-nl/Data/expansion.MPQ" "$TMP/client-nl/Data/patch.MPQ"
OUT="$("$BIN/wow-install-client" "$TMP/client-nl" 2>&1)"
assert_contains "$OUT" "no locale folder" "tbc without locale rejected"
rm "$TMP/client-vanilla/Data/texture.MPQ"
OUT="$("$BIN/wow-install-client" "$TMP/client-vanilla" 2>&1)"
assert_contains "$OUT" "incomplete 1.12 client" "incomplete vanilla rejected"
touch "$TMP/client-vanilla/Data/texture.MPQ"
assert_eq "$(ls "$RES/games" | wc -l | tr -d ' ')" "0" "games dir untouched by rejections"

# ...but a client we simply do not recognise is installed as it is
OUT="$("$BIN/wow-install-client" "$TMP/client-junk" 2>&1)"
assert_contains "$OUT" "not one the launcher recognises" "unknown client is noted, not refused"
assert_contains "$OUT" "game installed (unknown)" "unknown client installs"
assert_contains "$(cat "$RES/launcher.conf")" "GAME_FAMILY=generic" "family recorded"
assert_contains "$(cat "$RES/launcher.conf")" "AUTO_RES=0" "no cvar seeding for an unknown client"
assert_nofile "$RES/games/main/WTF/Config.wtf"
OUT="$("$BIN/wow-verify-game" 2>&1)"
assert_contains "$OUT" "RESULT: OK" "an unknown client verifies clean"
assert_eq "$(echo "$OUT" | grep -c '^FAIL:')" "0" "and raises no failures"
assert_eq "$(echo "$OUT" | awk '/^PROGRESS/ {print $3}' | sort -u)" \
          "$(echo "$OUT" | grep -c '^PROGRESS ')" "computed TOTAL matches the steps run"
rm -rf "$RES/games"/*; reset_conf

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
# the copy reports progress for the install pane, and ends at 100 %
LAST="$(echo "$OUT" | grep '^COPY ' | tail -1)"
assert_eq "$(echo "$LAST" | awk '{print ($2 == $3 && $2 > 0) ? "done" : $0}')" "done" "the last COPY line says all of it"

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

# an unrecognised level falls back to the default rather than erroring — this is
# what a conf left over from a pre-rename build (PATCHES=warden) now hits, and it
# must land on `all`, not on a half-applied state
for BAD in warden garbage ""; do
  sed -i '' '/^PATCHES=/d' "$RES/launcher.conf"; echo "PATCHES=$BAD" >> "$RES/launcher.conf"
  OUT="$("$BIN/wow-verify-game" --fix 2>&1)"
  assert_contains "$OUT" "RESULT: OK" "unknown level '$BAD' verifies without erroring"
  assert_eq "$(cat "$G/dlls.txt")" "$(printf 'mods/winerosetta.dll\nmods/libSiliconPatch.dll')" "unknown level '$BAD' falls back to all"
done
OUT="$("$BIN/wow-install-client" "$TMP/client-wotlk" 2>&1)"
assert_contains "$OUT" "patch level: all" "installer falls back to all for an unknown level"

# patch_level() and game_exe() live in wow-client-profile and nowhere else —
# the copies these scripts used to carry are what the profile replaced
for f in wow-install-client wow-verify-game wow-launch wow-language; do
  grep -qE '^(patch_level|game_exe)\(\)' "$BIN/$f" \
    && bad "$f carries its own copy of patch_level()/game_exe() again" || ok
done

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

# both entrypoints present: Wow.exe wins. This is the case a Sirus player creates
# by copying run.exe to Wow.exe to satisfy a launcher that hardcodes the name.
cp -R "$TMP/client-wotlk" "$TMP/client-dual"
printf 'wowexe\n' > "$TMP/client-dual/Wow.exe"
printf 'runexe\n' > "$TMP/client-dual/run.exe"
OUT="$("$BIN/wow-install-client" "$TMP/client-dual" 2>&1)"
assert_contains "$OUT" "game installed (3.3.5a)" "client carrying both exes installs"
assert_eq "$(cat "$G/run.exe")" "runexe" "run.exe is copied in as well"
OUT="$("$BIN/wow-verify-game" 2>&1)"
assert_contains "$OUT" "ok: Wow.exe present" "Wow.exe wins over run.exe in verify"
assert_eq "$(echo "$OUT" | grep -c 'run.exe is a custom client entrypoint')" "0" "not treated as a custom client"
: > "$WINELOG"; "$BIN/wow-launch"; sleep 0.3
assert_contains "$(cat "$WINELOG")" "games/main/Wow.exe" "Wow.exe wins over run.exe at launch"
OUT="$("$BIN/wow-language" list 2>&1 || true)"
assert_eq "$(echo "$OUT" | grep -c 'custom entrypoint')" "0" "language packs stay available"

# neither entrypoint: rejected before the installed game is touched
mkdir -p "$TMP/client-noexe/Data"
for m in common common-2 expansion lichking patch patch-2; do touch "$TMP/client-noexe/Data/$m.MPQ"; done
OUT="$("$BIN/wow-install-client" "$TMP/client-noexe" 2>&1 || true)"
assert_contains "$OUT" "no game executable" "a client with neither entrypoint is rejected"
assert_eq "$(cat "$G/Wow.exe")" "wowexe" "the installed game survived the rejection"


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
# audio (runtime r15 winecoreaudio contract): spatial mixer and normalizer on unless
# the conf says 0 (absent = on, like AUTO_RES), device following left to the driver's
# default, control files pinned inside the bundle
assert_contains "$(cat "$WINELOG")" "SPATIAL=fixed" "spatial audio on by default (no key)"
assert_contains "$(cat "$WINELOG")" "NORM=1" "normalize audio on by default (no key)"
assert_contains "$(cat "$WINELOG")" "FOLLOW=unset" "device following left at the driver default"
assert_contains "$(cat "$WINELOG")" "ACTL=$RES/audio/spatial-audio-mode" "spatial control file pinned inside the bundle"
assert_contains "$(cat "$WINELOG")" "NCTL=$RES/audio/normalize-audio" "normalize control file pinned inside the bundle"
printf 'SPATIAL_AUDIO=0\nNORMALIZE_AUDIO=0\n' >> "$RES/launcher.conf"
: > "$WINELOG"; WOWSILICON_SPATIAL_AUDIO_MODE=garbage "$BIN/wow-launch"; sleep 0.3
assert_contains "$(cat "$WINELOG")" "SPATIAL=off" "SPATIAL_AUDIO=0 turns the spatial mixer off (and overrides a stale shell value)"
assert_contains "$(cat "$WINELOG")" "NORM=0" "NORMALIZE_AUDIO=0 turns the normalizer off"
sed -i '' 's/^SPATIAL_AUDIO=.*/SPATIAL_AUDIO=1/; s/^NORMALIZE_AUDIO=.*/NORMALIZE_AUDIO=yes/' "$RES/launcher.conf"
: > "$WINELOG"; "$BIN/wow-launch"; sleep 0.3
assert_contains "$(cat "$WINELOG")" "SPATIAL=fixed" "SPATIAL_AUDIO=1 is on"
assert_contains "$(cat "$WINELOG")" "NORM=0" "a value other than 1 or absent is off (AUTO_RES idiom)"
sed -i '' '/^SPATIAL_AUDIO=/d; /^NORMALIZE_AUDIO=/d' "$RES/launcher.conf"

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
cp "$TMP/client-tbc/DivxTac.dll" "$RES/patch-kit/DivxTac.dll.2.4.3.orig"
echo patchedtac > "$RES/patch-kit/DivxTac.dll.2.4.3.patched"
printf 'RENDERER=mtld3d\n' >> "$RES/launcher.conf"
OUT="$("$BIN/wow-install-client" "$TMP/client-tbc" 2>&1)"
assert_contains "$OUT" "game installed (2.4.3)" "install completed"
assert_nofile "$G/mods/libSiliconPatch.dll"
assert_eq "$(cat "$G/dlls.txt")" "mods/winerosetta.dll" "tbc dlls.txt (winerosetta only)"
assert_eq "$(cat "$G/DivxTac.dll")" "patchedtac" "the older DivxTac.dll is the loader hook"
assert_eq "$(cat "$G/DivxTac.dll.bak")" "origtac" "DivxTac backup kept"
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
cp "$TMP/client-vanilla/DivxTac.dll" "$RES/patch-kit/DivxTac.dll.1.12.orig"
echo patchedtac > "$RES/patch-kit/DivxTac.dll.1.12.patched"
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

# ============================================================ other clients
section "install: clients past WotLK"
reset_conf
OUT="$("$BIN/wow-install-client" "$TMP/client-cata" 2>&1)"
assert_contains "$OUT" "game installed (4.3.4)" "a Cataclysm-shaped client installs"
assert_contains "$OUT" "patch level: no-silicon (asked for 'all'" "the level is clamped, and says so"
assert_file "$G/d3d9.dll"
assert_file "$G/libDllLdr.dll"
assert_file "$G/mods/winerosetta.dll"
assert_nofile "$G/mods/libSiliconPatch.dll"
assert_eq "$(cat "$G/dlls.txt")" "mods/winerosetta.dll" "no libSiliconPatch past wotlk"
CONF="$(cat "$RES/launcher.conf")"
assert_contains "$CONF" "GAME_FAMILY=post-wotlk" "family recorded"
assert_contains "$CONF" "GAME_BUILD=15595" "build recorded"
assert_contains "$CONF" "AUTO_RES=1" "MPQ-era clients still get cvar handling"
OUT="$("$BIN/wow-verify-game" 2>&1)"
assert_contains "$OUT" "RESULT: OK" "a Cataclysm-shaped client verifies"
assert_eq "$(echo "$OUT" | grep -c '^FAIL:')" "0" "with no failures"
assert_contains "$OUT" "ok: libSiliconPatch not used for 4.3.4 clients" "and says why there are no hooks"

section "install: a 64-bit client"
: > "$WINELOG"
export WOW_TEST_RETINA=""      # a fresh prefix has never had RetinaMode written
OUT="$("$BIN/wow-install-client" "$TMP/client-casc" 2>&1)"
assert_contains "$OUT" "game installed (7.3.5)" "a Legion-shaped client installs"
assert_contains "$OUT" "patch level: none (asked for 'all'" "clamped all the way down"
assert_nofile "$G/d3d9.dll"
assert_nofile "$G/libDllLdr.dll"
assert_nofile "$G/mods/winerosetta.dll"
assert_nofile "$G/dlls.txt"
assert_nofile "$G/WTF/Config.wtf"
assert_contains "$(cat "$RES/launcher.conf")" "AUTO_RES=0" "no resolution matching for a 64-bit client"
# RetinaMode is a wine-prefix setting, not a client cvar, and verify checks it for
# every client — skipping the whole of `wow-settings auto` here would leave a fresh
# wrapper failing its own verify on a Retina Mac
assert_contains "$(cat "$WINELOG")" "reg add HKCU\\Software\\Wine\\Mac Driver /v RetinaMode" \
  "retina mode is still matched for a client with no cvar handling"
unset WOW_TEST_RETINA
OUT="$("$BIN/wow-verify-game" 2>&1)"
assert_contains "$OUT" "RESULT: OK" "a 64-bit client verifies clean"
assert_eq "$(echo "$OUT" | grep -c '^FAIL:')" "0" "and raises no failures"
assert_contains "$OUT" "ok: DXVK not applicable (this client is 64-bit)" "verify says why DXVK is absent"
assert_contains "$OUT" "ok: no realmlist.wtf" "and does not demand a realmlist"
assert_eq "$(echo "$OUT" | awk '/^PROGRESS/ {print $3}' | sort -u)" \
          "$(echo "$OUT" | grep -c '^PROGRESS ')" "computed TOTAL matches the steps run"
: > "$WINELOG"; "$BIN/wow-launch"; sleep 0.3
assert_contains "$(cat "$WINELOG")" "games/main/Wow.exe" "a 64-bit client still launches"
OUT="$("$BIN/wow-language" list 2>&1 || true)"
assert_contains "$OUT" "only available for 3.3.5a and 2.4.3" "no language packs for it"

# the request is remembered across a client swap, so going back restores it
assert_eq "$("$BIN/wow-client-profile" | grep '^PATCHES=' | cut -d= -f2)" "none" "clamped while installed"
OUT="$("$BIN/wow-install-client" "$TMP/client-wotlk" 2>&1)"
assert_contains "$OUT" "patch level: all" "swapping back to wotlk restores the full level"
assert_eq "$(cat "$G/mods/libSiliconPatch.dll")" "sil-lk" "and libSiliconPatch with it"

section "install: a repack with its own executable name"
OUT="$("$BIN/wow-install-client" "$TMP/client-oddexe" 2>&1)"
assert_contains "$OUT" "game installed (3.3.5a)" "a repack with a renamed exe installs"
assert_contains "$(cat "$RES/launcher.conf")" "GAME_EXE=Azeroth.exe" "the entrypoint is recorded for the GUI"
assert_contains "$OUT" "icon patch skipped (Azeroth.exe is a custom client entrypoint)" "no icon patch for it"
OUT="$("$BIN/wow-verify-game" 2>&1)"
assert_contains "$OUT" "ok: Azeroth.exe present" "verify follows the same entrypoint"
assert_contains "$OUT" "RESULT: OK" "and the repack verifies"
: > "$WINELOG"; "$BIN/wow-launch"; sleep 0.3
assert_contains "$(cat "$WINELOG")" "games/main/Azeroth.exe" "and launches it"
"$BIN/wow-install-client" "$TMP/client-wotlk" >/dev/null 2>&1   # restore for what follows


# ============================================================ self-install guard
section "self-install guard"
OUT="$("$BIN/wow-install-client" "$G" 2>&1)"
assert_contains "$OUT" "the source is the installed game itself" "guard triggers"
assert_file "$G/Wow.exe"

# ============================================================ leftover wineserver
# Wine creates sockets inside wineserver, and a wineserver from an earlier
# session belongs to no launcher — macOS then blocks the game's LAN traffic.
section "a fresh wineserver per session"
reset_conf; "$BIN/wow-install-client" "$TMP/client-wotlk" >/dev/null 2>&1
: > "$WINELOG"; "$BIN/wow-launch"; sleep 0.3
assert_contains "$(cat "$WINELOG")" "WINE ARGS: -k" "launch stops a leftover wineserver first"
( exec -a "$G/Wow.exe" sleep 3 ) &                    # a game from this copy is running
FAKE=$!; sleep 0.2
: > "$WINELOG"; "$BIN/wow-launch"; sleep 0.3
assert_eq "$(grep -c 'WINE ARGS: -k |' "$WINELOG")" "0" "a running game's wineserver is left alone"
kill "$FAKE" 2>/dev/null; wait "$FAKE" 2>/dev/null
( exec -a "Z:$(printf '%s' "$G" | tr '/' '\\')\\Wow.exe" sleep 3 ) &   # Wine's own Z:\ form
FAKE=$!; sleep 0.2
: > "$WINELOG"; "$BIN/wow-launch"; sleep 0.3
assert_eq "$(grep -c 'WINE ARGS: -k |' "$WINELOG")" "0" "a running game in Wine's Z:\\ form is recognised too"
kill "$FAKE" 2>/dev/null; wait "$FAKE" 2>/dev/null

# ============================================================ Rosetta missing
# The real probe passes here (the stub wine is a shell script, not x86_64), so
# the failing path is exercised by swapping the probe itself — the suite must
# not depend on whether the machine running it happens to have Rosetta.
section "Rosetta 2 missing"
cat > "$BIN/wow-check-rosetta" <<'STUB'
#!/bin/bash
echo "ROSETTA: not installed — run: sudo softwareupdate --install-rosetta --agree-to-license"
exit 1
STUB
chmod +x "$BIN/wow-check-rosetta"

: > "$WINELOG"; OUT="$("$BIN/wow-launch" 2>&1)"; sleep 0.3
assert_contains "$OUT" "cannot start without Rosetta 2" "launch refuses"
assert_contains "$(cat "$RES/logs/last-launch.log")" "ROSETTA: not installed" "the reason lands in the log"
assert_eq "$(cat "$WINELOG")" "" "wine is never invoked"

OUT="$("$BIN/wow-verify-game" 2>&1)"
assert_contains "$OUT" "ROSETTA" "verify emits the marker"
assert_contains "$OUT" "WARN: retina mode cannot be checked without Rosetta 2" "retina warns"
assert_contains "$OUT" "WARN: the fast-exit fix cannot be checked without Rosetta 2" "fast-exit warns"
assert_eq "$(echo "$OUT" | grep -c '^CANFIX$')" "0" "no CANFIX to offer a fix that cannot work"
assert_eq "$(echo "$OUT" | grep -c '^PROGRESS ')" "43" "step count unchanged without Rosetta"
assert_eq "$(echo "$OUT" | awk '/^PROGRESS/ {print $3}' | sort -u)" "43" "TOTAL unchanged without Rosetta"

reset_conf
mv "$RES/patch-kit/DivxDecoder.dll.3.3.5a.patched" "$TMP/kit-divx.patched"   # the path that needs wine
OUT="$("$BIN/wow-install-client" "$TMP/client-wotlk" 2>&1)"
assert_contains "$OUT" "game installed" "the client still installs"
assert_contains "$OUT" "Rosetta 2 is missing" "and says the DLL was not patched"
mv "$TMP/kit-divx.patched" "$RES/patch-kit/DivxDecoder.dll.3.3.5a.patched"   # leave the kit as found

install -m 755 "$ROOT/scripts/wow-check-rosetta" "$BIN/wow-check-rosetta"   # real probe back
OUT="$("$BIN/wow-verify-game" 2>&1)"
assert_eq "$(echo "$OUT" | grep -c '^ROSETTA$')" "0" "no marker once the probe passes again"
# the build calls it before anything is installed, so the loader comes as an argument
"$BIN/wow-check-rosetta" "$RES/wine/bin/wine" && ok || bad "the probe accepts a loader path"

# ================================================================== wow-copy
section "wow-copy"
OUT="$("$BIN/wow-copy" "$TMP/client-wotlk" "$TMP/copy-ok" 2>&1)"; RC=$?
assert_eq "$RC" "0" "a clean copy exits 0"
diff -r "$TMP/client-wotlk" "$TMP/copy-ok" >/dev/null && ok || bad "the copy differs from the source"
assert_eq "$(echo "$OUT" | grep -vc '^COPY ')" "0" "it prints nothing but COPY lines"
"$BIN/wow-copy" "$TMP/nonexistent" "$TMP/copy-none" >/dev/null 2>&1 && bad "a missing source passes" || ok
# the name on a progress line is the file ditto is reading: a stand-in ditto
# holds one open past the first tick, then hands over to the real one
mkdir -p "$TMP/slow-ditto"
cat > "$TMP/slow-ditto/ditto" <<'STUB'
#!/bin/bash
exec 3<"$1/Data/common.MPQ"; sleep 1.5; exec /usr/bin/ditto "$@"
STUB
chmod +x "$TMP/slow-ditto/ditto"
OUT="$(PATH="$TMP/slow-ditto:$PATH" "$BIN/wow-copy" "$TMP/client-wotlk" "$TMP/copy-slow" 2>&1)"
assert_contains "$OUT" "Data/common.MPQ" "a progress line names the file being read, relative to SRC"
diff -r "$TMP/client-wotlk" "$TMP/copy-slow" >/dev/null && ok || bad "the slow copy differs from the source"
# a backslash is a legal macOS folder-name character, and must not read as an escape
cp -R "$TMP/client-wotlk" "$TMP/back\\slash"
OUT="$(PATH="$TMP/slow-ditto:$PATH" "$BIN/wow-copy" "$TMP/back\\slash" "$TMP/copy-bs" 2>&1)"
assert_contains "$OUT" "Data/common.MPQ" "the name is found under a source path with a backslash"
# ditto runs in the background, out of reach of the installer's set -e: its
# failure has to come back through wow-copy's exit status, or a half-copied
# client gets patched and reported as installed
if [ "$(id -u)" != 0 ]; then   # root reads a mode-000 file anyway
  cp -R "$TMP/client-wotlk" "$TMP/client-unreadable"
  chmod 000 "$TMP/client-unreadable/Data/common.MPQ"
  "$BIN/wow-copy" "$TMP/client-unreadable" "$TMP/copy-bad" >/dev/null 2>&1 \
    && bad "a failed ditto passes" || ok
  reset_conf
  OUT="$("$BIN/wow-install-client" "$TMP/client-unreadable" 2>&1)"
  assert_eq "$(echo "$OUT" | grep -c 'game installed')" "0" "a failed copy is not reported as installed"
  assert_eq "$(echo "$OUT" | grep -c 'applying patch kit')" "0" "and nothing gets patched"
  chmod 644 "$TMP/client-unreadable/Data/common.MPQ"
fi

# ============================================================ wine's HOME (#12)
# This wine creates $HOME/Wine in every process it starts and links the prefix's
# user profile there, so every wine call must carry a HOME inside the bundle.
section "wine HOME stays inside the bundle"
mkdir -p "$RES/prefix/drive_c/users"
U="${USER:-$(id -un)}"; UL="$RES/prefix/drive_c/users/$U"
ln -sfn "$TMP/old-home/Wine" "$UL"            # what an older wrapper, or a moved one, has
OUT="$("$BIN/wow-wine-home")"
assert_eq "$OUT" "$RES/home" "wow-wine-home prints the bundle's home"
assert_eq "$(readlink "$UL")" "../../../home/Wine" "the profile link is re-pointed, relative"
[ -d "$RES/home/Wine" ] && ok || bad "home/Wine is created"
rm -f "$UL"; "$BIN/wow-wine-home" >/dev/null
assert_eq "$(readlink "$UL")" "../../../home/Wine" "a missing profile link is created"
rm -f "$UL"; mkdir "$UL"; : > "$UL/keep"; "$BIN/wow-wine-home" >/dev/null
assert_file "$UL/keep"                        # a real folder is somebody's profile
rm -rf "$UL"
# no wine call reaches the caller's HOME — run everything with a throwaway one
FAKEHOME="$TMP/fake-home"; mkdir -p "$FAKEHOME"
: > "$WINELOG"
HOME="$FAKEHOME" "$BIN/wow-settings" show >/dev/null 2>&1
HOME="$FAKEHOME" "$BIN/wow-verify-game" >/dev/null 2>&1
reset_conf; HOME="$FAKEHOME" "$BIN/wow-install-client" "$TMP/client-wotlk" >/dev/null 2>&1
HOME="$FAKEHOME" "$BIN/wow-launch" >/dev/null 2>&1; sleep 0.3
assert_eq "$([ -s "$WINELOG" ] && echo yes)" "yes" "the scripts ran wine at all"
assert_eq "$(grep -vc "HOME=$RES/home\$" "$WINELOG")" "0" "every wine call carries the bundle's HOME"
assert_nofile "$FAKEHOME/Wine"
# the installer's Russian-layout check must still read the caller's own prefs,
# not the bundle's empty home — or Cyrillic input stops switching itself on
mkdir -p "$FAKEHOME/Library/Preferences"
python3 -c 'import plistlib,sys; plistlib.dump({"AppleEnabledInputSources":[{"InputSourceKind":"Keyboard Layout","KeyboardLayout Name":"Russian"}]}, open(sys.argv[1],"wb"))' \
  "$FAKEHOME/Library/Preferences/com.apple.HIToolbox.plist"
printf 'AUTO_RES=1\n' > "$RES/launcher.conf"   # no CHAT_CP line: detection is allowed to run
HOME="$FAKEHOME" "$BIN/wow-install-client" "$TMP/client-wotlk" >/dev/null 2>&1
assert_contains "$(cat "$RES/launcher.conf")" "CHAT_CP=1251" "the Russian layout is found in the user's own prefs"
reset_conf
# a helper that cannot run leaves the caller's HOME in place, never an empty one
chmod -x "$BIN/wow-wine-home"; : > "$WINELOG"
HOME="$FAKEHOME" "$BIN/wow-settings" show >/dev/null 2>&1
chmod +x "$BIN/wow-wine-home"
assert_eq "$(grep -vc "HOME=$FAKEHOME\$" "$WINELOG")" "0" "a failed helper falls back to the caller's HOME"

# a script added later that runs wine without it would bring ~/Wine back, and
# nothing above would notice: every script naming the loader must ask for the home
for f in "$ROOT"/scripts/wow-*; do
  n="$(basename "$f")"
  [ "$n" = wow-check-rosetta ] && continue   # inspects the loader (lipo, arch), never runs it
  grep -v '^[[:space:]]*#' "$f" | grep -qE 'wine/bin/|"\$LOADER"' || continue
  grep -q 'wow-wine-home' "$f" && ok || bad "$n runs wine without wow-wine-home (~/Wine comes back)"
done

# ============================================================ Retina chosen by hand
# The display here is retina, so every auto-match used to switch RetinaMode back
# on right after the user turned it off: in the Display pane (retina off, then
# auto), at every Play (AUTO_RES=1), and in Verify, which called it a failure.
section "Retina chosen by hand survives the auto-match"
reset_conf; "$BIN/wow-install-client" "$TMP/client-wotlk" >/dev/null 2>&1
G="$RES/games/main"
retina_writes() { grep -c "RetinaMode /t REG_SZ /d $1" "$WINELOG"; }
: > "$WINELOG"; OUT="$(WOW_TEST_RETINA=Y "$BIN/wow-settings" retina off)"
assert_contains "$(cat "$RES/launcher.conf")" "RETINA=off" "retina off is remembered"
: > "$WINELOG"; OUT="$(WOW_TEST_RETINA=N "$BIN/wow-settings" auto)"
assert_eq "$(retina_writes Y)" "0" "auto keeps a hand-set retina off"
assert_contains "$(cat "$G/WTF/Config.wtf")" 'SET gxResolution "1728x1117"' "and matches the resolution to it (points)"
: > "$WINELOG"; WOW_TEST_RETINA=N "$BIN/wow-launch" >/dev/null 2>&1; sleep 0.3
assert_eq "$(retina_writes Y)" "0" "Play keeps it too"
OUT="$(WOW_TEST_RETINA=N "$BIN/wow-verify-game" 2>&1)"
assert_contains "$OUT" "ok: retina mode off (set by hand)" "verify accepts it"
assert_eq "$(echo "$OUT" | grep -c '^FAIL: re')" "0" "no resolution or retina failure over it"
# the detect button: forget the choice, fit the screen again
: > "$WINELOG"; OUT="$(WOW_TEST_RETINA=N "$BIN/wow-settings" auto reset)"
assert_eq "$(grep -c '^RETINA=' "$RES/launcher.conf")" "0" "auto reset forgets the choice"
assert_eq "$(retina_writes Y)" "1" "and turns retina back on for a retina display"
assert_contains "$(cat "$G/WTF/Config.wtf")" 'SET gxResolution "3456x2234"' "at native pixels"
WOW_TEST_RETINA=Y "$BIN/wow-settings" retina on >/dev/null
assert_contains "$(cat "$RES/launcher.conf")" "RETINA=on" "retina on is remembered as well"
WOW_TEST_RETINA=Y "$BIN/wow-settings" retina auto >/dev/null
assert_eq "$(grep -c '^RETINA=' "$RES/launcher.conf")" "0" "retina auto forgets it"
WOW_TEST_RETINA=Y "$BIN/wow-settings" retina off >/dev/null
"$BIN/wow-install-client" "$TMP/client-wotlk" >/dev/null 2>&1
assert_eq "$(grep -c '^RETINA=' "$RES/launcher.conf")" "0" "a fresh install resets it with the other display settings"
reset_conf

# ======================================================= install from a previous app
section "install from a previous app"
mk_plist() {  # mk_plist <app> <bundle id> <version>
  mkdir -p "$1/Contents"
  printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>%s</string>
<key>CFBundleShortVersionString</key><string>%s</string>
</dict></plist>\n' "$2" "$3" > "$1/Contents/Info.plist"
}
state() { ls -R "$RES/games"; cat "$RES/launcher.conf"; }
tree_sums() { (cd "$1" && find . -type f -exec md5 -r {} + | sort); }
# the previous app: a copy of this wrapper (a space in the name on purpose)
# with a 3.3.5a installed, the player's choices set, and a pack imported
reset_conf; rm -rf "$RES/games"/*
OLD="$TMP/Old Launcher.app"; OLDRES="$OLD/Contents/Resources"
cp -R "$APP" "$OLD"; mk_plist "$OLD" io.github.matasarei.wow-launcher 2.7
"$OLD/Contents/Resources/bin/wow-install-client" "$TMP/client-wotlk" >/dev/null 2>&1
printf 'PATCHES=no-silicon\nRENDERER=mtld3d\nCLOSE_ON_PLAY=1\nRETINA=off\nDISPLAY_RECT=1,2,3,4\nGAME_DISPLAY=Old Screen\n' >> "$OLDRES/launcher.conf"
sed -i '' 's/^SET gxWindow .*/SET gxWindow "0"/' "$OLDRES/games/main/WTF/Config.wtf"
echo 'SET myCvar "42"' >> "$OLDRES/games/main/WTF/Config.wtf"
mkdir -p "$OLDRES/games/main/locales/deDE/pack"; echo de-exe > "$OLDRES/games/main/locales/deDE/Wow.exe"
mkdir -p "$OLDRES/games/main/Interface/AddOns/MyAddon"
# this wrapper starts as a fresh one: no self-populated kit references
mkdir -p "$TMP/kitrefs"; mv "$RES/patch-kit/"DivxDecoder.dll.* "$TMP/kitrefs/"
mk_plist "$APP" io.github.matasarei.wow-launcher 2.8
BEFORE_OLD="$(tree_sums "$OLD")"

# refused, and nothing here changes
BEFORE="$(state)"
mk_plist "$TMP/Other.app" com.example.other 5.0
OUT="$("$BIN/wow-install-client" "$TMP/Other.app" 2>&1)"
assert_contains "$OUT" "not a WoW Launcher app: Other" "an unrelated app is refused"
mkdir -p "$TMP/Bare.app"
OUT="$("$BIN/wow-install-client" "$TMP/Bare.app" 2>&1)"
assert_contains "$OUT" "not a WoW Launcher app: Bare" "an app without Info.plist is refused"
mk_plist "$TMP/Ancient.app" local.wow335.singleapp 2.0
OUT="$("$BIN/wow-install-client" "$TMP/Ancient.app" 2>&1)"
assert_contains "$OUT" "Ancient 2.0 is too old to import from" "1.0/2.0 (old bundle id) is refused"
for ver in 2.0 1.9 2 garbage ""; do
  mk_plist "$TMP/Old2.app" io.github.matasarei.wow-launcher "$ver"
  OUT="$("$BIN/wow-install-client" "$TMP/Old2.app" 2>&1)"
  assert_contains "$OUT" "too old to import from" "version '$ver' is refused"
done
OUT="$("$BIN/wow-install-client" "$APP" 2>&1)"
assert_contains "$OUT" "this launcher itself" "this app itself is refused"
mk_plist "$TMP/Empty.app" io.github.matasarei.wow-launcher 2.8
mkdir -p "$TMP/Empty.app/Contents/Resources/games"
OUT="$("$BIN/wow-install-client" "$TMP/Empty.app" 2>&1)"
assert_contains "$OUT" "Empty has no game installed" "an app without a game is refused"
fake_proc() {  # fake_proc <command line> — started, and listed by ps, before it returns
  (exec -a "$1" sleep 30) & RUNNING=$!
  local L   # listed first: a grep reading ps live would find its own command line
  for _ in $(seq 50); do L="$(ps -axww -o command=)"; printf '%s\n' "$L" | grep -qF -- "$1" && return; sleep 0.1; done
}
fake_proc "$OLD/Contents/MacOS/WoW Launcher"
OUT="$("$BIN/wow-install-client" "$OLD" 2>&1)"
# --updating: an update imports from the launcher that runs it, so that
# launcher may be running — only its game may not (see wow-update)
UPD="$("$BIN/wow-install-client" --updating "$OLD" 2>&1)"
kill "$RUNNING" 2>/dev/null; wait "$RUNNING" 2>/dev/null
assert_contains "$OUT" "Old Launcher is still running" "a running previous app is refused"
assert_contains "$UPD" "game installed (3.3.5a)" "--updating imports while the previous launcher runs"
rm -rf "$RES/games"/* "$RES/patch-kit/"DivxDecoder.dll.*; reset_conf
fake_proc "$OLD/Contents/Resources/wine/bin/wineserver"
UPD="$("$BIN/wow-install-client" --updating "$OLD" 2>&1)"
kill "$RUNNING" 2>/dev/null; wait "$RUNNING" 2>/dev/null
assert_contains "$UPD" "game from Old Launcher is still running" "--updating still refuses a running game"
fake_proc "Z:$(echo "$OLD" | tr / '\\')\\Contents\\Resources\\games\\main\\Wow.exe"
OUT="$("$BIN/wow-install-client" "$OLD" 2>&1)"
kill "$RUNNING" 2>/dev/null; wait "$RUNNING" 2>/dev/null
assert_contains "$OUT" "Old Launcher is still running" "its game under Wine (Z:\\ path) counts as running"
assert_eq "$(state)" "$BEFORE" "refusals change nothing here"

# accepted: 2.10 is newer than 2.1 (numbers, not text)
mk_plist "$OLD" io.github.matasarei.wow-launcher 2.10
BEFORE_OLD="$(tree_sums "$OLD")"
: > "$WINELOG"
OUT="$(WOW_TEST_RETINA=N "$BIN/wow-install-client" "$OLD/" 2>&1)"
G="$RES/games/main"
assert_contains "$OUT" "importing from Old Launcher 2.10" "the previous app is accepted"
assert_contains "$OUT" "game installed (3.3.5a), imported from Old Launcher 2.10" "and its game installed"
assert_eq "$(tree_sums "$OLD")" "$BEFORE_OLD" "the previous app is left byte-for-byte as it was"
CONF="$(cat "$RES/launcher.conf")"
for kv in PATCHES=no-silicon RENDERER=mtld3d CLOSE_ON_PLAY=1 RETINA=off GAME_VERSION=3.3.5a GAME_FAMILY=wotlk; do
  assert_contains "$CONF" "$kv" "$kv after the move"
done
assert_eq "$(grep -cE '^(DISPLAY_RECT|GAME_DISPLAY)=' "$RES/launcher.conf")" "0" "the old screen setup stays behind"
assert_contains "$(cat "$G/WTF/Config.wtf")" 'SET myCvar "42"' "the player's cvars survive"
assert_contains "$(cat "$G/WTF/Config.wtf")" 'SET gxWindow "0"' "and are not re-seeded"
assert_contains "$(cat "$G/WTF/Config.wtf")" 'SET gxResolution "1728x1117"' "resolution fits this screen at the kept Retina choice"
assert_file "$G/locales/deDE/Wow.exe"
[ -d "$G/Interface/AddOns/MyAddon" ] && ok || bad "addons came along"
assert_eq "$(cat "$RES/patch-kit/DivxDecoder.dll.3.3.5a.patched")" "patcheddivx" "kit reference imported"
assert_contains "$OUT" "kit reference imported: DivxDecoder.dll.3.3.5a.orig" "and said so"
assert_eq "$(cat "$G/DivxDecoder.dll")" "patcheddivx" "Divx stays patched, not patched again"
assert_eq "$(cat "$G/dlls.txt")" "mods/winerosetta.dll" "mod set follows the carried patch level"
assert_eq "$(grep -c 'PatchDivx' "$WINELOG")" "0" "no live Divx patch was run"
OUT="$(WOW_TEST_RETINA=N "$BIN/wow-verify-game" 2>&1)"
assert_contains "$OUT" "RESULT: OK — all checks passed" "the moved game verifies clean"
assert_eq "$(echo "$OUT" | grep -c '^PROGRESS ')" "43" "all 43 checks"
# a kit reference this wrapper already has is never overwritten
echo mine > "$RES/patch-kit/DivxDecoder.dll.3.3.5a.orig"
OUT="$(WOW_TEST_RETINA=N "$BIN/wow-install-client" "$OLD" 2>&1)"
assert_eq "$(cat "$RES/patch-kit/DivxDecoder.dll.3.3.5a.orig")" "mine" "existing kit reference kept"
# a pre-2.4 app: SILICON=0 is its patch level
sed -i '' '/^PATCHES=/d; s/^AUTO_RES=.*/AUTO_RES=0/' "$OLDRES/launcher.conf"; echo 'SILICON=0' >> "$OLDRES/launcher.conf"
mk_plist "$OLD" io.github.matasarei.wow-launcher 2.3
OUT="$(WOW_TEST_RETINA=N "$BIN/wow-install-client" "$OLD" 2>&1)"
assert_contains "$OUT" "patch level: no-silicon" "SILICON=0 from a 2.3 app means no-silicon"
assert_contains "$(cat "$RES/launcher.conf")" "SILICON=0" "and is carried"
assert_contains "$(cat "$RES/launcher.conf")" "AUTO_RES=0" "resolution managed by hand stays so"
# an old app that never managed to patch Divx (installed without Rosetta):
# no .bak, no kit references anywhere — the move patches it as an install would
mk_plist "$OLD" io.github.matasarei.wow-launcher 2.7
cp "$TMP/client-wotlk/DivxDecoder.dll" "$OLDRES/games/main/DivxDecoder.dll"
rm -f "$OLDRES/games/main/DivxDecoder.dll.bak" "$OLDRES/patch-kit/"DivxDecoder.dll.* "$RES/patch-kit/"DivxDecoder.dll.*
: > "$WINELOG"
OUT="$(WOW_TEST_RETINA=N "$BIN/wow-install-client" "$OLD" 2>&1)"
assert_contains "$(cat "$WINELOG")" "PatchDivxDecoder" "an unpatched Divx from a previous app is patched live"
rm -f "$APP/Contents/Info.plist" "$RES/patch-kit/"DivxDecoder.dll.*
mv "$TMP/kitrefs/"* "$RES/patch-kit/"; rm -rf "$RES/games"/*; reset_conf

# ============================================================== wow-update check
section "wow-update check"
# a release, as the GitHub API answers it — served from a file:// URL
mk_release() {  # mk_release <file> <tag> [<asset name>]
  local A="${3-WoW-$2.zip}" ASSETS=""
  [ -n "$A" ] && ASSETS="{\"name\":\"$A\",\"size\":123,\"digest\":\"sha256:dead\",
      \"browser_download_url\":\"file://$TMP/rel/$A\"}"
  printf '{"tag_name":"%s","html_url":"https://example.invalid/%s","assets":[%s]}\n' \
    "$2" "$2" "$ASSETS" > "$1"
}
mkdir -p "$TMP/rel"
mk_release "$TMP/rel/newer.json"  v2.10
mk_release "$TMP/rel/same.json"   v2.9
mk_release "$TMP/rel/older.json"  v2.8
mk_release "$TMP/rel/noasset.json" v2.10 ""
mk_plist "$APP" io.github.matasarei.wow-launcher 2.9
check() {  # check <fixture> [--force] — one check against that release
  local F="$1"; shift
  WOW_UPDATE_API="file://$TMP/rel/$F" "$BIN/wow-update" check "$@" 2>&1
}
reset_conf
OUT="$(check newer.json)"
assert_contains "$OUT" "RESULT: UPDATE" "a newer release is an update"
assert_contains "$OUT" "REPLACEABLE=1" "a copy in a writable folder can replace itself"
assert_contains "$OUT" "LATEST=2.10" "the version comes from the tag"
assert_contains "$OUT" "CURRENT=2.9" "and the current one from Info.plist"
assert_contains "$OUT" "ASSET=file://$TMP/rel/WoW-v2.10.zip" "the WoW-v*.zip asset is picked"
assert_contains "$OUT" "SIZE=123" "with its size"
assert_contains "$OUT" "DIGEST=sha256:dead" "and its checksum"
assert_contains "$OUT" "PAGE=https://example.invalid/v2.10" "the release page comes along"
assert_contains "$(cat "$RES/launcher.conf")" "UPDATE_CHECKED=" "a completed check is remembered"
# 2.10 > 2.9 as numbers — as text it is not
reset_conf; assert_contains "$(check same.json)" "RESULT: CURRENT" "the same version is not an update"
reset_conf; assert_contains "$(check older.json)" "RESULT: CURRENT" "an older release is not an update"
reset_conf; assert_contains "$(check noasset.json)" "RESULT: CURRENT" "a release without a WoW-v*.zip is not offered"
# a release older than the floor cannot install itself, whatever this app is
mk_plist "$APP" io.github.matasarei.wow-launcher 2.1
reset_conf; assert_contains "$(check older.json)" "RESULT: CURRENT" "a pre-2.9 release is never offered"
mk_plist "$APP" io.github.matasarei.wow-launcher 2.9
# the settings, and --force ignoring each of them
reset_conf; echo 'UPDATE_CHECK=0' >> "$RES/launcher.conf"
assert_contains "$(check newer.json)" "RESULT: OFF" "automatic checking can be turned off"
assert_contains "$(check newer.json --force)" "RESULT: UPDATE" "the button checks anyway"
reset_conf; printf 'UPDATE_CHECKED=%s\n' "$(date +%s)" >> "$RES/launcher.conf"
assert_contains "$(check newer.json)" "RESULT: TOO-SOON" "checked again within the week"
assert_contains "$(check newer.json --force)" "RESULT: UPDATE" "the button ignores the interval"
reset_conf; printf 'UPDATE_CHECKED=%s\n' "$(( $(date +%s) - 604801 ))" >> "$RES/launcher.conf"
assert_contains "$(check newer.json)" "RESULT: UPDATE" "a week later it checks again"
reset_conf; echo 'UPDATE_SKIP=2.10' >> "$RES/launcher.conf"
assert_contains "$(check newer.json)" "RESULT: SKIPPED" "a skipped version stays quiet"
assert_contains "$(check newer.json --force)" "RESULT: UPDATE" "the button offers it anyway"
reset_conf; echo 'UPDATE_SKIP=2.9' >> "$RES/launcher.conf"
assert_contains "$(check newer.json)" "RESULT: UPDATE" "a newer version than the skipped one is offered"
# a folder that cannot be written: the update has to be done by hand
reset_conf; chmod a-w "$TMP"
OUT="$(check newer.json)"
chmod u+w "$TMP"
assert_contains "$OUT" "REPLACEABLE=0" "a copy that cannot be replaced says so"
assert_contains "$OUT" "RESULT: UPDATE" "and still reports the new version"
# GitHub unreachable: say so, and do not start the week
reset_conf
OUT="$(check nothing-here.json)"
assert_contains "$OUT" "RESULT: UNREACHABLE" "an unreachable API is reported"
assert_eq "$(grep -c '^UPDATE_CHECKED=' "$RES/launcher.conf")" "0" "and is not remembered as a check"
rm -f "$APP/Contents/Info.plist"; reset_conf

# ============================================================== wow-update apply
section "wow-update apply"
# a release zip: a wrapper of its own, sealed ad-hoc the way a real one is
mk_release_app() {  # mk_release_app <dir> <version> [<bundle id>]
  local D="$1/WoW.app"
  rm -rf "$1"; mkdir -p "$D/Contents/MacOS" "$D/Contents/Resources/bin"
  mk_plist "$D" "${3:-io.github.matasarei.wow-launcher}" "$2"
  printf '#!/bin/bash\nexit 0\n' > "$D/Contents/MacOS/WoW Launcher"
  chmod +x "$D/Contents/MacOS/WoW Launcher"
  cp "$ROOT/scripts/wow-"* "$D/Contents/Resources/bin/"
  printf 'AUTO_RES=1\n' > "$D/Contents/Resources/launcher.conf"
  codesign --force --deep --sign - "$D" 2>/dev/null
}
mk_release_zip() {  # mk_release_zip <zip> <version> [<bundle id>]
  mk_release_app "$TMP/relsrc" "$2" "${3:-}"
  rm -f "$1"; ditto -c -k --keepParent "$TMP/relsrc/WoW.app" "$1"
}
digest_of() { printf 'sha256:%s\n' "$(shasum -a 256 "$1" | cut -d' ' -f1)"; }
mkdir -p "$TMP/swap/Trash"
cat > "$TMP/swap/open" <<'STUB'
#!/bin/bash
echo "OPEN $*" >> "$WOW_TEST_OPENLOG"
# refuses whatever WOW_TEST_OPEN_FAIL names, the way macOS refuses an app it
# will not run — the swap must then put the old one back
case "$1" in *"${WOW_TEST_OPEN_FAIL:-\0}"*) [ -n "${WOW_TEST_OPEN_FAIL:-}" ] && exit 1 ;; esac
exit 0
STUB
chmod +x "$TMP/swap/open"
export WOW_TEST_OPENLOG="$TMP/swap/open.log"
(exec -a wow-swap-probe sleep 0) & DEAD=$!; wait "$DEAD" 2>/dev/null   # a pid that has certainly exited
# a disposable copy of this wrapper: apply ends by replacing the app it runs
# from, which must never be the one the rest of the suite uses
AAPP="$TMP/applytest/WoW.app"
apply_setup() {
  rm -rf "$TMP/applytest"; mkdir -p "$TMP/applytest"
  cp -R "$APP" "$AAPP"
  rm -rf "$AAPP/Contents/Resources/games"/*
  mk_plist "$AAPP" io.github.matasarei.wow-launcher "${1:-2.9}"
}
apply() {  # apply <zip> <digest> — against the disposable copy
  WOW_UPDATE_TRASH="$TMP/swap/Trash" WOW_UPDATE_OPEN="$TMP/swap/open" \
    "$AAPP/Contents/Resources/bin/wow-update" apply "file://$1" "$(stat -f%z "$1")" "$2" "$DEAD" 2>&1
}
apply_setup
Z="$TMP/rel/WoW-v2.10.zip"
mk_release_zip "$Z" 2.10
printf 'RENDERER=mtld3d\n' >> "$AAPP/Contents/Resources/launcher.conf"
OUT="$(apply "$Z" "$(digest_of "$Z")")"
assert_contains "$OUT" "downloaded 2.10" "a good release downloads and checks out"
assert_contains "$OUT" "no game to import" "an empty wrapper carries only its settings"
assert_contains "$OUT" "RESTARTING" "and hands over to the swap"
LAST="$(echo "$OUT" | grep '^DOWNLOAD ' | tail -1)"
assert_eq "$(echo "$LAST" | awk '{print ($2 == $3 && $2 > 0) ? "done" : $0}')" "done" "the last DOWNLOAD line says all of it"
# the swap that apply spawned lands on its own; then: no quarantine, settings kept
for _ in $(seq 100); do
  [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
      "$AAPP/Contents/Info.plist" 2>/dev/null)" = 2.10 ] && break
  sleep 0.1
done
# (the quarantine strip in wow-update is not asserted here: the flag is put on
# by LaunchServices when a GUI app downloads, and ditto does not carry one from
# a zip, so this suite cannot reproduce the case it guards against)
assert_contains "$(cat "$AAPP/Contents/Resources/launcher.conf")" "RENDERER=mtld3d" "the settings were carried into it"
stage_count() { find "$TMP/applytest" -maxdepth 1 -name '.wow-update.*' | wc -l | tr -d ' '; }
apply_setup
# and everything that must stop before anything is installed
assert_contains "$(apply "$Z" sha256:dead)" "does not match its checksum" "a wrong checksum stops it"
chmod a-w "$TMP/applytest"
assert_contains "$(apply "$Z" "$(digest_of "$Z")")" "manual update required" "an unwritable folder asks for a manual update"
chmod u+w "$TMP/applytest"
assert_contains "$(apply "$Z" '')" "no checksum" "a release without a checksum stops it"
assert_eq "$(stage_count)" "0" "and nothing is left behind"
apply_setup
mk_release_zip "$TMP/rel/foreign.zip" 3.0 com.example.other
assert_contains "$(apply "$TMP/rel/foreign.zip" "$(digest_of "$TMP/rel/foreign.zip")")" \
  "not a WoW Launcher app" "a foreign app is refused"
mk_release_zip "$TMP/rel/old.zip" 2.2
assert_contains "$(apply "$TMP/rel/old.zip" "$(digest_of "$TMP/rel/old.zip")")" \
  "cannot install itself" "a pre-2.9 download is refused"
apply_setup 2.11
assert_contains "$(apply "$Z" "$(digest_of "$Z")")" "not newer than 2.11" "a download that is not newer is refused"
apply_setup
printf 'not a zip\n' > "$TMP/rel/broken.zip"
assert_contains "$(apply "$TMP/rel/broken.zip" "$(digest_of "$TMP/rel/broken.zip")")" \
  "not a readable archive" "a corrupt archive is refused"
fake_proc "$AAPP/Contents/Resources/wine/bin/wineserver"
OUT="$(apply "$Z" "$(digest_of "$Z")")"
kill "$RUNNING" 2>/dev/null; wait "$RUNNING" 2>/dev/null
assert_contains "$OUT" "the game is still running" "an update while the game runs is refused"
assert_eq "$(stage_count)" "0" "no staging dir survives a refusal"
rm -f "$APP/Contents/Info.plist"; reset_conf

# =============================================================== wow-update swap
section "wow-update swap"
# the swap replaces the app it was started from, so it runs detached, after the
# launcher has quit — here with a pid that is already gone, a fake Trash and a
# stub for `open`
mkdir -p "$TMP/swap/Applications"
swap_setup() {  # a 2.9 app in place, a 2.10 one staged beside it
  rm -rf "$TMP/swap/Applications" "$TMP/swap/Trash" "$WOW_TEST_OPENLOG"
  mkdir -p "$TMP/swap/Applications" "$TMP/swap/Trash"
  mk_release_app "$TMP/swap/old" 2.9
  mv "$TMP/swap/old/WoW.app" "$TMP/swap/Applications/AzerothCore.app"   # renamed by its owner
  mk_release_app "$TMP/swap/Applications/.wow-update.test/new" 2.10
}
swap_run() {  # swap_run <pid>
  WOW_UPDATE_TRASH="$TMP/swap/Trash" WOW_UPDATE_OPEN="$TMP/swap/open" \
    "$BIN/wow-update" swap "$1" "$TMP/swap/Applications/AzerothCore.app" \
      "$TMP/swap/Applications/.wow-update.test/new/WoW.app" 2>&1
}
swap_setup
OUT="$(swap_run "$DEAD")"
assert_eq "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$TMP/swap/Applications/AzerothCore.app/Contents/Info.plist" 2>/dev/null)" "2.10" \
  "the new version takes the old app's exact path and name"
assert_file "$TMP/swap/Trash/AzerothCore.app/Contents/Info.plist"
assert_contains "$(cat "$WOW_TEST_OPENLOG")" "OPEN $TMP/swap/Applications/AzerothCore.app" "and it is opened again"
assert_eq "$(find "$TMP/swap/Applications" -maxdepth 1 -name '.wow-update.*' | wc -l | tr -d ' ')" "0" "the staging dir is gone"
# a second update with the first still in the Trash: the name gets a suffix
swap_setup; mkdir -p "$TMP/swap/Trash/AzerothCore.app"
OUT="$(swap_run "$DEAD")"
assert_file "$TMP/swap/Trash/AzerothCore 1.app/Contents/Info.plist"
# the Trash cannot be written: the update is done anyway, the old copy waits
swap_setup
chmod a-w "$TMP/swap/Trash"
OUT="$(swap_run "$DEAD")"
chmod u+w "$TMP/swap/Trash"
assert_eq "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$TMP/swap/Applications/AzerothCore.app/Contents/Info.plist" 2>/dev/null)" "2.10" "a Trash that cannot be written does not fail the update"
assert_contains "$OUT" "could not be moved to the Trash" "and says where the old copy is"
assert_file "$TMP/swap/Applications/.wow-update.test/old.app/Contents/Info.plist"
rm -rf "$TMP/swap/Applications/.wow-update.test"
# a staging path that is not one: the delete must refuse it
swap_setup
mkdir -p "$TMP/swap/Applications/not-staging"
mv "$TMP/swap/Applications/.wow-update.test/new" "$TMP/swap/Applications/not-staging/new"
OUT="$(WOW_UPDATE_TRASH="$TMP/swap/Trash" WOW_UPDATE_OPEN="$TMP/swap/open" \
  "$BIN/wow-update" swap "$DEAD" "$TMP/swap/Applications/AzerothCore.app" \
    "$TMP/swap/Applications/not-staging/new/WoW.app" 2>&1)"
assert_contains "$OUT" "not a staging dir" "a delete outside a staging dir is refused"
[ -d "$TMP/swap/Applications/not-staging" ] && ok || bad "the directory was deleted anyway"
rm -rf "$TMP/swap/Applications/not-staging"
# the new version will not open: the old one comes back out of the Trash
swap_setup
export WOW_TEST_OPEN_FAIL=AzerothCore   # exported: the stub is run by wow-update, not here
OUT="$(swap_run "$DEAD")"
unset WOW_TEST_OPEN_FAIL
assert_contains "$OUT" "would not open — the old app is back" "a new version that will not start is rolled back"
assert_contains "$(cat "$TMP/swap/Applications/AzerothCore.app/Contents/Resources/logs/update-failed.txt" 2>&1)" \
  "would not open" "and leaves the reason where the app will read it"
assert_eq "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$TMP/swap/Applications/AzerothCore.app/Contents/Info.plist" 2>/dev/null)" "2.9" "the old version is back in place"
assert_eq "$(find "$TMP/swap/Trash" -maxdepth 1 -name '*.app' | wc -l | tr -d ' ')" "0" "and out of the Trash"
# the new app cannot be moved into place: the old one comes back and runs
swap_setup; rm -rf "$TMP/swap/Applications/.wow-update.test/new/WoW.app"
OUT="$(swap_run "$DEAD")"
assert_contains "$OUT" "the old one is back" "a failed swap says so"
assert_eq "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$TMP/swap/Applications/AzerothCore.app/Contents/Info.plist" 2>/dev/null)" "2.9" "the old app is back in place"
assert_contains "$(cat "$WOW_TEST_OPENLOG")" "OPEN $TMP/swap/Applications/AzerothCore.app" "and it is the one opened"
assert_contains "$(cat "$TMP/swap/Applications/AzerothCore.app/Contents/Resources/logs/update-failed.txt" 2>&1)" \
  "could not be moved into place" "the app that reopens is told why"
# it waits for the launcher to quit before touching anything
swap_setup
fake_proc "wow-update-swap-wait"
( swap_run "$RUNNING" > "$TMP/swap/waiting.out" 2>&1 ) & WAITER=$!
sleep 1
assert_eq "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$TMP/swap/Applications/AzerothCore.app/Contents/Info.plist" 2>/dev/null)" "2.9" "nothing moves while the launcher runs"
kill "$RUNNING" 2>/dev/null; wait "$WAITER" 2>/dev/null
assert_eq "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$TMP/swap/Applications/AzerothCore.app/Contents/Info.plist" 2>/dev/null)" "2.10" "and swaps once it has"

# ========================================================= wow-update end to end
section "wow-update: download, import, swap"
# a whole update against a copy of this wrapper: its own game, its own settings,
# a release built from the same wrapper with a higher version
mkdir -p "$TMP/e2e/Applications" "$TMP/e2e/Trash"
E2E="$TMP/e2e/Applications/AzerothCore.app"
rm -rf "$RES/games"/* "$RES/patch-kit/"DivxDecoder.dll.*; reset_conf
mk_plist "$APP" io.github.matasarei.wow-launcher 2.9
"$BIN/wow-install-client" "$TMP/client-wotlk" >/dev/null 2>&1
printf 'RENDERER=mtld3d\nCLOSE_ON_PLAY=1\nUPDATE_SKIP=2.98\n' >> "$RES/launcher.conf"
cp -R "$APP" "$E2E"                                   # the app being updated
rm -rf "$RES/games"/* "$RES/patch-kit/"DivxDecoder.dll.*; reset_conf
rm -f "$APP/Contents/Info.plist"
mk_plist "$E2E" io.github.matasarei.wow-launcher 2.9
rm -rf "$TMP/e2e/rel"; mkdir -p "$TMP/e2e/rel/WoW.app"   # the release: same wrapper, 2.99
cp -R "$E2E/" "$TMP/e2e/rel/WoW.app/"
rm -rf "$TMP/e2e/rel/WoW.app/Contents/Resources/games"/*
printf 'AUTO_RES=1\n' > "$TMP/e2e/rel/WoW.app/Contents/Resources/launcher.conf"
mk_plist "$TMP/e2e/rel/WoW.app" io.github.matasarei.wow-launcher 2.99
codesign --force --deep --sign - "$TMP/e2e/rel/WoW.app" 2>/dev/null
EZ="$TMP/e2e/WoW-v2.99.zip"; ditto -c -k --keepParent "$TMP/e2e/rel/WoW.app" "$EZ"
OUT="$(WOW_UPDATE_TRASH="$TMP/e2e/Trash" WOW_UPDATE_OPEN="$TMP/swap/open" \
  "$E2E/Contents/Resources/bin/wow-update" apply \
  "file://$EZ" "$(stat -f%z "$EZ")" "$(digest_of "$EZ")" "$DEAD" 2>&1)"
assert_contains "$OUT" "importing the game into 2.99" "the update imports the game"
assert_contains "$OUT" "game installed (3.3.5a)" "and the import runs from the new copy"
assert_contains "$OUT" "RESTARTING" "then hands over to the swap"
for _ in $(seq 100); do   # the swap is detached: wait for it to land
  [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
      "$E2E/Contents/Info.plist" 2>/dev/null)" = 2.99 ] && break
  sleep 0.1
done
assert_eq "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$E2E/Contents/Info.plist" 2>/dev/null)" "2.99" "the app at the old path is the new version"
assert_file "$E2E/Contents/Resources/games/main/Wow.exe"
CONF="$(cat "$E2E/Contents/Resources/launcher.conf")"
assert_contains "$CONF" "RENDERER=mtld3d" "the settings came with it"
assert_contains "$CONF" "UPDATE_SKIP=2.98" "the update settings too"
assert_contains "$CONF" "GAME_VERSION=3.3.5a" "and the game is recorded"
assert_file "$TMP/e2e/Trash/AzerothCore.app/Contents/Info.plist"
assert_eq "$(find "$TMP/e2e/Applications" -maxdepth 1 -name '.wow-update.*' | wc -l | tr -d ' ')" "0" "no staging dir is left"

# ================================================================== Swift sources
section "Swift sources"
# SDK 27 makes @State an Xcode-only macro; the bare Command Line Tools cannot
# expand it. CI builds with Xcode, so only this check notices it coming back.
HITS="$(grep -nE '@(SwiftUI\.)?State([^A-Za-z0-9_]|$)' "$ROOT/main.swift" | grep -vE '^[0-9]+:[[:space:]]*//')"
assert_eq "$HITS" "" "main.swift uses @State — use @ViewState (SDK 27 makes @State an Xcode-only macro)"

# ================================================================== summary
echo ""
echo "passed: $PASS, failed: $FAILED"
[ "$FAILED" = 0 ] || exit 1
