APP       := $(HOME)/Applications/VideoWallpaper.app
BINARY    := $(APP)/Contents/MacOS/videowallpaper
# SwiftPM's output folders (Package.swift); recursive (=), so SwiftPM is only asked by the targets that use them.
RELEASE_DIR = $(shell swift build -c release --show-bin-path)
DEBUG_DIR   = $(shell swift build -c debug --show-bin-path)
PLIST_SRC := com.videowallpaper.plist.template
PLIST_DST := $(HOME)/Library/LaunchAgents/com.videowallpaper.plist
LABEL     := com.videowallpaper
VIDEO_DIR := $(HOME)/Movies/LiveWallpaper
SUPPORT   := $(HOME)/Library/Application Support/VideoWallpaper
BUNDLE_ID := com.evanscott.videowallpaper
# A stable signature keeps the Location Services grant across reinstalls; ad-hoc ("-") would change every build.
# Recursive (=), so only `install` looks the identity up.
SIGN_ID    = $(or $(shell security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development/ {print $$2; exit}'),-)

.PHONY: install uninstall build lint test smoke debug

# `install` writes a new inode, so the running binary is never overwritten in place.
install: build
	@mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources" "$(VIDEO_DIR)" "$(HOME)/Library/Logs"
	@cp Info.plist "$(APP)/Contents/Info.plist"
	@install -m 755 "$(RELEASE_DIR)/videowallpaper" "$(BINARY)"
	@# The first signing asks for keychain access: choose Always Allow. If the key is refused, sign ad-hoc so the
	@# install still completes (Location Services may then ask again after a later reinstall).
	@codesign --force --sign "$(SIGN_ID)" --identifier $(BUNDLE_ID) "$(APP)" \
		|| { echo "! Could not sign with $(SIGN_ID); signing ad-hoc"; \
		     codesign --force --sign - --identifier $(BUNDLE_ID) "$(APP)"; }
	@sed 's|__HOME__|$(HOME)|g' "$(PLIST_SRC)" > "$(PLIST_DST)"
	@launchctl unload "$(PLIST_DST)" 2>/dev/null || true
	@launchctl load "$(PLIST_DST)"
	@echo "✓ Installed. Drop .mp4 files into $(VIDEO_DIR)/"

lint:
	swiftlint lint --strict --quiet

# Every suite under swift-testing; any failed check fails the run.
test:
	swift test

# The real analyser on generated clips with a known flash rate. Pass video paths to measure them instead:
# `.build/debug/smoke ~/Movies/LiveWallpaper/*.mp4` (read only).
smoke:
	swift build --product smoke
	"$(DEBUG_DIR)/smoke"

build: lint test smoke
	swift build -c release --product videowallpaper
	@echo "✓ Built $(RELEASE_DIR)/videowallpaper"

# A separate binary for manual tests, never installed: SwiftPM's debug configuration defines DEBUG, so only it honours
# VIDEOWALLPAPER_FOLDER and VIDEOWALLPAPER_DWELL_SCALE (see the Rotation ticket's Comments).
debug:
	swift build -c debug --product videowallpaper
	@echo "✓ Built $(DEBUG_DIR)/videowallpaper"

# The agent is unloaded first so the app can't set its Poster again; then the original desktop pictures are
# restored while the Posters they replace still exist. A failed restore is reported but doesn't block removal.
# Paths are quoted so a home folder with a space can't split into other paths for `rm -rf`.
uninstall:
	@case "$(HOME)" in /?*) ;; *) echo "! HOME is not an absolute path; refusing to uninstall"; exit 1;; esac
	@launchctl unload "$(PLIST_DST)" 2>/dev/null || true
	@if [ -x "$(BINARY)" ]; then \
		"$(BINARY)" --restore-wallpaper || echo "! Could not restore every desktop picture; set it in System Settings"; \
	else \
		echo "! App not found, desktop picture not restored; set it in System Settings"; \
	fi
	@rm -rf "$(APP)" "$(PLIST_DST)" "$(SUPPORT)"
	@rm -f "$(VIDEO_DIR)/.poster.jpg"
	@defaults delete $(BUNDLE_ID) 2>/dev/null || true
	@echo "✓ Uninstalled: app, LaunchAgent, Application Support and preferences removed"
	@echo "  (videos in $(VIDEO_DIR)/ and the log in ~/Library/Logs/ left intact)"
	@echo "  macOS keeps VideoWallpaper's Location Services entry, and there is no command to remove it: switch it"
	@echo "  off in System Settings › Privacy & Security › Location Services if it is listed"
