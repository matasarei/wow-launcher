# Third-party components & licensing

What a freshly built `WoW.app` (no game installed) contains, where it comes
from, and under which license. Everything is open source and redistributable
with attribution; nothing proprietary is embedded since the CrossOver-based
stack was replaced (see INTERNALS.md).

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
(`wine-runtime-r4.tar.xz`, sha256-pinned in the Makefile).

## Patch kit (`Resources/patch-kit/`)

| Component | License | Source |
|---|---|---|
| `d3d9.dll` (DXVK / d9vk) | Zlib | [doitsujin/dxvk](https://github.com/doitsujin/dxvk) + [WineAndAqua/d8vk](https://github.com/WineAndAqua/d8vk); DXVK's LICENSE ships next to it in the payload |
| `winerosetta.dll`, `libDllLdr.dll`, `libSiliconPatch.dll` | GPL-3.0 | [WoWSilicon/WoWSilicon](https://github.com/WoWSilicon/WoWSilicon) |
| `rosettax87/` | MIT | [Lifeisawful/rosettax87](https://github.com/Lifeisawful/rosettax87) |
| `x87sidecar/` | MIT | Lifeisawful; LICENSE ships next to the binary |

These are standalone binaries copied or spawned at runtime — none are linked
into the MIT-licensed launcher, so there is no license interaction with this
repo's own code.

## Blizzard-related caveats

- A fresh wrapper contains **no Blizzard files**, with one cosmetic exception:
  the app icon (`assets/icon.png`) and the `wow-icon-*.bsdiff` patches embed
  World of Warcraft icon artwork (Blizzard copyright/trademark) — the same
  artwork this repo already displays.
- A **used** wrapper is different: after a game install it contains the full
  client, and the patch kit self-populates Blizzard-derived reference files
  (`Wow.exe.*`, `DivxDecoder.dll.*`, `fonts-client/`). Never distribute a
  wrapper in that state.

## If the wrapper is ever distributed

A freshly built, game-less wrapper is redistributable provided the LGPL/GPL
notices travel with it: keep this file in the bundle, don't modify the upstream
binaries, and point recipients at the source repositories above (all public).
World of Warcraft remains a Blizzard trademark; this project is unaffiliated.
