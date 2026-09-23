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
  home/                            wine's HOME (Wine/ = the prefix's Windows user profile); created at first run
```

## launcher.conf keys

| Key | Meaning |
|---|---|
| `AUTO_RES=1\|0` | auto-match resolution/Retina to the main display at each launch |
| `RETINA=on\|off` | a Retina choice made by hand (Display pane toggle, `wow-settings retina on\|off`). Absent = follow the display. Every auto-match keeps it — at Play, in the app, in Verify, which then checks against it — and sizes the resolution to it (points when off). Dropped by the main screen's detect button (`wow-settings auto reset`), by `wow-settings retina auto`, and by a fresh install |
| `GAME=main` | active game folder under `games/` (installer sets it) |
| `GAME_VERSION=<label>` | detected client version — the canonical `3.3.5a`/`2.4.3`/`1.12` for a client the launcher knows, otherwise whatever the executable declares (`4.3.4`), or `unknown` |
| `GAME_FAMILY=wotlk\|tbc\|vanilla\|post-wotlk\|casc\|generic` | which shape of client this is. **Verify trusts this over re-detection**: with `Data/lichking.MPQ` deleted the folder alone reads as TBC, and verify would quietly stop asking for the file that is missing. Absent in wrappers written before 2.5 — derived from `GAME_VERSION` then |
| `GAME_BUILD=<n>` | build number from the executable's `VS_VERSIONINFO` (`12340`), empty when it has none |
| `GAME_EXE=<name>` | the entrypoint the installer found. The GUI's run-detection pattern includes it, so a repack that renamed its executable is still recognised as running |
| `CHAT_CP=1251` | Cyrillic input layer for any client (env locale, system codepage, remapped fonts); auto-added by the installer when a Russian keyboard layout is present, `CHAT_CP=` empty opts out |
| `GAME_DISPLAY=<name>` | show the game on this display (GUI writes it) |
| `DISPLAY_RECT=x,y,w,h` | resolved AX coords for the window mover (recomputed at Play) |
| `RENDERER=dxvk\|mtld3d` | graphics backend (Display pane): dxvk = game-dir DXVK d3d9 (`d3d9=n,b`); mtld3d = the runtime's builtin Metal-native d3d9, HDR-capable (`d3d9=b`) |
| `SPATIAL_AUDIO=1\|0` | Apple spatial audio for headphones (Audio pane) — **on by default** (absent = on, like `AUTO_RES`): `wow-launch` exports `WOWSILICON_SPATIAL_AUDIO_MODE=fixed`, `0` → `off`; takes effect at the next game start |
| `NORMALIZE_AUDIO=1\|0` | volume normalizer — quiet up, loud down (Audio pane) — **on by default**: exports `WOWSILICON_NORMALIZE_AUDIO=1`, `0` → `0`; next game start |
| `PATCHES=all\|no-silicon\|winerosetta\|none` | how much of the patch stack is applied to the client — **`all` by default** (Game pane → Patches picker). This records what the **user asked for**; `wow-client-profile` clamps it down to the best level the installed client can actually take and every tool uses the clamped value, so swapping to a client that cannot take libSiliconPatch and back again restores the full set. The picker only offers the levels in the profile's `LEVELS`. `all`: every patch, libSiliconPatch included. `no-silicon`: everything but libSiliconPatch — its ~400 hooks are hardcoded addresses with no build check, so on a modified client they corrupt memory instead of failing, and Sirus-style clients report the patched bytes to the server (WoWSilicon issue #15). `winerosetta`: only the Divx mod loader + `mods/winerosetta.dll`. That DLL's `DllMain` installs a vectored exception handler which fills two Rosetta 2 instruction gaps — it emulates `ARPL AX,DX` and rewrites `FCOMP ST(0),ST(0)` in place; neither encoding appears in the client itself, so what needs them is server-pushed Warden code. (It also exports `Direct3DCreate9` and can proxy to `d9vk.dll` / `<known folder>\d3d9.dll`; that path is dormant here, since DXVK's own `d3d9.dll` sits in the game dir and the exe imports it directly.) `none`: the client is left exactly as it shipped (Warden servers will most likely disconnect). Levels apply via `wow-verify-game --fix`, which converges the mod set, the Divx DLL and the `Wow.exe` icon patch in both directions. The pre-2.4 `SILICON=` toggle still migrates (`1`→`all`, `0`→`no-silicon`) |
| `CLOSE_ON_PLAY=1\|0` | quit the launcher once the game is in front (Play pane checkbox) — **off by default** (absent = stay open); while the game runs the launcher only leaves the screen, because the game's Local Network access is the launcher's (Assorted gotchas) |
| `X87=rosettax87\|sidecar` | x87 engine (conf-only, no UI): default rosettax87 from the game dir; `sidecar` uses patch-kit/x87sidecar via `X87_SIDECAR_PATH` (cooperative attach, no debugger) — fallback if rosettax87 breaks on a future macOS |

## Wine runtime (what `make runtime` / `make payloads` do)

- **Runtime** = WoWSilicon's standalone wine build: [WineAndAqua wine](https://github.com/WineAndAqua/wine)
  11.13 (branch `wine-11.13-macos`) plus the mtld3d D3D9→Metal layer, published as
  `wine-runtime-r<N>.tar.xz` on WoWSilicon's releases. The Makefile downloads it
  sha256-pinned (`RUNTIME_URL`/`RUNTIME_SHA256` — update both together) and untars
  into `Resources/wine/`. `share/wowsilicon/runtime-lock.json` inside records the
  exact wine commit and component versions. Pinned at **r16** (same wine commit as r6,
  plus WoWSilicon's thirteen patches — r16 added one that keeps the wine user profile
  inside the prefix instead of linking it to `$HOME/Wine`).
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
- **Payloads** (`make payloads`): the game-side files come from the WoWSilicon 3.2.1
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

## Install progress (wow-install-client ↔ GUI)

The client copy goes through `wow-copy`, which runs `ditto` in the background
and prints `COPY <done KB> <total KB> <file>` about once a second, then a final
`COPY <total> <total>`. Every other line is a stage line the install pane shows
as it is. Traps: ditto writes into a temporary `.BC.T_*` file and renames it
at the end, so the name being copied is read from the **source** side
(`lsof`, the regular file open under SRC); sizes are apparent (`du -A`) on both
sides, or exFAT cluster sizes make the bar stop short. A backgrounded ditto is
out of reach of `set -e`, so `wow-copy` hands its exit status back through
`wait`, and the suite checks that a failed copy never reaches the patch step.
Within a single volume ditto clones instead of copying (`--clone`, asked for
explicitly), so the bar only ever moves on a copy from another drive.

## Import from a previous app (2.9)

`wow-install-client /path/Old.app` takes the game from an older copy of this
app — the usual way to update, since the previous version is simply there in
/Applications (often renamed: never trust the file name). Checked first,
refused with nothing here changed: `CFBundleIdentifier` must be
`io.github.matasarei.wow-launcher`, `CFBundleShortVersionString` ≥ 2.1
(numeric), not this app, `games/<GAME>` non-empty, and no process running from
its `Contents/` (matched both resolved and as given — `/tmp` vs `/private/tmp`).

**Why 2.1 is the floor:** the game layout (`games/main`, `GAME=`) and the
`.bak` / `Wow.exe.icon-backup` originals are there since 1.0. Every release up to
2.9 shipped the WoWSilicon 3.0.1 payload. The move to 3.2.1 changed only `d3d9.dll`
and the wotlk `libSiliconPatch.dll`, and both are copied from the kit again by every
install and import (verify flags them as repairable when they differ).
`libDllLdr.dll`, which produces the patched Divx DLLs, is byte-identical, so an old
app's `.patched` references are still what this one would write. But 1.0 and 2.0 carried the
bundle identifier `local.wow335.singleapp` (and 1.0 unversioned kit references,
3.3.5a only) — 2.1 is the first release the identifier check can recognise.
**When the payload pin moves**, check this again: if `libDllLdr.dll` ever changes,
an older app's `.patched` references and patched Divx DLLs are of the old payload.

What moves: the game folder, cloned (Config.wtf, AddOns, `locales/` packs,
realmlist, caches — all as they are; the cvar seeding of a normal install is
skipped); the old kit's self-populated references (`DivxDecoder/DivxTac
.dll.<V>.{orig,patched}`, `Wow.exe.{orig,icon-patched}` — never over one this kit
has) and its `fonts-client/` stash if `wow-client-fonts check` passes (pre-2.3
remaps do not); and the player's choices from `launcher.conf`: `PATCHES`
(`SILICON` only when there is no `PATCHES`), `CHAT_CP`, `RENDERER`,
`SPATIAL_AUDIO`, `NORMALIZE_AUDIO`, `CLOSE_ON_PLAY`, `X87`, `RETINA`, and
`AUTO_RES=0` (resolution managed by hand, for gx*-cvar clients). Not the
screen setup (`DISPLAY_RECT`, `GAME_DISPLAY`) nor `GAME_*` (recomputed).
Nothing is patched by the installer — the Divx DLL is already patched, and
patching it live again would patch a patched file; `wow-verify-game --fix`
then brings kit files, mod set, Divx, icon, resolution and Retina to the
chosen level from the originals the old app left beside them. The source app
is only ever read (the suite compares its checksum listing before and after).

## Version check and in-app update (2.9) — `wow-update`

The update is the import run backwards: the release is downloaded beside this
app, the **new copy** imports the game out of the running one, and the two are
then swapped. Nothing in the update knows how to patch a client.

`wow-update check [--force]` also prints `REPLACEABLE=1|0` — a real `mktemp` probe in the
app's folder, which catches a standard user under `/Applications`
(`drwxrwxr-x root:admin`), a read-only mount and a translocated copy alike. `0` means the
dialog for a new version drops the Update button and says the update must be done by hand.
**Nothing in the updater ever escalates**: no `sudo`, no authorization call, no password
prompt — an updater that can elevate is a much bigger risk than one that declines and says so.

`wow-update check [--force]` asks
`api.github.com/repos/matasarei/wow-launcher/releases/latest` (never a draft or a
pre-release) and prints `CURRENT=`, `LATEST=`, `PAGE=`, `ASSET=`, `SIZE=`,
`DIGEST=` and one `RESULT:` — `UPDATE`, `CURRENT`, `SKIPPED`, `OFF`, `TOO-SOON`
or `UNREACHABLE`. `plutil -extract` reads the API's JSON, so there is no JSON
parser here. Versions compare as numbers: **2.10 is newer than 2.9**, which a
string compare gets backwards. `launcher.conf`: `UPDATE_CHECK=1|0` (absent = on),
`UPDATE_CHECKED=<epoch>`, `UPDATE_SKIP=<version>` — all three carried by the
import. The GUI runs the check from `Store.init` on a background queue, weekly
(`curl --max-time 15` is the outer bound), and says nothing unless there is news;
the About button passes `--force`, which ignores the interval, the off switch and
a skipped version.

`wow-update apply <url> <size> <digest> [<pid>]` refuses first — a translocated
copy (a quarantined download runs read-only), a folder it cannot write, a running
game — then downloads into `.wow-update.XXXX` **beside the app** (so the swap is a
rename and the import clones), prints `DOWNLOAD <done> <total>` for the same bar
as `COPY`, checks the sha256 against the API's `digest`, unpacks, and asks the
download what the import asks of a previous app: our bundle identifier, ≥ 2.9
(`--updating` landed there — an older release could not install itself), newer
than this one, and `codesign --verify --deep` intact. Then
`<new>/…/bin/wow-install-client --updating <this app>` carries the game; with no
game installed the settings are copied by key instead. Finally a copy of the new
`wow-update` is spawned detached and `RESTARTING` tells the launcher to quit.

`wow-update swap <pid> <old> <new>` runs from that staging copy, waits for the launcher to exit
(60 s cap), then moves the old app **sideways into the staging dir** (not the Trash: while the
app's path is empty both copies sit in one place, and the rollback is a single rename back),
renames the new app to the old one's **exact path and name** — apps get renamed, and the Dock
and the Local Network grant follow the path — and opens it. Only once it has opened does the old
copy go to `~/.Trash`, with a numbered suffix when the name is taken; its game shares blocks
with the new copy, so keeping it costs almost nothing. A Trash move that fails is a `NOTE:`, not
a failure — the update is already done, and the old copy stays in staging.

A failed rename, or a new version that will not open, puts the old app back and opens that. The
staging dir is deleted only when its name is the `.wow-update.*` one `mktemp` gave it — what is
deleted comes from an argument, and a mistyped one must not take a folder of apps with it.

**Failures speak.** Everything here happens after the launcher has quit, so each failure path
writes one line to `logs/update-failed.txt` **inside the app that reopens**. `Store.init` reads
it (`checkUpdateFailure`), shows it once as an alert with **Open Release Page**, deletes the
marker, and keeps it as a banner in About until a check gets through.

**What the checks do and do not prove.** The digest comes from the same API as
the link, so it proves the download arrived intact, not who built it; the ad-hoc
seal proves the bundle is internally consistent, not its author. Real provenance
needs Developer ID signing and notarization (see "Making a release" in
`CLAUDE.md`). Also: the new copy is a new ad-hoc identity, so the first LAN game
after an update may have to be granted Local Network access again — and that
grant needs both launcher and game restarted (below).

**Tests:** `curl` reads `file://` URLs and `WOW_UPDATE_API`, `WOW_UPDATE_INTERVAL`,
`WOW_UPDATE_TIMEOUT`, `WOW_UPDATE_TRASH` and `WOW_UPDATE_OPEN` are overridable, so
the hermetic suite drives the whole thing — check in every result, apply against a
sealed fake release, swap with a fake Trash and a stub `open`, and one end-to-end
run that leaves the new version at the old path with the game and settings in it.

## Assorted gotchas

- **This wine creates `$HOME/Wine`** (issue #12). WineAndAqua's macOS branch runs
  `mkdir("$HOME/Wine")` in every wine process (`dlls/ntdll/unix/loader.c`,
  `set_home_dir`) and links the prefix's `C:\users\<name>` to `$HOME/Wine`
  (`dlls/shell32/shellpath.c`), with no switch to turn either off. So every script
  that runs wine exports `HOME="$(wow-wine-home)"` → `Resources/home`, and the
  Makefile's `prefix` step does the same (then drops `home/`, so a fresh bundle ships
  without it). `wow-wine-home` also makes the profile link relative
  (`../../../home/Wine`) — wine writes it absolute, which breaks when the app is moved
  — and re-points links older wrappers aimed at `~/Wine`. It never deletes `~/Wine`:
  WoWSilicon uses the same folder. macOS ignores `HOME` for what the game needs (home
  directory, keyboard layouts, prefs: checked), and wine itself reads it only for
  `~/Wine` and the `~/.wine` fallback that `WINEPREFIX` overrides. A script that
  still needs the real home (the installer's keyboard-layout check) saves it first.
  Drop all of this once the runtime stops doing it.
- **A leftover `wineserver` breaks LAN play.** Wine creates sockets inside
  `wineserver` and hands them to the game, and macOS attributes a socket to the
  app responsible for the process that created it. `wineserver` can outlive the
  session that started it; once its launcher is gone it is responsible only for
  itself — unsigned, no Local Network grant — and a new game reusing it hangs at
  login on a LAN realm even though its own launcher is alive and responsible for
  the game. `wow-launch` therefore stops any leftover `wineserver` before it
  starts wine, unless a game from the same copy is still running. The running
  check matches the copy's whole game path as literal text in both forms
  (slashes, and Wine's `Z:\` backslashes), and lists processes before grepping
  them — a `games/main` pattern matched other copies of the app, and a grep in
  the same pipeline as `ps` matches its own command line.

- **The wine runtime is `x86_64`, so Rosetta 2 is load-bearing.** It is an
  on-demand component and a macOS upgrade can drop it (macOS 27 did): the
  loader then fails to exec with "Bad CPU type in executable", `nohup` writes
  that into `logs/last-launch.log`, and no game window ever appears. macOS only
  offers to reinstall Rosetta for an Intel *app*, never for a binary started
  from a script, so `wow-check-rosetta` asks — `lipo -archs` on the loader, then
  `arch -x86_64 /usr/bin/true` — and launch, verify, install and the Play pane
  all consult it. Verify matters most: every `$LOADER reg query` returns nothing
  without Rosetta, which reads exactly like an unwritten setting, so verify used
  to fail the retina and fast-exit checks and offer a `--fix` that re-ran wine
  and could never succeed. Rosetta 2 is fully supported through macOS 27; macOS
  28 is expected to keep only a subset for older games, which may end this.

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

- **No `@State` in `main.swift` — use `@ViewState`.** The macOS 27 SDK
  redeclares SwiftUI's `@State` as a macro backed by `libSwiftUIMacros.dylib`,
  and that plugin ships only inside Xcode; the Command Line Tools carry just the
  Observation and Swift macro plugins. With the bare CLT — all the build asks
  for — every `@State` fails with "plugin for module 'SwiftUIMacros' not found"
  (issue #7). `ViewState` wraps a plain `State` stored property, which is not a
  macro, so SwiftUI keeps the same storage on every SDK. CI builds with Xcode
  and would never notice one coming back; `make test` greps for it instead.

- **Fast exit**: Wow.exe phones dead Blizzard tracker endpoints on quit (~5 min
  hang); fixed by dead-proxy registry keys (`ProxyEnable=1`, `ProxyServer=127.0.0.1:1`)
  in the prefix — wininet fails instantly, realm/world traffic (winsock) unaffected.
- **Running detection**: wine rewrites the game path to Windows form
  (`Z:\...\main\Wow.exe`, backslashes) — match `main[/\\][Ww]o[Ww](_[Tt]weaked)?\.exe`, not the unix path.
- **gxMaximize=1 overrides gxResolution** (window always fills the screen); with
  RetinaMode=Y the game renders native pixels. `wow-settings auto` keeps both in
  sync with the display; `hwDetect 0` stops the game from overriding seeded settings.
- **GUI launches have no locale env** — wow-launch exports one explicitly.
- After Play the manager hands focus to the game window and stays behind it.
  A quit while the game runs — Cmd+Q, the menu, or `CLOSE_ON_PLAY=1` right
  after the handoff — is deferred in `applicationShouldTerminate`: the manager
  goes off screen (accessory activation policy, hidden: no window, Dock icon or
  Cmd-Tab entry) and terminates when the game process exits (NSWorkspace's
  termination notice, a 5 s `pgrep` poll behind it). Reopening the app
  meanwhile (`applicationShouldHandleReopen`) brings the window back and cancels
  the pending quit. Logout/restart/shutdown (`kAEQuitReason`) pass straight
  through. Why it must outlive the game: macOS attributes a child's network traffic to the app that spawned
  it (TN3179's "responsible code"), and Wine — unsigned, no bundle — has no
  identity of its own, so the game's Local Network access *is* the launcher's
  grant. On macOS 27 the connection drops a few seconds after the launcher quits
  (seen on three Macs, #7). Of TN3179's exemptions — `launchd` daemons, root,
  tools run from Terminal/SSH — none fits, which is why disclaiming Wine's
  responsibility would not help; only a nested app opened through
  LaunchServices would give the game its own grant (unbuilt). The game is
  detached and keeps running either way. Script-app launchers that don't check in with
  LaunchServices get "not responding" — the compiled SwiftUI binary is what
  fixed that historically.

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
