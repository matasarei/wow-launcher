# Building the WoW335.app wrapper

The wrapper is a self-contained app bundle: wine stack + prefix + patch kit + the
manager GUI. It is **built on your machine from parts you obtain yourself** — it is
not distributed, because it embeds CrossOver's commercial binaries.

## Step 1 — install the prerequisites

The build takes its dependencies from two apps that must be **downloaded and
installed on your Mac first** (`make` will refuse to run and tell you what's
missing otherwise):

1. **Xcode Command Line Tools** — run `xcode-select --install` in Terminal
   (skip if already installed). Compiles the SwiftUI manager; no full Xcode needed.
2. **CrossOver** — download from
   [codeweavers.com/crossover](https://www.codeweavers.com/crossover) and install
   it into `/Applications` or `~/Applications`. The free 14-day trial is fine: the
   wrapper calls wine directly and never touches CrossOver's licensing UI, so the
   trial state doesn't matter to it. This supplies the whole wine + MoltenVK stack.
   (If you find CrossOver useful, buy a license — CodeWeavers funds a large share
   of Wine development.)
3. **WoWSilicon** — download the app from
   [github.com/WoWSilicon/WoWSilicon/releases](https://github.com/WoWSilicon/WoWSilicon/releases)
   and drop `WoWSilicon.app` into `/Applications` or `~/Applications`.
   **You never need to launch it** — the build only reads files from inside the
   app bundle (the open-source patch payloads: winerosetta, rosettax87, DXVK
   d3d9, libSiliconPatch, libDllLdr).

You will also need **a WoW 3.3.5a client** (build 12340) — e.g.
[chromiecraft.com](https://www.chromiecraft.com) has instructions — but that is
installed later through the app's own GUI, not by make.

## Step 2 — build

```sh
make wrapper
```

Both apps are auto-detected in `~/Applications` and `/Applications`; if you keep
them elsewhere:

```sh
make wrapper CROSSOVER=/path/to/CrossOver.app WOWSILICON=/path/to/WoWSilicon.app
```

## What `make wrapper` does

1. **skeleton** — app bundle structure, Info.plist, icon
2. **cxwine** — copies CrossOver's wine tree (`SharedSupport/CrossOver`, ~1 GB) into the bundle
3. **loader-patch** — creates `wineloader2` (a signature-stripped copy of the wine loader, so wine can load the patched libraries), installs winerosetta's `ntdll.so` (fast x87 math under Rosetta — the biggest FPS win), and applies the cosmetic Dock-name patch so the game shows as "WoW"
4. **patch-kit** — collects the open-source payloads (DXVK `d3d9.dll`, `libDllLdr.dll`, `winerosetta.dll`, `libSiliconPatch.dll`, `rosettax87`) used to patch game clients at install time. No game files are included — `DivxDecoder.dll` is patched live, in your own client, on first install.
5. **prefix** — creates a fresh wine prefix and applies the fast-exit fix (WoW 3.3.5 phones dead Blizzard tracker endpoints on quit and hangs ~5 min; a dead-proxy registry entry makes those fail instantly without affecting game traffic)
6. **launcher** — compiles the SwiftUI manager and installs it plus the helper scripts

The build is idempotent — re-running skips what's already done. `make launcher`
rebuilds just the GUI/scripts into an existing wrapper.

## First run

1. Open `WoW335.app` (first launch of an ad-hoc-signed app: right-click → Open)
2. Click **Install** and choose your 3.3.5a client folder — it is copied in and patched automatically
3. Pick your server in **Game → Server**, click **Play**

Selecting a non-main display in **Display** needs a one-time Accessibility
permission (System Settings → Privacy & Security → Accessibility → WoW335).

## Sharing the result

Don't, publicly — the built wrapper contains CrossOver's proprietary binaries and
(after a game install) Blizzard's client. `make zip` exists for private/backup use.
Share this repo instead; anyone can rebuild the wrapper in a few minutes.
