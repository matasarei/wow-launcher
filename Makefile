# Build a WoW335.app wrapper. Fully self-bootstrapping: the wine runtime and
# the patch payloads are downloaded from WoWSilicon's GitHub releases
# (checksum-verified) — nothing needs to be installed beforehand except the
# Xcode Command Line Tools. See docs/BUILD-WRAPPER.md.
#
#   make wrapper                 build into ~/Applications/WoW335.app
#   make wrapper APP=/path/App.app
#   make launcher                rebuild just the manager GUI + scripts
#   make zip                     compress the wrapper for sharing (private use!)

APP  ?= $(HOME)/Applications/WoW335.app
RES   = $(APP)/Contents/Resources
WINE  = $(RES)/wine
UNIX  = $(WINE)/lib/wine/x86_64-unix
DEPS  = build/deps

# Pinned upstream artifacts (update the URL and hash together).
RUNTIME_URL    = https://github.com/WoWSilicon/WoWSilicon/releases/download/wine-runtime-r4/WoWSilicon-WineRuntime-r4.tar.xz
RUNTIME_SHA256 = 56f5b8ca54042b0212f2f6e97b769af64c233a24072549ed9867e1623e4a10f0
PAYLOAD_URL    = https://github.com/WoWSilicon/WoWSilicon/releases/download/v3.0.1/WoWSilicon-3.0.1.dmg
PAYLOAD_SHA256 = 4d6fd5aa42d53dbdec86b31cf1c166368cba41a3a01a0bd5e2aba6d11b904ca0

# A locally installed WoWSilicon 3.x can serve the payloads without a download.
WOWSILICON ?= $(firstword $(wildcard $(HOME)/Applications/WoWSilicon.app /Applications/WoWSilicon.app))
LOCAL_PAY   = $(WOWSILICON)/Contents/Resources/WoWSilicon-swift_WoWSiliconSwift.bundle/Patching

.PHONY: wrapper check skeleton runtime payloads patch-kit prefix launcher zip

wrapper: check skeleton runtime patch-kit prefix launcher
	@echo ""
	@echo "==> Done: $(APP)"
	@echo "    Open it and click Install to add your WoW 3.3.5a client."

check:
	@command -v swiftc >/dev/null || { echo "ERROR: swiftc not found — install the Xcode Command Line Tools: xcode-select --install"; exit 1; }
	@command -v curl >/dev/null || { echo "ERROR: curl not found"; exit 1; }
	@echo "==> prerequisites OK (runtime and payloads are downloaded as needed)"

skeleton:
	@echo "==> app skeleton"
	@mkdir -p "$(APP)/Contents/MacOS" "$(RES)/bin" "$(RES)/games" "$(RES)/logs"
	@cp assets/Info.plist "$(APP)/Contents/Info.plist"
	@printf 'AUTO_RES=1\n' > "$(RES)/launcher.conf"
	@rm -rf /tmp/wow335.iconset && mkdir /tmp/wow335.iconset
	@sips -z 128 128 assets/icon.png --out /tmp/wow335.iconset/icon_128x128.png >/dev/null
	@cp assets/icon.png /tmp/wow335.iconset/icon_128x128@2x.png
	@cp assets/icon.png /tmp/wow335.iconset/icon_256x256.png
	@iconutil -c icns /tmp/wow335.iconset -o "$(RES)/WoW.icns"
	@rm -rf /tmp/wow335.iconset

runtime:
	@if [ -x "$(WINE)/bin/wine" ]; then echo "==> wine runtime already present, skipping"; else \
	  echo "==> wine runtime (WineAndAqua wine 11.13 + mtld3d, ~57 MB download)"; \
	  mkdir -p "$(DEPS)"; \
	  [ -f "$(DEPS)/wine-runtime.tar.xz" ] || curl -fL --progress-bar -o "$(DEPS)/wine-runtime.tar.xz" "$(RUNTIME_URL)"; \
	  echo "$(RUNTIME_SHA256)  $(DEPS)/wine-runtime.tar.xz" | shasum -a 256 -c - >/dev/null || { echo "ERROR: wine runtime checksum mismatch — delete $(DEPS)/wine-runtime.tar.xz and retry"; exit 1; }; \
	  mkdir -p "$(WINE)"; tar -xJf "$(DEPS)/wine-runtime.tar.xz" --strip-components 1 -C "$(WINE)"; fi
	@echo "==> Dock-name cosmetics (game shows as 'WoW')"
	@cd "$(UNIX)" && { [ -e "WoW" ] || ln -s wine "WoW"; }

# Materialize the open-source patch payloads in $(DEPS)/Patching: from a locally
# installed WoWSilicon 3.x when present, otherwise from the release DMG.
payloads:
	@if [ -f "$(DEPS)/Patching/d9vk/d3d9.dll" ]; then echo "==> payloads already present, skipping"; \
	elif [ -d "$(LOCAL_PAY)/x87sidecar" ]; then \
	  echo "==> payloads from $(WOWSILICON)"; \
	  mkdir -p "$(DEPS)"; ditto "$(LOCAL_PAY)" "$(DEPS)/Patching"; \
	else \
	  echo "==> payloads (WoWSilicon 3.0.1 DMG, ~150 MB download — only used as a file source)"; \
	  mkdir -p "$(DEPS)"; \
	  [ -f "$(DEPS)/wowsilicon.dmg" ] || curl -fL --progress-bar -o "$(DEPS)/wowsilicon.dmg" "$(PAYLOAD_URL)"; \
	  echo "$(PAYLOAD_SHA256)  $(DEPS)/wowsilicon.dmg" | shasum -a 256 -c - >/dev/null || { echo "ERROR: payload DMG checksum mismatch — delete $(DEPS)/wowsilicon.dmg and retry"; exit 1; }; \
	  hdiutil attach -nobrowse -readonly -mountpoint "$(DEPS)/dmg-mount" "$(DEPS)/wowsilicon.dmg" >/dev/null; \
	  ditto "$(DEPS)/dmg-mount/WoWSilicon.app/Contents/Resources/WoWSilicon-swift_WoWSiliconSwift.bundle/Patching" "$(DEPS)/Patching"; \
	  hdiutil detach "$(DEPS)/dmg-mount" >/dev/null; fi

patch-kit: payloads
	@echo "==> patch kit (open-source payloads only)"
	@mkdir -p "$(RES)/patch-kit/mods"
	@cp "$(DEPS)/Patching/d9vk/d3d9.dll" "$(DEPS)/Patching/winerosetta/libDllLdr.dll" "$(RES)/patch-kit/"
	@cp "$(DEPS)/Patching/winerosetta/winerosetta.dll" "$(DEPS)/Patching/libSiliconPatch/wotlk/libSiliconPatch.dll" "$(RES)/patch-kit/mods/"
	@ditto "$(DEPS)/Patching/rosettax87" "$(RES)/patch-kit/rosettax87"
	@chmod +x "$(RES)/patch-kit/rosettax87/"*
	@printf 'mods/winerosetta.dll\nmods/libSiliconPatch.dll\n' > "$(RES)/patch-kit/dlls.txt"
	@cp assets/wow-icon-*.bsdiff "$(RES)/patch-kit/"

prefix:
	@if [ -d "$(RES)/prefix/drive_c" ]; then echo "==> prefix already present, skipping"; \
	else echo "==> creating wine prefix (takes ~1 min)"; \
	  WINEPREFIX="$(RES)/prefix" WINEDEBUG=-all WINEDLLOVERRIDES="mshtml=;mscoree=" "$(WINE)/bin/wine" wineboot -u >/dev/null 2>&1; \
	  WINEPREFIX="$(RES)/prefix" "$(WINE)/bin/wineserver" -w; fi
	@echo "==> fast-exit network fix"
	@WINEPREFIX="$(RES)/prefix" WINEDEBUG=-all "$(WINE)/bin/wine" reg add 'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings' /v ProxyEnable /t REG_DWORD /d 1 /f >/dev/null 2>&1
	@WINEPREFIX="$(RES)/prefix" WINEDEBUG=-all "$(WINE)/bin/wine" reg add 'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings' /v ProxyServer /t REG_SZ /d 127.0.0.1:1 /f >/dev/null 2>&1
	@WINEPREFIX="$(RES)/prefix" "$(WINE)/bin/wineserver" -k >/dev/null 2>&1 || true

launcher:
	@echo "==> building the manager GUI"
	@./build.sh "$(APP)"

zip:
	@echo "==> zipping (for PRIVATE sharing — after a game install this contains the game itself; do not redistribute)"
	ditto -c -k --keepParent "$(APP)" WoW335.zip
	@du -h WoW335.zip
