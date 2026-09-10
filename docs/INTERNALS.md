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
| `GAME_VERSION=<label>` | detected client version — the canonical `3.3.5a`/`2.4.3`/`1.12` for a client the launcher knows, otherwise whatever the executable declares (`4.3.4`), or `unknown` |
| `GAME_FAMILY=wotlk\|tbc\|vanilla\|post-wotlk\|casc\|generic` | which shape of client this is. **Verify trusts this over re-detection**: with `Data/lichking.MPQ` deleted the folder alone reads as TBC, and verify would quietly stop asking for the file that is missing. Absent in wrappers written before 2.5 — derived from `GAME_VERSION` then |
| `GAME_BUILD=<n>` | build number from the executable's `VS_VERSIONINFO` (`12340`), empty when it has none |
| `GAME_EXE=<name>` | the entrypoint the installer found. The GUI's run-detection pattern includes it, so a repack that renamed its executable is still recognised as running |
| `CHAT_CP=1251` | Cyrillic input layer for any client (env locale, system codepage, remapped fonts); auto-added by the installer when a Russian keyboard layout is present, `CHAT_CP=` empty opts out |
| `GAME_DISPLAY=<name>` | show the game on this display (GUI writes it) |
| `DISPLAY_RECT=x,y,w,h` | resolved AX coords for the window mover (recomputed at Play) |
| `RENDERER=dxvk\|mtld3d` | graphics backend (Display pane): dxvk = game-dir DXVK d3d9 (`d3d9=n,b`); mtld3d = the runtime's builtin Metal-native d3d9, HDR-capable (`d3d9=b`) |
| `PATCHES=all\|no-silicon\|winerosetta\|none` | how much of the patch stack is applied to the client — **`all` by default** (Game pane → Patches picker). This records what the **user asked for**; `wow-client-profile` clamps it down to the best level the installed client can actually take and every tool uses the clamped value, so swapping to a client that cannot take libSiliconPatch and back again restores the full set. The picker only offers the levels in the profile's `LEVELS`. `all`: every patch, libSiliconPatch included. `no-silicon`: everything but libSiliconPatch — its ~400 hooks are hardcoded addresses with no build check, so on a modified client they corrupt memory instead of failing, and Sirus-style clients report the patched bytes to the server (WoWSilicon issue #15). `winerosetta`: only the Divx mod loader + `mods/winerosetta.dll`. That DLL's `DllMain` installs a vectored exception handler which fills two Rosetta 2 instruction gaps — it emulates `ARPL AX,DX` and rewrites `FCOMP ST(0),ST(0)` in place; neither encoding appears in the client itself, so what needs them is server-pushed Warden code. (It also exports `Direct3DCreate9` and can proxy to `d9vk.dll` / `<known folder>\d3d9.dll`; that path is dormant here, since DXVK's own `d3d9.dll` sits in the game dir and the exe imports it directly.) `none`: the client is left exactly as it shipped (Warden servers will most likely disconnect). Levels apply via `wow-verify-game --fix`, which converges the mod set, the Divx DLL and the `Wow.exe` icon patch in both directions. The pre-2.4 `SILICON=` toggle still migrates (`1`→`all`, `0`→`no-silicon`) |
| `X87=rosettax87\|sidecar` | x87 engine (conf-only, no UI): default rosettax87 from the game dir; `sidecar` uses patch-kit/x87sidecar via `X87_SIDECAR_PATH` (cooperative attach, no debugger) — fallback if rosettax87 breaks on a future macOS |

## Wine runtime (what `make runtime` / `make payloads` do)

- **Runtime** = WoWSilicon's standalone wine build: [WineAndAqua wine](https://github.com/WineAndAqua/wine)
  11.13 (branch `wine-11.13-macos`) plus the mtld3d D3D9→Metal layer, published as
  `wine-runtime-r<N>.tar.xz` on WoWSilicon's releases. The Makefile downloads it
  sha256-pinned (`RUNTIME_URL`/`RUNTIME_SHA256` — update both together) and untars
  into `Resources/wine/`. `share/wowsilicon/runtime-lock.json` inside records the
  exact wine commit and component versions. Pinned at **r15** (same wine commit as r6,
  plus WoWSilicon's twelve patches).
- **Audio follows the macOS default device** (r15+): `winecoreaudio.drv` re-targets a
  running stream to the system default output every ~250 ms and `dsound` migrates its
  buffers along, so switching to AirPods mid-game just works. The driver reads a
  `WOWSILICON_*` environment contract: `WOWSILICON_FOLLOW_SYSTEM_OUTPUT` (default `1` —
  never set it), `WOWSILICON_SPATIAL_AUDIO_MODE=off|fixed`,
  `WOWSILICON_NORMALIZE_AUDIO=0|1`, and two control-file paths
  (`WOWSILICON_SPATIAL_AUDIO_CONTROL`, `WOWSILICON_NORMALIZE_AUDIO_CONTROL`) that it
  polls for live changes. Unset, those default to
  `~/Library/Application Support/WoWSilicon/…` — a co-installed WoWSilicon's settings
  would leak in — so `wow-launch` always points them at `Resources/audio/`.
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

`Wow.exe` is an all-ANSI application (`RegisterClassExA`, `GetMessageA`…)
that derives its own input codepage from the keyboard-layout HKL. Under
winemac.drv the app never receives `WM_INPUTLANGCHANGE`, so after the first
RU↔EN layout toggle the client decodes wine's CP1251 bytes as Latin-1 (the
ruRU client too — before the toggle it decodes correctly). CrossOver's wine
doesn't have this; the standalone Wine 11.13 runtime does — the real fix
belongs in winemac.drv. Things that do NOT fix it: wine env locale alone, the
prefix ACP registry alone, patching the exe's `push 1252` constants (regressed
behavior). The workaround that works (classic community approach): **fonts
with Cyrillic glyphs at the Latin-1 positions the bytes land on** — U+00C0–U+00FF
→ А–я, Ё/ё at A8/B8, plus CP1251's 0xA0–0xBF letters (І і Ї ї Є є Ґ ґ Ў ў Ј ј
Ѕ ѕ №, so Ukrainian/Belarusian layouts work; without them `і` shows as `³`) —
in `game/Fonts/`. `tools/wow-client-fonts.swift` (built into `bin/wow-client-fonts`)
extracts the client's own locale-MPQ fonts and rewrites their unicode cmap
subtables; native Swift, decompression via the system libz/libbz2 dylibs, so
nothing (no Python, no Xcode CLT) is needed at run time. Once extracted they
are stashed in `patch-kit/fonts-client/` and reused for any client (no other
source — enUS MPQ fonts have no Cyrillic glyphs); a ruRU install/pack import
refreshes a stash that fails `wow-client-fonts check` (older remap, corrupt).
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
`TOTAL` must match the number of `step` calls exactly. It is **computed**, not a
constant: `2` (executable) `+` support DLLs `+` `10` (patch stack) `+` core and
optional archives `+` locale group `+` `6` (settings). That still comes to
43 (3.3.5a), 29 (2.4.3) and 25 (1.12); an unrecognised client has no support-DLL
or archive lists and lands at 19. The patch-stack group is deliberately a
constant — a step that cannot apply to this client reports so rather than
disappearing, which keeps the progress bar honest. The suite asserts the
identity directly (`awk '/^PROGRESS/ {print $3}' | sort -u` against the step count).

## Assorted gotchas

- **`tools/wow-client-fonts.swift` must be compiled `-Onone`.** At `-O` the
  Swift 6.1.2 toolchain — the one on macOS 15, the minimum this app supports —
  miscompiles it: the binary dies with `EXC_BAD_ACCESS (code=1, address=0x7)` in
  `swift_unknownObjectRetain` before extracting anything, so Cyrillic font
  extraction silently fails and the installer reports the fonts as unavailable.
  The same source at `-Onone` produces byte-identical output. It does not
  reproduce on the newer toolchain shipped with macOS 26, which is why local
  testing never caught it; CI on `macos-15` did, on its first run. Whether the
  bug is in the optimiser or in latent UB in this file has not been determined —
  if you go looking, `-Onone` vs `-O` on the same source is the reproducer, and
  the cost of the workaround is 0.16 s instead of 0.02 s once per install.

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

## Any-client support (2.5) — `wow-client-profile`

One game at a time, and it no longer has to be one of the classic three. A
single script fingerprints the client and derives what the patch kit can do with
it; the installer, verify, launch and the language tool all read it, and the GUI
reads it too. `wow-client-profile [<dir>]` prints `KEY=value` lines and always
exits 0 — an unrecognised client is an answer (`FAMILY=generic`), not an error.
`--exe <dir>` is the cheap mode used on the launch path: entrypoint only, no
version scan.

**Detection**, cheapest first and most authoritative last:

1. **Entrypoint** — `Wow.exe` > `run.exe` > the largest root `.exe` that is not a
   known helper (`WowError.exe`, `Repair.exe`, `Launcher.exe`, …).
2. **`ARCH`** — the PE machine word at `e_lfanew+4`: `014c` → x86, `8664` → x64.
3. **`VERSION`/`BUILD`** — the executable's `VS_VERSIONINFO`, found through the
   section table: only `.rsrc` is read, not the whole file (scanning everything
   costs ~1 s per 9 MB, on every install and every verify — 0.09 s vs 0.83 s on
   the 7.7 MB 3.3.5a `Wow.exe`). A header with no usable section table falls back
   to the whole file. Two `tr` passes either way: the first deletes NULs (the
   strings are UTF-16LE), the second turns every remaining non-printable byte
   into a newline. **Without the second pass the input is one enormous "line" and
   BSD `grep -o` silently finds nothing.**
4. **`DATA` layout** — checked most-specific first: `.build.info`/`Data/data/*.idx`
   → casc; `expansion2`/`expansion3`/`world`/`world2.MPQ` → post-wotlk;
   `lichking.MPQ` → wotlk; `expansion.MPQ` → tbc; `dbc.MPQ` → vanilla.

The resource wins over the layout. `Data/lichking.MPQ` only says "WotLK era";
`FileVersion 3, 3, 5, 12340` says which build, and that is what libSiliconPatch's
hardcoded addresses actually need. `CONFIDENCE` is `exact` when both agree,
`likely` when only the layout is known, `guess` for `generic`/`casc` — where the
launcher knows the client's name at best, never its expected contents.

**What gates a patch** (all of it verified against the payloads, not assumed):

| Payload | Gate | Why |
|---|---|---|
| `d3d9.dll` (DXVK), mtld3d | `ARCH != x64` | both are PE `014c`; the runtime ships mtld3d only under `wine/i386-windows/` |
| `libDllLdr.dll` + `mods/winerosetta.dll` | 32-bit **and** a `DivxDecoder.dll`/`DivxTac.dll` to hook | `libDllLdr` exports exactly `PatchDivxDecoder`, `PatchDivxTac`, `RunDll32Entry`, `ScanWow` — there is no other injection route |
| `libSiliconPatch.dll` | the mod loader **and** wotlk build 12340 (or unreadable) / any 1.12 | the Divx hook is what loads it; its hooks are 12340 addresses. An unreadable build still qualifies, so a packed custom exe does not silently lose hooks it gets today |
| icon bsdiff | `Wow.exe` whose md5 matches a diff on either end | already md5-keyed; matching the *output* too keeps the level offered after patching |
| `vanilla-tweaks.exe` | `FAMILY=vanilla` | |
| language packs | `FAMILY` wotlk/tbc **and** `EXE=Wow.exe` | a pack carries its own locale-matched `Wow.exe` |
| `Config.wtf` seeding, `AUTO_RES` | `DATA=mpq` | the `gx*` names are MPQ-era; never guess at others |
| rosettax87 / x87sidecar | always | it patches the Rosetta runtime, not the game |

**`LEVELS`** follows: `none` always; `winerosetta` with the loader; `no-silicon`
with the loader or the icon; `all` only with a libSiliconPatch build. So a 12340
client sees all four (unchanged from 2.4), a Cataclysm client three, and a
64-bit client one — for it, nothing in the kit can be loaded at all and the app
says so before the copy starts.

- **Client entrypoint**: `Wow.exe` normally; if a client ships only `run.exe`
  (Sirus-style custom builds) that becomes the entrypoint for launch and verify,
  and a repack may name it anything else. When both exist `Wow.exe` wins.
- **Leniency**: at `PATCHES=none` — the level people pick for custom clients —
  and for any client at `CONFIDENCE=guess`, failing to recognise the build is
  expected: the unknown-build warning, the "cannot verify the original" warning
  and missing support DLLs are all reported as `ok:` lines instead of warnings.
  Nothing is skipped; the step count is unchanged.
- **Divx patch**: `DivxTac.dll` is patched too when present (older clients);
  kit references are version-keyed (`DivxDecoder.dll.<version>.{orig,patched}`)
  because the DLLs differ between client builds.
- **1.12**: no `Data/<locale>/` folder — `realmlist.wtf` lives in the game root
  (the GUI already reads both); `vanilla-tweaks.exe` is copied into the game dir
  (not run automatically — if the user generates `WoW_tweaked.exe`, wow-launch
  prefers it); the `WDB/` cache is deleted before every launch.
- **Config.wtf baseline**: common seeds for all; `videoOptionsVersion`/`M2*`/
  `gxFixLag` only for wotlk. Both the seeding and the `wow-settings auto` that
  follows it are skipped entirely for a client that does not use those cvar
  names, which is also recorded as `AUTO_RES=0`.
- **Verify** is client-aware; see the Verify protocol section for how `TOTAL` is
  computed. An unrecognised client is checked only for what the launcher itself
  put in the folder, and its `realmlist.wtf` is reported, never demanded — a
  CASC-era client picks its server another way.
- The install triggers an automatic verify in the GUI (`installGame` →
  `verifyGame()`), and the run-detection pattern matches `Wow.exe`,
  `WoW_tweaked.exe`, `run.exe` and whatever `GAME_EXE` recorded.

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
