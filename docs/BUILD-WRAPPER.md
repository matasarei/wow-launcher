# Building the WoW335.app wrapper

The wrapper is a self-contained app bundle: wine stack + prefix + patch kit + the
manager GUI. It is **built on your machine from parts you obtain yourself** — it is
not distributed, because it embeds CrossOver's commercial binaries.

## Step 0 — get this repo onto your Mac

No git or programming knowledge needed:

1. On the [repository page](https://github.com/matasarei/wow335-launcher), click
   the green **Code** button → **Download ZIP**.
2. Double-click the downloaded `wow335-launcher-main.zip` — macOS unpacks it into
   a folder called `wow335-launcher-main` (usually in Downloads).

That folder is all you need; you can move it anywhere you like.

## Step 1 — install the prerequisites

The build takes its dependencies from two apps that must be **downloaded and
installed on your Mac first** (`make` will refuse to run and tell you what's
missing otherwise):

1. **Xcode Command Line Tools** — open the **Terminal** app (find it with
   Spotlight: press Cmd+Space, type "Terminal", press Enter), then type
   `xcode-select --install` and press Enter. A macOS dialog appears — click
   **Install** and wait for it to finish. (If it says the tools are already
   installed, you're done with this step.) This provides the compiler for the
   manager app; the full Xcode is not needed.
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

1. Open **Terminal** (Cmd+Space → "Terminal" → Enter).
2. Type `cd ` (with a space after it), then **drag the unpacked
   `wow335-launcher-main` folder from Finder into the Terminal window** — its
   path appears automatically. Press Enter.
3. Type:

   ```sh
   make wrapper
   ```

   and press Enter. The build prints its progress and takes a few minutes
   (copying the ~1 GB wine stack is the slow part). When it finishes you'll see:

   ```
   ==> Done: /Users/you/Applications/WoW335.app
   ```

   The finished app is in the `Applications` folder inside your home folder
   (in Finder: Go → Home → Applications).

If a prerequisite is missing, the build stops immediately and prints what to
install and where to get it — fix that and run `make wrapper` again; it resumes
where it left off.

CrossOver and WoWSilicon are auto-detected in `~/Applications` and
`/Applications`; if you keep them elsewhere:

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
