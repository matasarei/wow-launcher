# Building the WoW335.app wrapper

The wrapper is a self-contained app bundle: wine stack + prefix + patch kit + the
manager GUI. It is **built on your machine from parts you obtain yourself** — it is
not distributed, because it embeds CrossOver's commercial binaries.

```sh
make wrapper
```

That's the whole build. Read on for what it needs and what it does.

## Prerequisites

| What | Where to get it | Why |
|---|---|---|
| **Xcode Command Line Tools** | `xcode-select --install` | compiles the SwiftUI manager (no Xcode needed) |
| **CrossOver** (25/26+) | [codeweavers.com/crossover](https://www.codeweavers.com/crossover) — the free 14-day trial is fine | supplies the wine + MoltenVK stack. The wrapper calls wine directly and never touches CrossOver's licensing UI, so the trial state is irrelevant to the wrapper. If you find CrossOver useful, buy a license — CodeWeavers funds a large share of Wine development. |
| **WoWSilicon** | [github.com/WoWSilicon/WoWSilicon/releases](https://github.com/WoWSilicon/WoWSilicon/releases) | used **only as a file source** (it bundles the open-source patch payloads: winerosetta, rosettax87, DXVK d3d9, libSiliconPatch, libDllLdr). It is never launched — just drop the .app in `~/Applications` or `/Applications`. |
| **A WoW 3.3.5a client** (build 12340) | e.g. [chromiecraft.com](https://www.chromiecraft.com) has instructions | installed later through the app's GUI, not by make |

Both apps are auto-detected in `~/Applications` and `/Applications`; override with
`make wrapper CROSSOVER=/path/to/CrossOver.app WOWSILICON=/path/to/WoWSilicon.app`.

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
