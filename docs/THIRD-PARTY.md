# Third-party components & licensing

What a freshly built `WoW.app` (no game installed) contains, where it comes
from, and under which license. Nothing proprietary is embedded since the
CrossOver-based stack was replaced (see INTERNALS.md), but "open source" is not
quite true of everything — see **Known gaps** at the bottom before redistributing.

## Wine runtime (`Resources/wine/`)

| Component | License | Source |
|---|---|---|
| wine 11.13 (WineAndAqua build, winerosetta integrated) | LGPL-2.1-or-later | [WineAndAqua/wine](https://github.com/WineAndAqua/wine), branch `wine-11.13-macos` (exact commit in `share/wowsilicon/runtime-lock.json`) |
| MTLd3D (Metal-native D3D9) | Zlib | [athei/mtld3d](https://github.com/athei/mtld3d) |
| MoltenVK | Apache-2.0 | [KhronosGroup/MoltenVK](https://github.com/KhronosGroup/MoltenVK) |
| SDL2 | Zlib | libsdl.org |
| FreeType | FTL | freetype.org |
| GnuTLS, nettle/hogweed, GMP, libtasn1, libidn2, libunistring, libintl, p11-kit, libpng | LGPL family / BSD / libpng | standard open-source libraries, shipped unmodified |

The runtime is downloaded unmodified from
[WoWSilicon's releases](https://github.com/WoWSilicon/WoWSilicon/releases)
(`wine-runtime-r6.tar.xz`, sha256-pinned in the Makefile).

## Patch kit (`Resources/patch-kit/`)

| Component | License | Source |
|---|---|---|
| `d3d9.dll` (DXVK / d9vk) | Zlib | [doitsujin/dxvk](https://github.com/doitsujin/dxvk) + [WineAndAqua/d8vk](https://github.com/WineAndAqua/d8vk) |
| `winerosetta.dll` | MIT | [Gcenx/winerosetta](https://github.com/Gcenx/winerosetta) — source published (`src/winerosetta.cpp`, `src/winerosetta.def`; the `.def` exports exactly `Direct3DCreate9`, matching the DLL we ship). WoWSilicon vendors this binary inside its GPL-3 repo, but a repo-level LICENSE does not relicense a third party's MIT file |
| `libDllLdr.dll` | unclear — vendored in a GPL-3.0 repo, **no source published** | [WoWSilicon/WoWSilicon](https://github.com/WoWSilicon/WoWSilicon) (`Sources/WoWSiliconSwift/Resources/Patching/winerosetta/`). Exports `PatchDivxDecoder`, `PatchDivxTac`, `RunDll32Entry`; a GitHub code search for those names returns only consumers, no source. Load-bearing: it is what applies the Divx mod-loader patch the first time |
| `libSiliconPatch/{wotlk,vanilla}/libSiliconPatch.dll` | GPL-3.0 as declared by the repo, but **binary only — no source is published** anywhere (same situation as `libDllLdr.dll`) | [WoWSilicon/WoWSilicon](https://github.com/WoWSilicon/WoWSilicon). Applied at `PATCHES=all` (Game → Patches), the default; dropped at every lower level: x87→SSE reimplementations of ~180 client functions installed as inline hooks at hardcoded 12340/5875 addresses; no network, file or registry access (checked from imports). For 1.12 an open-source, byte-verified alternative exists: [athei/wow-mods](https://github.com/athei/wow-mods) (`wow_turbo`) |
| `rosettax87/` | MIT | [Lifeisawful/rosettax87](https://github.com/Lifeisawful/rosettax87) |
| `x87sidecar/` | MIT | Lifeisawful; LICENSE ships next to the binary |

These are standalone binaries copied or spawned at runtime. Nothing GPL is
linked into this repo's code: `winerosetta.dll` and `libSiliconPatch.dll` are
Windows DLLs loaded into the **game's** process by the patched `DivxDecoder`,
and `libDllLdr.dll` is invoked out-of-process through `rundll32`. That is mere
aggregation under GPL-3 §5, not derivation, so the launcher's own MIT license
stands and the GPL files keep their own terms.

## Blizzard-related caveats

- A fresh wrapper contains **no Blizzard files**, with one cosmetic exception:
  the app icon (`assets/icon.png`) and the `wow-icon-*.bsdiff` patches embed
  World of Warcraft icon artwork (Blizzard copyright/trademark) — the same
  artwork this repo already displays.
- A **used** wrapper is different: after a game install it contains the full
  client, and the patch kit self-populates Blizzard-derived reference files
  (`Wow.exe.*`, `DivxDecoder.dll.*`, `fonts-client/`). Never distribute a
  wrapper in that state.

## Known gaps

Two things are not satisfied today. Neither is about this repo's MIT license —
both are about redistributing other people's binaries.

1. **Two components have no corresponding source.** `libDllLdr.dll` and
   `libSiliconPatch.dll` are binary-only and sit inside a GPL-3.0 repo. GPL-3 §6
   requires conveying the corresponding source, or a valid written offer, when
   the binaries are distributed — and no source exists publicly, so neither this
   project nor upstream can satisfy it. Options, in order of preference: get
   upstream to publish the source; fetch the binaries from WoWSilicon's release
   on first use instead of bundling them, so upstream stays the distributor; or
   drop them (viable for `libSiliconPatch`, which measurably changes nothing on
   the current runtime — not for `libDllLdr`, which applies the Divx patch).
2. **The notices do not travel with the bundle.** A built `WoW.app` contains
   only `patch-kit/x87sidecar/LICENSE`. This file and the license texts for the
   LGPL-2.1 wine runtime (~57 MB of the bundle), DXVK, MoltenVK and the rest
   should be copied into `Contents/Resources/` by `make`, with
   `share/wowsilicon/runtime-lock.json`'s commit as the wine source pointer.

**This is not hypothetical: we already redistribute.** Every release from v2.0
to v2.4 ships a `WoW-vX.Y.zip` containing `patch-kit/libDllLdr.dll` and both
`libSiliconPatch.dll` builds, without corresponding source and without the
license texts. Gap 1 applies to those published artifacts today, not to some
future distribution.

Don't modify the upstream binaries, and point recipients at the source
repositories above.

World of Warcraft remains a Blizzard trademark; this project is unaffiliated.

*Not legal advice — this is an engineering inventory, written to be corrected.*
