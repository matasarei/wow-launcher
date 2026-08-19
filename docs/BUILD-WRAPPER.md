# Building the WoW335.app wrapper

The wrapper is a self-contained app bundle: wine stack + prefix + patch kit + the
manager GUI. It is **built on your machine with one command** — the build downloads
the open-source wine runtime and patch payloads from WoWSilicon's GitHub releases
(checksum-verified) and assembles everything automatically.

## Step 0 — get this repo onto your Mac

No git or programming knowledge needed:

1. On the [repository page](https://github.com/matasarei/wow335-launcher), click
   the green **Code** button → **Download ZIP**.
2. Double-click the downloaded `wow335-launcher-main.zip` — macOS unpacks it into
   a folder called `wow335-launcher-main` (usually in Downloads).

That folder is all you need; you can move it anywhere you like.

## Step 1 — install the prerequisites

Just one thing, plus an internet connection (the build downloads ~200 MB of
open-source components on first run and caches them):

**Xcode Command Line Tools** — open the **Terminal** app (find it with
Spotlight: press Cmd+Space, type "Terminal", press Enter), then type
`xcode-select --install` and press Enter. A macOS dialog appears — click
**Install** and wait for it to finish. (If it says the tools are already
installed, you're done with this step.) This provides the compiler for the
manager app; the full Xcode is not needed.

Nothing else to install: the wine runtime (a standalone open-source
[WineAndAqua](https://github.com/WineAndAqua/wine) build) and the patch payloads
(winerosetta, rosettax87, DXVK d3d9, libSiliconPatch, libDllLdr) are fetched from
[WoWSilicon](https://github.com/WoWSilicon/WoWSilicon)'s releases with their
checksums verified. WoWSilicon itself is never installed or launched — its release
DMG is only read as a file source. (If a WoWSilicon 3.x app happens to be installed
already, the build takes the payloads from it and skips that download.)

For Cyrillic chat support: `python3 -m pip install --user mpyq fonttools` —
used to extract and remap the original fonts from a ruRU client at install
time (there is no bundled substitute; the authentic fonts are the only source).

You will also need **a WoW 3.3.5a client** (build 12340) — e.g.
[chromiecraft.com](https://www.chromiecraft.com) has instructions — but that is
installed later through the app's own GUI, not by make.

## Step 2 — build

1. Open **Terminal** (Cmd+Space → "Terminal" → Enter).
2. Type `cd ` (with a space after it), then **drag the unpacked
   `wow335-launcher-main` folder from Finder into the Terminal window** — its
   path appears automatically. Press Enter.
3. Type:

   ```sh
   make wrapper
   ```

   and press Enter. The build prints its progress and takes a few minutes
   (the downloads are the slow part; they are cached for re-runs). When it
   finishes you'll see:

   ```
   ==> Done: /Users/you/Applications/WoW335.app
   ```

   The finished app is in the `Applications` folder inside your home folder
   (in Finder: Go → Home → Applications).

If something is missing or a download fails, the build stops immediately and
prints what's wrong — fix that and run `make wrapper` again; it resumes where
it left off.

## What `make wrapper` does

1. **skeleton** — app bundle structure, Info.plist, icon
2. **runtime** — downloads the wine runtime (~57 MB, sha256-verified) and unpacks it into the bundle. This wine has winerosetta's fast-x87-under-Rosetta support built in — the biggest FPS win. Also creates the `WoW` loader symlink so the game shows as "WoW" in the Dock instead of "wine"
3. **payloads / patch-kit** — collects the open-source payloads (DXVK `d3d9.dll`, `libDllLdr.dll`, `winerosetta.dll`, `libSiliconPatch.dll`, `rosettax87`) from a local WoWSilicon 3.x app or the release DMG (~150 MB, sha256-verified). These patch game clients at install time. No game files are included — `DivxDecoder.dll` is patched live, in your own client, on first install
4. **prefix** — creates a fresh wine prefix and applies the fast-exit fix (WoW 3.3.5 phones dead Blizzard tracker endpoints on quit and hangs ~5 min; a dead-proxy registry entry makes those fail instantly without affecting game traffic)
5. **launcher** — compiles the SwiftUI manager and installs it plus the helper scripts

The build is idempotent — re-running skips what's already done. `make launcher`
rebuilds just the GUI/scripts into an existing wrapper.

## First run

1. Open `WoW335.app`. A locally built app opens directly. A *downloaded* copy is
   quarantined, and macOS refuses ad-hoc-signed apps outright ("damaged") — clear
   the flag once: `xattr -dr com.apple.quarantine /path/to/WoW335.app`
2. Click **Install** and choose your 3.3.5a client folder — it is copied in and patched automatically
3. Pick your server in **Game → Server**, click **Play**

Selecting a non-main display in **Display** needs a one-time Accessibility
permission (System Settings → Privacy & Security → Accessibility → WoW335).

## Sharing the result

Don't share a wrapper with a game installed — it contains Blizzard's client.
`make zip` exists for private/backup use. Share this repo instead; anyone can
rebuild the wrapper in a few minutes from freely downloadable components.
