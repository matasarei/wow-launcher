# Development rules for this project

Read this before changing anything. Deeper background: `docs/INTERNALS.md`
(architecture, mechanisms, traps — read it first), `docs/BUILD-WRAPPER.md`
(build walkthrough), `docs/THIRD-PARTY.md` (embedded components & licenses).

## Ground rules

- **The repo is the source of truth.** Never edit files inside the built
  `WoW.app` directly — change the repo, then rebuild via make: `make launcher` for the
  GUI + scripts only, `make build` for the full bundle (helper scripts like `build.sh` are make's internals, never run directly). The wrapper is a
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

## Localization

UI strings are localized (assets/lproj/<lang>.lproj/Localizable.strings, 8
languages, keys = the English strings). When adding or changing a UI string in
main.swift: literals localize automatically, dynamically built strings must go
through L()/LF() — and every key needs a row in ALL eight .strings files
(a missing key silently falls back to English, which is correct for en but
leaves other languages untranslated). Script output (verify labels, installer
messages) is deliberately NOT localized — it is the shell-tool protocol.
Spot-check a language with: open WoW.app --args -AppleLanguages '(ru)'.

## Versioning

The app version lives in **one place**: `CFBundleShortVersionString` in
`assets/Info.plist`. The About pane reads it at runtime from the bundle, so a
bump propagates automatically after `make build` (which copies Info.plist).
`make launcher` alone does **not** copy Info.plist — after a version bump either
run `make skeleton launcher` or a full `make build`. Release tags on GitHub
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
2. Build clean: `rm -rf ~/Applications/WoW.app && make build`.
3. Verify the bundle is pristine:
   - `Resources/games/` is empty;
   - `Resources/launcher.conf` contains only `AUTO_RES=1`;
   - `Resources/patch-kit/` contains only the open-source payloads, `dlls.txt`
     and the `wow-icon-*.bsdiff` files — no `Wow.exe.*`, no `DivxDecoder.*`,
     no `fonts-client/`;
   - `Resources/logs/` is empty.
4. Run the test matrix (below) with a scratch copy, then **rebuild clean
   again** before zipping — testing dirties the wrapper.
5. Archive and publish (only with the maintainer's explicit go-ahead):

   ```sh
   make zip APP=/path/to/pristine/WoW.app     # → WoW.zip
   mv WoW.zip WoW-v<version>.zip
   gh release create v<version> WoW-v<version>.zip \
     --title "WoW Launcher v<version>" --notes-file <notes>
   ```

   Don't commit the zip. To keep the maintainer's working wrapper (and its
   installed game) untouched, build the release copy at a separate path:
   `make build APP=/tmp/release/WoW.app`.

   Gatekeeper facts (learned the hard way): the bundle **must** carry a valid
   deep ad-hoc seal (`make sign`, the last wrapper step) or downloaded copies
   fail as "damaged"; absolute symlinks in the prefix break codesign (stripped
   by the prefix target). Even with a valid seal, modern macOS refuses
   quarantined **ad-hoc** apps with no "Open Anyway" offered — release notes
   must include the `curl` install (no quarantine) and the
   `xattr -dr com.apple.quarantine` fallback. Frictionless downloads would
   require Developer ID signing + notarization (paid Apple account).

## Tests

`make test` runs the hermetic suite (`tests/run-tests.sh`): fake wrapper +
stub wine + fake clients made of empty files — version detection, install
validation and patching per version, verify step counts (43/29/25) and
CANFIX/REINSTALL/--fix behavior, launch env/exe selection, and the native font
tool against `tests/fixtures/locale-*.MPQ` (synthetic fonts in a real MPQ
layout, generated by `tests/fixtures/make-fixtures.py` — dev-only, needs
fontTools). Seconds to run, no game data needed (compiles the font tool with
swiftc once). Run it after ANY script change; add assertions for new
behavior. What it cannot cover stays manual (below).

## Manual test matrix (after any runtime/installer/launcher change)

- Fresh `make build`, open the app.
- Install an **enUS 3.3.5a** client → auto-verify passes (43 checks) → Play:
  ~120 FPS, maximized Retina window, Dock shows "WoW", fast exit.
- Replace with a **ruRU** client → Cyrillic input and rendering work
  (fonts extracted + stashed in the kit), including after RU→EN→RU layout
  toggles and with a **Ukrainian** layout (`і` must not render as `³`);
  reinstall enUS → Cyrillic still works from the stash.
- Both renderers launch (Display → DXVK and MTLd3D), and `X87=sidecar` in
  `launcher.conf` still boots the game.
- Language packs (3.3.5a/2.4.3): import a pack from another-locale client,
  switch both ways — window must appear and the game language change; the
  Language section must be absent for 1.12.
- When touching the installer/verify/launch scripts: also install a **1.12**
  and a **2.4.3** client — version detection, per-version verify totals
  (25 / 29), vanilla WDB cleanup and root-level realmlist must all hold.

## Layout crib

| Path | Role |
|---|---|
| `main.swift` | the entire SwiftUI manager (single file by design) |
| `scripts/wow-*` | runtime helpers installed into `Resources/bin/` by `build.sh` |
| `tools/wow-client-fonts.swift` | native MPQ font extraction + CP1251 cmap remap, compiled into `Resources/bin/` by `build.sh` |
| `Makefile` | wrapper assembly: skeleton, runtime download, payloads, patch-kit, prefix, launcher |
| `build.sh` | internal helper of `make launcher`: compiles main.swift + the font tool (swiftc, no Xcode) + installs scripts |
| `assets/` | Info.plist, icon, icon bsdiffs |
| `tests/run-tests.sh` | hermetic script tests (`make test`) — no game data or wine needed |
| `tests/fixtures/` | synthetic `locale-*.MPQ` font fixtures + their generator |
