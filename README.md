<p align="center">
  <img src="assets/icon.png" width="128" alt="WoW 3.3.5a icon">
</p>

<h1 align="center">WoW335 Launcher</h1>

<p align="center">
  A native macOS launcher &amp; manager for <b>World of Warcraft 3.3.5a</b> on <b>Apple Silicon</b> — ~120 FPS in a single self-contained app.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-black?logo=apple" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Apple%20Silicon-arm64-orange" alt="Apple Silicon">
  <img src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white" alt="Swift 6">
  <img src="https://img.shields.io/badge/SwiftUI-native-blue" alt="SwiftUI">
  <img src="https://img.shields.io/badge/WoW-3.3.5a%20(12340)-gold" alt="WoW 3.3.5a">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT license">
</p>

<p align="center">
  <a href="https://hcnotes.cc/article/articles-my-own-private-azeroth"><b>Why and how I built this →</b></a>
</p>

---

## About

<p align="center">
  <img src="assets/screenshots/launcher-play.png" width="49%" alt="Launcher — Play">
  <img src="assets/screenshots/launcher-display.png" width="49%" alt="Launcher — Display settings">
</p>

Wrath of the Lich King–era WoW is a 32-bit x86 Direct3D 9 Windows game — about the worst possible match for an ARM Mac. This project wraps everything needed to run it *fast* into one `WoW335.app` bundle and puts a native SwiftUI manager in front of it:

| Layer | What it does |
|---|---|
| **Wine 11 ([WineAndAqua](https://github.com/WineAndAqua/wine) build)** | runs the Windows client on macOS |
| **DXVK (async)** | translates Direct3D 9 → Vulkan → Metal |
| **winerosetta + rosettax87** | fast x87 FPU math under Rosetta 2 — the single biggest FPS win for 2010-era game code |
| **libSiliconPatch** | client-side hooks for Apple Silicon |
| **SwiftUI manager** (this repo) | install, patch, verify, configure, and launch — no terminal needed |

> [!IMPORTANT]
> **This repo contains only the launcher source and the build tooling** — no game data,
> no wine stack. Nothing needs to be installed beforehand except the Xcode Command Line
> Tools: the build downloads the wine runtime and the patch payloads from
> [WoWSilicon](https://github.com/WoWSilicon/WoWSilicon)'s releases (checksum-verified)
> and bakes them into the app bundle. The finished `WoW335.app` is fully self-contained;
> you bring your own 3.3.5a client and install it through the app.

The result on an M4 Max: **~120 FPS at native Retina resolution**, fast startup, fast exit.

**Why this exists:** for fun and discovery — making a 2010 Windows game run *great* on
modern Apple hardware is the whole point. This is not a piracy project: it ships no
game data, and it is built around the **original WoW 3.3.5a (build 12340) client**.
Modified or repacked clients might work, but they are untested and unsupported — if
one misbehaves, try a clean original client first.

**Not a WoWSilicon copy or fork:** [WoWSilicon](https://github.com/WoWSilicon/WoWSilicon)
is the upstream that makes the performance possible — this project gratefully reuses its
open-source building blocks (the wine runtime, winerosetta/rosettax87, the patch DLLs)
but builds a different thing with them. WoWSilicon is a patcher/launcher app that manages
games living elsewhere on your disk and a shared `~/.wine` prefix, with profiles for
several expansions. This is a **single-game appliance**: the client, the wine stack, a
private prefix, and all tooling live inside one `WoW335.app` — nothing touches the rest
of your system, and deleting the app removes everything. On top sits its own SwiftUI
manager with things WoWSilicon doesn't do: integrity verification with one-click repair,
a realmlist editor, an addon manager, display targeting with automatic resolution/Retina
matching, the Cyrillic input layer, the fast-exit fix, and a proper "WoW" Dock identity.

<p align="center">
  <img src="assets/screenshots/dalaran.jpg" width="32%" alt="Dalaran at ~120 FPS">
  <img src="assets/screenshots/elwynn.jpg" width="32%" alt="Flying through Elwynn Forest at ~120 FPS">
  <img src="assets/screenshots/westfall.jpg" width="32%" alt="Sentinel Hill inn at ~120 FPS">
</p>

## Using the launcher

Double-click **WoW335.app** — a native manager window opens:

- **Play** — one big button. Shows current mode/resolution/retina state, a one-click "re-detect display" refresh, a live *running* indicator with force-stop, and an **Install** button instead when no game is present.
- **Game** — install a client (pick a 3.3.5a client folder — it's copied in and patched for Apple Silicon automatically), **Verify** integrity (41 checks: files, patches, settings) with one-click **Fix Issues** repair, or a reinstall suggestion if game data is damaged beyond repair. Below: the **server list** editor (realmlist.wtf) — radio-select the active server, add or remove entries.
- **AddOns** — list installed addons (with versions from their .toc), install from ZIP or folder, remove to Trash, reveal in Finder. Blizzard built-ins are hidden.
- **Display** — window mode (maximized / windowed / fullscreen) with standard window sizes, automatic resolution & Retina matching at every launch, a renderer choice (**DXVK** by default or the Metal-native **MTLd3D** with HDR output), or pick a specific display: the game window is moved there automatically after launch (needs a one-time Accessibility permission).
- **About** — version, links (repository, build story, third-party components), license and trademark info.

**Cyrillic input** (tested on both ruRU and enUS clients): works out of the box — for ruRU clients always, and for enUS clients whenever your Mac has a Russian keyboard layout configured (the installer detects it and enables `CHAT_CP=1251` in `Contents/Resources/launcher.conf` automatically; set the key manually to force it either way). The fonts come from a ruRU client's own files, extracted and remapped at install time (requires `pip3 install mpyq fonttools`) — install a ruRU client once and its fonts are reused for any client afterwards.

Everything the GUI does is also scriptable — the same tools it calls live in `Contents/Resources/bin/`:

```sh
wow-settings show|auto|windowed|maximized|fullscreen|resolution WxH|retina on|off
wow-verify-game [--fix]
wow-install-client /path/to/client [Name]
wow-launch
```

## Building the wrapper

The app bundle is **built locally with one command** — the build downloads the wine
runtime (~57 MB) and the patch payloads from WoWSilicon's GitHub releases,
verifies their checksums, and assembles everything:

1. Get this repo: **Code → Download ZIP**, double-click to unpack (no git needed)
2. In Terminal, `cd` into the unpacked folder and run:
   ```sh
   make                # assembles ~/Applications/WoW335.app
   make install        # optional: move it to /Applications
   ```

New to the command line? [docs/BUILD-WRAPPER.md](docs/BUILD-WRAPPER.md) walks
through every step, Terminal included.

Contributors: [docs/INTERNALS.md](docs/INTERNALS.md) documents the wrapper
anatomy, the patch mechanisms, and the traps already discovered.
[docs/THIRD-PARTY.md](docs/THIRD-PARTY.md) lists every embedded component
with its license and source.

## Repo layout & building the launcher

| File | Installs to (inside WoW335.app) | Role |
|---|---|---|
| `main.swift` | `Contents/MacOS/WoW335` | the SwiftUI manager (single file) |
| `scripts/wow-launch` | `Contents/Resources/bin/` | game starter: env, auto-resolution, display mover |
| `scripts/wow-settings` | `Contents/Resources/bin/` | Config.wtf cvars, Retina mode, display detection |
| `scripts/wow-install-client` | `Contents/Resources/bin/` | copy a client in + apply the patch kit |
| `scripts/wow-verify-game` | `Contents/Resources/bin/` | 41-check verification with `--fix` repair |

```sh
make build          # the full wrapper (same as plain `make`)
make launcher       # just recompile the manager GUI + scripts into the existing wrapper
make install        # move the wrapper to /Applications
```

`make` is the only entrypoint — the helper scripts (like `build.sh`) are internal.
Requires only the Xcode **Command Line Tools** (`swiftc` + macOS SDK). No Xcode, no dependencies.

## Troubleshooting

- **Something feels wrong with the game?** Open the **Game** tab and click
  **Verify** — it runs 41 checks over the client files, the Apple Silicon
  patches, and the settings, and offers **Fix Issues** for everything
  repairable in place.
- **Verify reports the game data itself is damaged** (or things stay broken
  after a fix): reinstall — click **Install New Game…** and point it at your
  client folder again. Installing always replaces the previous game and
  re-applies every patch from scratch. Your AddOns live inside the game folder,
  so re-add them after a reinstall.
- **Keyboard controls don't work / keybindings dead:** a Cyrillic keyboard
  layout is active — the game binds keys by character. Switch to a Latin
  layout for playing; switch to Russian only while typing in chat.
- **The game doesn't appear after Play:** it may have opened behind other
  windows — find the **WoW** icon in the Dock and click it to bring the game
  to the front.

## Credits

Standing on the shoulders of: [WoWSilicon](https://github.com/WoWSilicon/WoWSilicon), the [WineAndAqua](https://github.com/WineAndAqua/wine) wine build, the winerosetta / rosettax87 projects, [DXVK](https://github.com/doitsujin/dxvk) and its macOS D3D9 forks, Wine/CrossOver, and the [ChromieCraft](https://www.chromiecraft.com) community.

World of Warcraft is a trademark of Blizzard Entertainment. This project contains no Blizzard assets or game data.

## License

[MIT](LICENSE)
