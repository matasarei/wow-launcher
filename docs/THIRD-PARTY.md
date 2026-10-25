# Third-party components & licensing

Everything a freshly built `WoW.app` (no game installed) contains, where it came
from, and under which licence. The app's **About** pane links here, so this file
is the source pointer that travels with the build — keep it reachable.

## Wine runtime (`Resources/wine/`)

Downloaded unmodified at build time from
[`wine-runtime-r17`](https://github.com/WoWSilicon/WoWSilicon/releases/tag/wine-runtime-r17)
(sha256-pinned in the Makefile). `share/wowsilicon/runtime-lock.json` inside the
runtime records the exact upstream versions — though not the Vulkan loader and
KosmicKrisp, which r16 added outside it; those two rows below come from the
libraries themselves. The build carries WoWSilicon's thirteen wine patches
(device following, spatial audio, x87sidecar attach, winemac input and present
fixes, the user profile kept inside the prefix); their sources are
`Packaging/WineRuntime/patches/` in the
[WoWSilicon](https://github.com/WoWSilicon/WoWSilicon) repository (GPL-3.0),
applied to the LGPL wine tree below.

| Component | Licence | Source |
|---|---|---|
| wine 11.13 | LGPL-2.1-or-later | [WineAndAqua/wine](https://github.com/WineAndAqua/wine), branch `wine-11.13-macos`, commit [`37540b5`](https://github.com/WineAndAqua/wine/commit/37540b5d94ac1c86e2599ef55d7f3a15e3237ce8) |
| MTLd3D v0.7.0 (Metal-native D3D9) | Zlib | [athei/mtld3d](https://github.com/athei/mtld3d) |
| MoltenVK | Apache-2.0 | [KhronosGroup/MoltenVK](https://github.com/KhronosGroup/MoltenVK) |
| Vulkan loader (`lib/external/libvulkan.1.dylib`, from r16) | Apache-2.0 | [KhronosGroup/Vulkan-Loader](https://github.com/KhronosGroup/Vulkan-Loader) |
| KosmicKrisp Vulkan driver (`lib/external/libvulkan_kosmickrisp.dylib`, from r16; shipped, not used by this app) | MIT | [Mesa](https://gitlab.freedesktop.org/mesa/mesa), `src/kosmickrisp` |
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

## FEX runtime (`Resources/wine-fex/`, experimental — only in a `make build FEX=1` wrapper)

Runtime r18: the `Contents/Resources/Wine` folder of the
[WoWSilicon 3.3.0 Preview](https://github.com/WoWSilicon/WoWSilicon/releases/tag/Preview3.3.0)
app zip (sha256-pinned in the Makefile as `FEX_RUNTIME_URL`); nothing else of that app is kept.
It is an arm64 build of the same wine tree, with FEX as wine's x86 emulator in place of
Rosetta 2. Changed by the build in one place: `lib/wine/aarch64-unix/wine.app`'s
`CFBundleName` is set to `WoW` (the Dock name). Its `runtime-lock.json` records wine and
MTLd3D; its own licence texts are in `share/wowsilicon/licenses/`. The libraries shared with
r17 (SDL2, FreeType, GnuTLS and the rest above) are the same components.

| Component | Licence | Source |
|---|---|---|
| wine 11.13 (arm64) | LGPL-2.1-or-later | [WineAndAqua/wine](https://github.com/WineAndAqua/wine), branch `wine-11.13-macos`, commit [`37540b5`](https://github.com/WineAndAqua/wine/commit/37540b5d94ac1c86e2599ef55d7f3a15e3237ce8) |
| FEX (`lib/wine/aarch64-unix/libwow64fex_macos.so`, `libarm64ecfex_macos.so`) | MIT | [FEX-Emu/FEX](https://github.com/FEX-Emu/FEX), built for macOS by WoWSilicon |
| FEX's bundled libraries: fmt, unordered_dense, tiny-json / range-v3 / rpmalloc / cephes, xxhash | MIT / Boost-1.0 / public domain or MIT / BSD | FEX's `External/`, licence texts in `share/wowsilicon/licenses/FEX-dependencies/` |
| MTLd3D v0.13.0 (Metal-native D3D9) | Zlib | [athei/mtld3d](https://github.com/athei/mtld3d) |
| Vulkan loader, KosmicKrisp Vulkan driver (the only driver in r18; DXVK is not offered under FEX yet) | Apache-2.0, MIT | as above |

## Patch kit (`Resources/patch-kit/`)

Extracted at build time from the
[WoWSilicon 3.2.2](https://github.com/WoWSilicon/WoWSilicon/releases/tag/v3.2.2) release DMG
(sha256-pinned, mounted read-only, never launched or installed).

| Component | Licence | Source |
|---|---|---|
| `d3d9.dll` (D9VK 1.10.3, with the hardware-cursor scaling patch from [tairasu/d9vk](https://github.com/tairasu/d9vk) `7437b616`) | Zlib | [Sikarugir-App/d9vk](https://github.com/Sikarugir-App/d9vk), a fork of [doitsujin/dxvk](https://github.com/doitsujin/dxvk) |
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
