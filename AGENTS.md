# Development rules for this project

Read this before changing anything. Deeper background: `docs/INTERNALS.md`
(architecture, mechanisms, traps — read it first), `docs/BUILD-WRAPPER.md`
(build walkthrough), `docs/THIRD-PARTY.md` (embedded components & licenses).

## Ground rules

- **The repo is the source of truth.** Never edit files inside the built
  `WoW335.app` directly — change the repo, then rebuild: `./build.sh` for the
  GUI + scripts only, `make wrapper` for the full bundle. The wrapper is a
  disposable build artifact.
- **One change at a time, verified in the real game.** After each functional
  change, stop and have the change verified in the running game before making
  the next one. Do not push experimental fixes until they are confirmed fixed.
- **After rebuilding the GUI, the app must be fully quit (Cmd+Q) and
  reopened** — macOS keeps the old instance running and it will look like the
  change didn't compile.
- **No releases and no public distribution of a built wrapper without the
  maintainer's explicit approval.** A wrapper that has ever had a game
  installed must never be distributed at all.

## Versioning

The app version lives in **one place**: `CFBundleShortVersionString` in
`assets/Info.plist`. The About pane reads it at runtime from the bundle, so a
bump propagates automatically after `make wrapper` (which copies Info.plist).
`./build.sh` alone does **not** copy Info.plist — after a version bump either
run `make skeleton launcher` or a full `make wrapper`. Release tags on GitHub
should match it (`v<version>`).

## Updating the pinned upstream artifacts

The wine runtime and the patch payloads are pinned in the `Makefile`:
`RUNTIME_URL`/`RUNTIME_SHA256` and `PAYLOAD_URL`/`PAYLOAD_SHA256`. To move to a
newer WoWSilicon runtime or release:

1. Update the URL **and** its sha256 together (download, `shasum -a 256`).
2. Delete `build/deps/` (cached artifacts) and the wrapper, rebuild from
   scratch, and run the full test matrix below.
3. Check `share/wowsilicon/runtime-lock.json` inside the new runtime for
   component changes, and update `docs/THIRD-PARTY.md` if components or
   licenses changed.

## Making a release

A releasable wrapper must be **freshly built** — never a used one. A wrapper
that has run installs accumulates Blizzard-derived files (the game under
`games/`, and self-populated patch-kit references: `Wow.exe.*`,
`DivxDecoder.dll.*`, `fonts-client/`) plus personal data in the prefix and
logs. The procedure:

1. Bump the version in `assets/Info.plist`; commit and push everything.
2. Build clean: `rm -rf ~/Applications/WoW335.app && make wrapper`.
3. Verify the bundle is pristine:
   - `Resources/games/` is empty;
   - `Resources/launcher.conf` contains only `AUTO_RES=1`;
   - `Resources/patch-kit/` contains only the open-source payloads, `dlls.txt`
     and the `wow-icon-*.bsdiff` files — no `Wow.exe.*`, no `DivxDecoder.*`,
     no `fonts-client/`;
   - `Resources/logs/` is empty.
4. Run the test matrix (below) with a scratch copy, then **rebuild clean
   again** before zipping — testing dirties the wrapper.
5. `make zip` the pristine build; attach to a GitHub release tagged
   `v<version>` — only with the maintainer's explicit go-ahead.

## Test matrix (after any runtime/installer/launcher change)

- Fresh `make wrapper`, open the app (right-click → Open the first time).
- Install an **enUS** client → Verify passes (41 checks) → Play: ~120 FPS,
  maximized Retina window, Dock shows "WoW", fast exit.
- Replace with a **ruRU** client → Cyrillic input and rendering work
  (fonts extracted + stashed in the kit); reinstall enUS → Cyrillic still
  works from the stash.
- Both renderers launch (Display → DXVK and MTLd3D), and `X87=sidecar` in
  `launcher.conf` still boots the game.

## Layout crib

| Path | Role |
|---|---|
| `main.swift` | the entire SwiftUI manager (single file by design) |
| `scripts/wow-*` | runtime helpers installed into `Resources/bin/` by `build.sh` |
| `Makefile` | wrapper assembly: skeleton, runtime download, payloads, patch-kit, prefix, launcher |
| `build.sh` | compiles main.swift (swiftc, no Xcode) + installs scripts |
| `assets/` | Info.plist, icon, icon bsdiffs |
