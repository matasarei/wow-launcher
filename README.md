# WoW335 launcher

Sources for the manager GUI and helper scripts inside `WoW335.app` — the
self-contained WoW 3.3.5a (ChromieCraft) wrapper for Apple Silicon
(CrossOver 26 wine + DXVK-async + winerosetta/rosettax87, ~120 FPS).

The app bundle itself (18 GB: wine stack, game client, prefix) is **not** in
this repo — only the launcher code that lives in it.

## Layout

| Repo file            | Installs to (in WoW335.app)        | Role |
|----------------------|------------------------------------|------|
| `main.swift`         | `Contents/MacOS/WoW335`            | SwiftUI manager window (Play / AddOns / Display) — the app's main executable |
| `scripts/wow-launch` | `Contents/Resources/bin/wow-launch`| starts the game: env, optional auto-resolution, detached wine spawn |
| `scripts/wow-settings` | `Contents/Resources/bin/wow-settings` | CLI for Config.wtf cvars, wine RetinaMode, display auto-detection |

`Contents/Resources/launcher.conf` (`AUTO_RES=1|0`) controls whether
`wow-launch` auto-matches the resolution to the main display at each start.

## Build & install

```sh
./build.sh                     # installs into ~/Applications/WoW335.app
./build.sh /path/to/WoW335.app
```

Requires only Xcode Command Line Tools (swiftc + macOS SDK), no Xcode.
