# Build a WoW335.app wrapper from locally installed prerequisites.
# See docs/BUILD-WRAPPER.md for what you need and where to get it.
#
#   make wrapper                 build into ~/Applications/WoW335.app
#   make wrapper APP=/path/App.app
#   make launcher                rebuild just the manager GUI + scripts
#   make zip                     compress the wrapper for sharing (private use!)

APP        ?= $(HOME)/Applications/WoW335.app
CROSSOVER  ?= $(firstword $(wildcard $(HOME)/Applications/CrossOver.app /Applications/CrossOver.app))
WOWSILICON ?= $(firstword $(wildcard $(HOME)/Applications/WoWSilicon.app /Applications/WoWSilicon.app))

CX     = $(CROSSOVER)/Contents/SharedSupport/CrossOver
PAY    = $(WOWSILICON)/Contents/Resources/WoWSilicon-swift_WoWSiliconSwift.bundle/Patching
RES    = $(APP)/Contents/Resources
HOSTED = $(RES)/cxwine/CrossOver-Hosted Application
UNIX   = $(RES)/cxwine/lib/wine/x86_64-unix

.PHONY: wrapper check skeleton cxwine loader-patch patch-kit prefix launcher zip

wrapper: check skeleton cxwine loader-patch patch-kit prefix launcher
	@echo ""
	@echo "==> Done: $(APP)"
	@echo "    Open it and click Install to add your WoW 3.3.5a client."

check:
	@command -v swiftc >/dev/null || { echo "ERROR: swiftc not found — install the Xcode Command Line Tools: xcode-select --install"; exit 1; }
	@test -d "$(CX)" || { echo "ERROR: CrossOver.app not found (looked in ~/Applications and /Applications)."; echo "  Get it from https://www.codeweavers.com/crossover (the free trial is fine — the wrapper never uses its licensing UI)."; exit 1; }
	@test -d "$(PAY)" || { echo "ERROR: WoWSilicon.app not found (looked in ~/Applications and /Applications)."; echo "  Get it from https://github.com/WoWSilicon/WoWSilicon/releases — it is only used as a file source, never launched."; exit 1; }
	@echo "==> prerequisites OK"
	@echo "    CrossOver:  $(CROSSOVER)"
	@echo "    WoWSilicon: $(WOWSILICON)"

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

cxwine:
	@if [ -d "$(RES)/cxwine/lib" ]; then echo "==> cxwine already present, skipping copy"; \
	else echo "==> copying CrossOver wine tree (~1 GB, takes a minute)"; ditto "$(CX)" "$(RES)/cxwine"; fi

loader-patch:
	@echo "==> wineloader2 (signature-stripped loader)"
	@if [ ! -f "$(HOSTED)/wineloader2" ]; then \
	  cp "$(HOSTED)/wineloader" "$(HOSTED)/wineloader2" && codesign --remove-signature "$(HOSTED)/wineloader2"; fi
	@echo "==> winerosetta ntdll.so"
	@if ! cmp -s "$(PAY)/winerosetta/ntdll.so" "$(UNIX)/ntdll.so" && [ ! -f "$(UNIX)/ntdll.so.name-patched" ]; then \
	  [ -f "$(UNIX)/ntdll.so.bak" ] || cp "$(UNIX)/ntdll.so" "$(UNIX)/ntdll.so.bak"; \
	  cp "$(PAY)/winerosetta/ntdll.so" "$(UNIX)/ntdll.so"; fi
	@echo "==> Dock-name cosmetics (game shows as 'WoW')"
	@python3 scripts/patch-dock-name.py "$(UNIX)/ntdll.so"
	@cd "$(UNIX)" && if [ -f wine ] && [ ! -L wine ]; then mv wine "WoW 3.3.5"; ln -s "WoW 3.3.5" wine; fi; \
	cd "$(UNIX)" && [ -e "WoW 3.3.5" ] && ln -sf "WoW 3.3.5" "WoW " || true

patch-kit:
	@echo "==> patch kit (open-source payloads only)"
	@mkdir -p "$(RES)/patch-kit/mods"
	@cp "$(PAY)/d9vk/d3d9.dll" "$(PAY)/winerosetta/libDllLdr.dll" "$(RES)/patch-kit/"
	@cp "$(PAY)/winerosetta/winerosetta.dll" "$(PAY)/libSiliconPatch/wotlk/libSiliconPatch.dll" "$(RES)/patch-kit/mods/"
	@ditto "$(PAY)/rosettax87" "$(RES)/patch-kit/rosettax87"
	@chmod +x "$(RES)/patch-kit/rosettax87/"*
	@printf 'mods/winerosetta.dll\nmods/libSiliconPatch.dll\n' > "$(RES)/patch-kit/dlls.txt"
	@cp assets/wow-icon.bsdiff "$(RES)/patch-kit/"

prefix:
	@if [ -d "$(RES)/prefix/drive_c" ]; then echo "==> prefix already present, skipping"; \
	else echo "==> creating wine prefix (takes ~1 min)"; \
	  WINEPREFIX="$(RES)/prefix" WINEDEBUG=-all WINEDLLOVERRIDES="mshtml=;mscoree=" "$(HOSTED)/wineloader2" wineboot -u >/dev/null 2>&1; \
	  WINEPREFIX="$(RES)/prefix" "$(HOSTED)/wineserver" -w; fi
	@echo "==> fast-exit network fix"
	@WINEPREFIX="$(RES)/prefix" WINEDEBUG=-all "$(HOSTED)/wineloader2" reg add 'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings' /v ProxyEnable /t REG_DWORD /d 1 /f >/dev/null 2>&1
	@WINEPREFIX="$(RES)/prefix" WINEDEBUG=-all "$(HOSTED)/wineloader2" reg add 'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings' /v ProxyServer /t REG_SZ /d 127.0.0.1:1 /f >/dev/null 2>&1
	@WINEPREFIX="$(RES)/prefix" "$(HOSTED)/wineserver" -k >/dev/null 2>&1 || true

launcher:
	@echo "==> building the manager GUI"
	@./build.sh "$(APP)"

zip:
	@echo "==> zipping (for PRIVATE sharing — do not redistribute publicly, contains CrossOver binaries)"
	ditto -c -k --keepParent "$(APP)" WoW335.zip
	@du -h WoW335.zip
