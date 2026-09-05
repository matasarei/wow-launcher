# Third-party components & licensing

Everything a freshly built `WoW.app` (no game installed) contains, where it came
from, and under which licence. The app's **About** pane links here, so this file
is the source pointer that travels with the build — keep it reachable.

## Wine runtime (`Resources/wine/`)

Downloaded unmodified at build time from
[`wine-runtime-r6`](https://github.com/WoWSilicon/WoWSilicon/releases/tag/wine-runtime-r6)
(sha256-pinned in the Makefile). `share/wowsilicon/runtime-lock.json` inside the
runtime records the exact upstream versions.

| Component | Licence | Source |
|---|---|---|
| wine 11.13 | LGPL-2.1-or-later | [WineAndAqua/wine](https://github.com/WineAndAqua/wine), branch `wine-11.13-macos`, commit [`37540b5`](https://github.com/WineAndAqua/wine/commit/37540b5d94ac1c86e2599ef55d7f3a15e3237ce8) |
| MTLd3D v0.7.0 (Metal-native D3D9) | Zlib | [athei/mtld3d](https://github.com/athei/mtld3d) |
| MoltenVK | Apache-2.0 | [KhronosGroup/MoltenVK](https://github.com/KhronosGroup/MoltenVK) |
| SDL2 | Zlib | [libsdl.org](https://www.libsdl.org/) |
| FreeType | FTL or GPL-2.0 (dual) | [freetype.org](https://freetype.org/) |
| GnuTLS | LGPL-2.1-or-later | [gnutls.org](https://www.gnutls.org/) |
| nettle, hogweed | LGPL-3.0-or-later or GPL-2.0-or-later (dual) | [lysator.liu.se/~nisse/nettle](https://www.lysator.liu.se/~nisse/nettle/) |
| GMP | LGPL-3.0-or-later or GPL-2.0-or-later (dual) | [gmplib.org](https://gmplib.org/) |
| libtasn1 | LGPL-2.1-or-later | [gnu.org/software/libtasn1](https://www.gnu.org/software/libtasn1/) |
| libidn2 | LGPL-3.0-or-later | [gnu.org/software/libidn](https://www.gnu.org/software/libidn/) |
| libunistring | LGPL-3.0-or-later | [gnu.org/software/libunistring](https://www.gnu.org/software/libunistring/) |
| libintl (gettext) | LGPL-2.1-or-later | [gnu.org/software/gettext](https://www.gnu.org/software/gettext/) |
| p11-kit | BSD-3-Clause | [p11-glue/p11-kit](https://github.com/p11-glue/p11-kit) |
| libpng | PNG Reference Library License | [libpng.org](http://www.libpng.org/pub/png/libpng.html) |

## Patch kit (`Resources/patch-kit/`)

Extracted at build time from the
[WoWSilicon 3.0.1](https://github.com/WoWSilicon/WoWSilicon/releases) release DMG
(sha256-pinned, mounted read-only, never launched or installed).

| Component | Licence | Source |
|---|---|---|
| `d3d9.dll` (D9VK) | Zlib | [Sikarugir-App/d9vk](https://github.com/Sikarugir-App/d9vk), a fork of [doitsujin/dxvk](https://github.com/doitsujin/dxvk) |
| `mods/winerosetta.dll` | MIT | [Gcenx/winerosetta](https://github.com/Gcenx/winerosetta) — the Rosetta 2 instruction shim (emulates `ARPL AX,DX`, rewrites `FCOMP ST(0),ST(0)`) |
| `libDllLdr.dll` | see **Binary-only components** below | [WoWSilicon/WoWSilicon](https://github.com/WoWSilicon/WoWSilicon) |
| `libSiliconPatch/{wotlk,vanilla}/libSiliconPatch.dll` | see **Binary-only components** below | [WoWSilicon/WoWSilicon](https://github.com/WoWSilicon/WoWSilicon) |
| `rosettax87/` | MIT | [Lifeisawful/rosettax87](https://github.com/Lifeisawful/rosettax87) |
| `x87sidecar/` | MIT | [athei/x87sidecar](https://github.com/athei/x87sidecar) |
| `vanilla-tweaks.exe` | MIT | [brndd/vanilla-tweaks](https://github.com/brndd/vanilla-tweaks) |

None of these are linked into this repo's code. `winerosetta.dll` and
`libSiliconPatch.dll` are Windows DLLs loaded into the **game's** process by the
patched `DivxDecoder`; `libDllLdr.dll` is invoked out-of-process through
`rundll32`. That is aggregation, not derivation, so this project's MIT licence
and their licences are independent.

## Binary-only components

`libDllLdr.dll` and `libSiliconPatch.dll` are published by the WoWSilicon project
as compiled binaries only — **no source has been released for either**, so no
source link can be given here. They are redistributed exactly as upstream
publishes them, unmodified. Requests for their source belong
[upstream](https://github.com/WoWSilicon/WoWSilicon/issues).

Neither is required to play:

- `libSiliconPatch.dll` is used only at **Game → Patches → All patches** and
  measurably changes nothing on the current runtime (rosettax87 already carries
  the x87 load). Any lower level omits it entirely.
- `libDllLdr.dll` is only used once, at install time, to apply the `DivxDecoder`
  mod-loader patch. At **No patches** it is never invoked.

## Scope of use

This wrapper is built for **personal use with a client you already own**.
Classic-era clients exist to connect to private servers, which is outside
Blizzard's terms regardless of how the client is launched — so treat a built
wrapper as something you run, not something you publish or sell.

Two further reasons not to hand a built wrapper around:

- The app icon (`assets/icon.png`) and the `wow-icon-*.bsdiff` patches embed
  World of Warcraft icon artwork, which is Blizzard's copyright and trademark.
- A **used** wrapper contains the entire game client, plus Blizzard-derived
  reference files the patch kit self-populates (`Wow.exe.*`, `DivxDecoder.dll.*`,
  `fonts-client/`). Never distribute a wrapper in that state.

World of Warcraft is a trademark of Blizzard Entertainment. This project is
unaffiliated with and unendorsed by Blizzard.
