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

---

## About

<p align="center">
  <img src="assets/screenshots/launcher-play.png" width="49%" alt="Launcher — Play">
  <img src="assets/screenshots/launcher-display.png" width="49%" alt="Launcher — Display settings">
</p>

Wrath of the Lich King–era WoW is a 32-bit x86 Direct3D 9 Windows game — about the worst possible match for an ARM Mac. This project wraps everything needed to run it *fast* into one `WoW335.app` bundle and puts a native SwiftUI manager in front of it:

| Layer | What it does |
|---|---|
| **CrossOver 26 wine** | runs the Windows client on macOS |
| **DXVK (async)** | translates Direct3D 9 → Vulkan → Metal |
| **winerosetta + rosettax87** | fast x87 FPU math under Rosetta 2 — the single biggest FPS win for 2010-era game code |
| **libSiliconPatch** | client-side hooks for Apple Silicon |
| **SwiftUI manager** (this repo) | install, patch, verify, configure, and launch — no terminal needed |

The result on an M4 Max: **~120 FPS at native Retina resolution**, fast startup, fast exit.

<p align="center">
  <img src="assets/screenshots/dalaran.jpg" width="32%" alt="Dalaran at ~120 FPS">
  <img src="assets/screenshots/elwynn.jpg" width="32%" alt="Flying through Elwynn Forest at ~120 FPS">
  <img src="assets/screenshots/westfall.jpg" width="32%" alt="Sentinel Hill inn at ~120 FPS">
</p>

> **What's not in this repo:** the game itself, the wine stack, and the prefix (≈18 GB) live only inside the app bundle. You need your own 3.3.5a client. This repo contains the launcher source that is installed into the bundle.

## Using the launcher

Double-click **WoW335.app** — a native manager window opens:

- **Play** — one big button. Shows current mode/resolution/retina state, a one-click "re-detect display" refresh, a live *running* indicator with force-stop, and an **Install** button instead when no game is present.
- **Game** — install a client (pick a 3.3.5a client folder — it's copied in and patched for Apple Silicon automatically), **Verify** integrity (41 checks: files, patches, settings) with one-click **Fix Issues** repair, or a reinstall suggestion if game data is damaged beyond repair. Below: the **server list** editor (realmlist.wtf) — radio-select the active server, add or remove entries.
- **AddOns** — list installed addons (with versions from their .toc), install from ZIP or folder, remove to Trash, reveal in Finder. Blizzard built-ins are hidden.
- **Display** — window mode (maximized / windowed / fullscreen), automatic resolution & Retina matching at every launch, or pick a specific display: the game window is moved there automatically after launch (needs a one-time Accessibility permission).

Everything the GUI does is also scriptable — the same tools it calls live in `Contents/Resources/bin/`:

```sh
wow-settings show|auto|windowed|maximized|fullscreen|resolution WxH|retina on|off
wow-verify-game [--fix]
wow-install-client /path/to/client [Name]
wow-launch
```

## Building the wrapper

The app bundle is **built locally, not downloaded** — it embeds CrossOver's wine
stack, which cannot be redistributed. With CrossOver and WoWSilicon present
(see [docs/BUILD-WRAPPER.md](docs/BUILD-WRAPPER.md) for the full manual):

```sh
make wrapper        # assembles ~/Applications/WoW335.app from your local parts
```

## Repo layout & building the launcher

| File | Installs to (inside WoW335.app) | Role |
|---|---|---|
| `main.swift` | `Contents/MacOS/WoW335` | the SwiftUI manager (single file) |
| `scripts/wow-launch` | `Contents/Resources/bin/` | game starter: env, auto-resolution, display mover |
| `scripts/wow-settings` | `Contents/Resources/bin/` | Config.wtf cvars, Retina mode, display detection |
| `scripts/wow-install-client` | `Contents/Resources/bin/` | copy a client in + apply the patch kit |
| `scripts/wow-verify-game` | `Contents/Resources/bin/` | 41-check verification with `--fix` repair |

```sh
./build.sh                     # compiles and installs into ~/Applications/WoW335.app
./build.sh /path/to/WoW335.app
make launcher                  # same thing, via make
```

Requires only the Xcode **Command Line Tools** (`swiftc` + macOS SDK). No Xcode, no dependencies.

## Credits

Standing on the shoulders of: [WoWSilicon](https://github.com/WoWSilicon/WoWSilicon), the winerosetta / rosettax87 projects, [DXVK](https://github.com/doitsujin/dxvk) and its macOS D3D9 forks, CrossOver/Wine, and the [ChromieCraft](https://www.chromiecraft.com) community.

World of Warcraft is a trademark of Blizzard Entertainment. This project contains no Blizzard assets or game data.

## License

[MIT](LICENSE)
