# Internals & maintenance notes

Reference for future development. The README covers usage; BUILD-WRAPPER.md covers
building; this file records how things actually work and the traps already hit.

## Wrapper layout (inside WoW335.app)

```
Contents/MacOS/WoW335              compiled SwiftUI manager (from main.swift)
Contents/Resources/
  bin/                             runtime scripts (installed by build.sh from scripts/wow-*)
  cxwine/                          CrossOver wine tree copy + patches (see below)
  prefix/                          wine prefix (fresh wineboot + fast-exit fix)
  patch-kit/                       payloads applied to every installed client
  games/main/                      THE game (single-game model; install = replace)
  launcher.conf                    key=value settings (see below)
  logs/                            last-launch.log(.settings|.mover)
```

## launcher.conf keys

| Key | Meaning |
|---|---|
| `AUTO_RES=1\|0` | auto-match resolution/Retina to the main display at each launch |
| `GAME=main` | active game folder under `games/` (installer sets it) |
| `CHAT_CP=1251` | force the Russian input layer for any client (env locale, system codepage, remapped fonts) |
| `GAME_DISPLAY=<name>` | show the game on this display (GUI writes it) |
| `DISPLAY_RECT=x,y,w,h` | resolved AX coords for the window mover (recomputed at Play) |

## cxwine patches (what `make loader-patch` does)

- **wineloader2** = CrossOver's `wineloader` with `codesign --remove-signature` —
  byte-identical to what WoWSilicon's "CrossOver Patch" produces. No signature →
  no library validation → the patched libraries load.
- **ntdll.so** = winerosetta's build (fast x87 under Rosetta — the biggest FPS win),
  taken from the WoWSilicon bundle.
- **Dock name**: the bare `wine\0` constant at offset **627328** in that ntdll.so is
  patched to `WoW \0` (4-char limit) by `scripts/patch-dock-name.py` (verifies bytes
  first, skips on other builds); the unix loader is renamed `WoW 3.3.5` with
  `wine` and `WoW ` symlinks. LaunchServices shows the *unresolved* exec basename.

## Patch kit anatomy

Shipped by `make patch-kit` (open-source payloads only): `d3d9.dll` (DXVK),
`libDllLdr.dll`, `dlls.txt`, `mods/{winerosetta,libSiliconPatch}.dll`, `rosettax87/`,
`wow-icon-<in-md5>-<out-md5>.bsdiff`, `fonts-cyr/` (DejaVu-based fallback).

Self-populating at install time (never committed — Blizzard-derived):
`DivxDecoder.dll.{orig,patched}`, `Wow.exe.{orig,icon-patched}`, `fonts-client/`.

- **DivxDecoder.dll**: patched live in the user's client via
  `wineloader2 'C:\windows\syswow64\rundll32.exe' "libDllLdr.dll,PatchDivxDecoder" <winpath>`
  (32-bit rundll32 required); the patched DLL chain-loads `dlls.txt` mods.
- **Icon**: bsdiffs keyed by source-exe md5, applied with the system `/usr/bin/bspatch`,
  output md5 verified. The known "ruRU" repack = enUS exe + 6-byte locale-force hack
  (offsets 0x1f41bf, 0x415a25..0x415b66), so it gets its own diff.

## Language / Cyrillic (hard-won)

The 3.3.5a enUS-based client inserts typed bytes into its UTF-8 chat strings
WITHOUT codepage conversion (as Latin-1 codepoints). Things that do NOT fix it:
wine env locale alone, the prefix ACP registry alone, patching the exe's
`push 1252` constants (regressed behavior). The fix that works (classic
community approach): **fonts with Cyrillic glyphs at U+00C0–U+00FF (+Ё/ё at
A8/B8)** in `game/Fonts/` — `wow-client-fonts.py` extracts the client's own
locale-MPQ fonts (mpyq) and remaps them (fontTools); fallback = `fonts-cyr/`.
The wine side still must deliver CP1251 bytes: `LANG/LC_ALL=ru_RU.UTF-8` +
system codepage ACP=1251/OEMCP=866 (wow-launch derives from game locale or
`CHAT_CP=1251`).

Traps:
- The system codepage is **baked per wineserver session** — after changing the
  Nls\CodePage registry, `wineserver -k` or nothing changes (wow-launch does this).
- wine reg's "Unable to find the specified registry ke**y**" ends in *y*: a
  `grep '[YyNn]$'` parser reads a MISSING key as `Y`. Parse the value line
  (`awk '/^ *Name/ {print $NF}'`) instead.
- Repack `realmlist.wtf` files may be CP1251-encoded (Russian comments) — strict
  UTF-8 reads return nil for the whole file; use the utf8→cp1251→latin1 fallback.

## Verify protocol (wow-verify-game ↔ GUI)

Line-oriented: `PROGRESS <n> <total> <label>` before each check; `ok:` / `WARN:` /
`FAIL:` results; `CANFIX` (fixable failures exist, check mode only); `REINSTALL`
(game data unrepairable); final `RESULT: …`; exit 1 on any FAIL. `--fix` repairs:
patch-stack files from the kit, settings (cvars, RetinaMode, fast-exit proxy).
`TOTAL` in the script must match the number of `step` calls (currently 41).

## Assorted gotchas

- **Fast exit**: Wow.exe phones dead Blizzard tracker endpoints on quit (~5 min
  hang); fixed by dead-proxy registry keys (`ProxyEnable=1`, `ProxyServer=127.0.0.1:1`)
  in the prefix — wininet fails instantly, realm/world traffic (winsock) unaffected.
- **Running detection**: wine rewrites the game path to Windows form
  (`Z:\...\main\Wow.exe`, backslashes) — match `main[/\\]Wow\.exe`, not the unix path.
- **gxMaximize=1 overrides gxResolution** (window always fills the screen); with
  RetinaMode=Y the game renders native pixels. `wow-settings auto` keeps both in
  sync with the display; `hwDetect 0` stops the game from overriding seeded settings.
- **GUI launches have no locale env** — wow-launch exports one explicitly.
- The manager quits ~2 s after Play (detached game keeps running); script-app
  launchers that don't check in with LaunchServices get "not responding" — the
  compiled SwiftUI binary is what fixed that historically.
