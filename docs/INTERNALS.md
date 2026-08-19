# Internals & maintenance notes

Reference for future development. The README covers usage; BUILD-WRAPPER.md covers
building; this file records how things actually work and the traps already hit.

## Wrapper layout (inside WoW.app)

```
Contents/MacOS/WoW Launcher        compiled SwiftUI manager (from main.swift)
Contents/Resources/
  bin/                             runtime scripts (installed by build.sh from scripts/wow-*)
  wine/                            wine runtime (WineAndAqua wine 11.13 + mtld3d, see below)
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
| `GAME_VERSION=3.3.5a\|2.4.3\|1.12` | detected client version (installer sets it; `wow-game-version` re-detects by Data fingerprint: lichking.MPQ → 3.3.5a, expansion.MPQ → 2.4.3, dbc.MPQ → 1.12) |
| `CHAT_CP=1251` | Cyrillic input layer for any client (env locale, system codepage, remapped fonts); auto-added by the installer when a Russian keyboard layout is present, `CHAT_CP=` empty opts out |
| `GAME_DISPLAY=<name>` | show the game on this display (GUI writes it) |
| `DISPLAY_RECT=x,y,w,h` | resolved AX coords for the window mover (recomputed at Play) |
| `RENDERER=dxvk\|mtld3d` | graphics backend (Display pane): dxvk = game-dir DXVK d3d9 (`d3d9=n,b`); mtld3d = the runtime's builtin Metal-native d3d9, HDR-capable (`d3d9=b`) |
| `X87=rosettax87\|sidecar` | x87 engine (conf-only, no UI): default rosettax87 from the game dir; `sidecar` uses patch-kit/x87sidecar via `X87_SIDECAR_PATH` (cooperative attach, no debugger) — fallback if rosettax87 breaks on a future macOS |

## Wine runtime (what `make runtime` / `make payloads` do)

- **Runtime** = WoWSilicon's standalone wine build: [WineAndAqua wine](https://github.com/WineAndAqua/wine)
  11.13 (branch `wine-11.13-macos`) plus the mtld3d D3D9→Metal layer, published as
  `wine-runtime-r<N>.tar.xz` on WoWSilicon's releases. The Makefile downloads it
  sha256-pinned (`RUNTIME_URL`/`RUNTIME_SHA256` — update both together) and untars
  into `Resources/wine/`. `share/wowsilicon/runtime-lock.json` inside records the
  exact wine commit and component versions.
- **winerosetta is integrated**: this wine's `ntdll.so` natively contains the fast-x87
  hooks (the biggest FPS win) and reads the same `ROSETTA_X87_PATH` env var as the
  old patched-CrossOver stack (plus a newer `X87_SIDECAR_PATH` alternative, unused here).
- **No signature games**: the runtime's binaries are unsigned, so there is no library
  validation to defeat. The old stack (≤ v2.5.5, CrossOver-based) needed `wineloader2`
  (signature-stripped loader) and a winerosetta `ntdll.so` swap — all obsolete.
- **Payloads** (`make payloads`): the game-side files come from the WoWSilicon 3.0.1
  release DMG (sha256-pinned, mounted read-only, never launched/installed) — or from a
  locally installed WoWSilicon 3.x if one is found (detected by `Patching/x87sidecar`).
  Materialized in `build/deps/Patching/`.
- **Dock name**: the game must not show as "wine" in the Dock. The macOS process
  name comes from the last component of the **exec path string** (not resolved).
  ntdll builds the loader path itself (`wineloader = ntdll_dir + "/wine"`,
  loader.c `init_paths`) — env `WINELOADER`, symlinks, even renaming the loader
  binary do NOT change it, and the string literal is merged into other rodata so
  it can't be byte-patched safely (all tried, all failed). What works: ntdll
  spawns `$ROSETTA_X87_PATH <loader> <args…>`, and the kit's
  `rosettax87/rosettax87-shim` rewrites `<loader>` to the `WoW` symlink
  (created by `make runtime`) before exec'ing the real rosettax87 → the game
  process is named "WoW". Known limitation: in `X87=sidecar` mode the loader is
  exec'd directly, so the Dock shows "wine" there.

## Patch kit anatomy

Shipped by `make patch-kit` (open-source payloads only): `d3d9.dll` (DXVK),
`libDllLdr.dll`, `mods/winerosetta.dll`, `libSiliconPatch/{vanilla,wotlk}/`,
`vanilla-tweaks.exe`, `rosettax87/`, `x87sidecar/`,
`wow-icon-<in-md5>-<out-md5>.bsdiff`. (`dlls.txt` is generated per version by
the installer, not shipped.)

Self-populating at install time (never committed — Blizzard-derived):
`DivxDecoder.dll.<version>.{orig,patched}` (also `DivxTac.dll.…` on older
clients), `Wow.exe.{orig,icon-patched}`, `fonts-client/`.

- **DivxDecoder.dll**: patched live in the user's client via
  `wine 'C:\windows\syswow64\rundll32.exe' "libDllLdr.dll,PatchDivxDecoder" <winpath>`
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
locale-MPQ fonts (mpyq) and remaps them (fontTools); once extracted they are
stashed in `patch-kit/fonts-client/` and reused for any client (no other source —
enUS MPQ fonts have no Cyrillic glyphs).
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
`TOTAL` in the script must match the number of `step` calls exactly — it is per-version: 43 (3.3.5a), 29 (2.4.3), 25 (1.12).

## Assorted gotchas

- **Fast exit**: Wow.exe phones dead Blizzard tracker endpoints on quit (~5 min
  hang); fixed by dead-proxy registry keys (`ProxyEnable=1`, `ProxyServer=127.0.0.1:1`)
  in the prefix — wininet fails instantly, realm/world traffic (winsock) unaffected.
- **Running detection**: wine rewrites the game path to Windows form
  (`Z:\...\main\Wow.exe`, backslashes) — match `main[/\\][Ww]o[Ww](_[Tt]weaked)?\.exe`, not the unix path.
- **gxMaximize=1 overrides gxResolution** (window always fills the screen); with
  RetinaMode=Y the game renders native pixels. `wow-settings auto` keeps both in
  sync with the display; `hwDetect 0` stops the game from overriding seeded settings.
- **GUI launches have no locale env** — wow-launch exports one explicitly.
- The manager quits ~2 s after Play (detached game keeps running); script-app
  launchers that don't check in with LaunchServices get "not responding" — the
  compiled SwiftUI binary is what fixed that historically.

## Multi-version support (2.0)

One game at a time, any of **3.3.5a / 2.4.3 / 1.12** — the installer detects the
version (`wow-game-version`, Data-MPQ fingerprint) and records it as
`GAME_VERSION`. Per-version differences, everything else is shared:

- **libSiliconPatch**: per-expansion builds in `patch-kit/libSiliconPatch/{vanilla,wotlk}`;
  none exists for 2.4.3 (its `dlls.txt` lists only winerosetta).
- **Divx patch**: `DivxTac.dll` is patched too when present (older clients);
  kit references are version-keyed (`DivxDecoder.dll.<version>.{orig,patched}`)
  because the DLLs differ between client builds.
- **1.12**: no `Data/<locale>/` folder — `realmlist.wtf` lives in the game root
  (the GUI already reads both); `vanilla-tweaks.exe` is copied into the game dir
  (not run automatically — if the user generates `WoW_tweaked.exe`, wow-launch
  prefers it); the `WDB/` cache is deleted before every launch.
- **Config.wtf baseline**: common seeds for all; `videoOptionsVersion`/`M2*`/
  `gxFixLag` only for 3.3.5a. The installer also runs `wow-settings auto` so a
  fresh install verifies clean.
- **Verify** is version-aware: 43 checks (3.3.5a), 29 (2.4.3), 25 (1.12) —
  the TOTAL constants in `wow-verify-game` must match the emitted steps exactly.
- The install triggers an automatic verify in the GUI (`installGame` →
  `verifyGame()`), and the run-detection pattern matches
  `[Ww]o[Ww](_[Tt]weaked)?\.exe`.

## Language packs (wow-language, 2.0)

A pack = the client's `Data/<locale>/` folder **plus its matching `Wow.exe`** —
they belong together: a clean enUS exe with `SET locale "ruRU"` starts, renders,
then its window vanishes (the ruRU "repack" exe's 6-byte locale-force hack is
load-bearing, not cosmetic). Two packs inside `Data/` at once breaks the same
way — hence **physical switching**: exactly one pack in `Data/`, the rest under
`games/<g>/locales/<loc>/{pack,Wow.exe}`. `wow-language switch` swaps folders +
exe, re-applies the md5-keyed icon bsdiff, sets the `locale` cvar, wipes
`Cache/` (stale per-locale server data), and keeps the Cyrillic fonts whenever
a ruRU pack exists anywhere. `import` validates the source client version
matches the installed game and also feeds the font stash from ruRU packs.
Vanilla (1.12) has no locale folders — localized 1.12 clients are entirely
separate builds — so the script refuses and the GUI hides the section.
