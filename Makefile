APP       := $(HOME)/Applications/VideoWallpaper.app
BINARY    := $(APP)/Contents/MacOS/videowallpaper
BUILD_DIR := .build
APP_SRC   := $(wildcard Sources/App/*.swift)
CORE_SRC  := $(wildcard Sources/Core/*.swift)
TEST_SRC  := $(wildcard Tests/*.swift)
SMOKE_SRC := Sources/App/LibraryAnalyser.swift $(wildcard Tests/Smoke/*.swift)
PLIST_SRC := com.videowallpaper.plist.template
PLIST_DST := $(HOME)/Library/LaunchAgents/com.videowallpaper.plist
LABEL     := com.videowallpaper
VIDEO_DIR := $(HOME)/Movies/LiveWallpaper
SUPPORT   := $(HOME)/Library/Application Support/VideoWallpaper
BUNDLE_ID := com.evanscott.videowallpaper

.PHONY: install uninstall build lint test smoke

# `install` writes a new inode, so the running binary is never overwritten in place.
install: build
	@mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources $(VIDEO_DIR) $(HOME)/Library/Logs
	@cp Info.plist $(APP)/Contents/Info.plist
	@install -m 755 $(BUILD_DIR)/videowallpaper $(BINARY)
	@sed 's|__HOME__|$(HOME)|g' $(PLIST_SRC) > $(PLIST_DST)
	@launchctl unload $(PLIST_DST) 2>/dev/null || true
	@launchctl load $(PLIST_DST)
	@echo "✓ Installed. Drop .mp4 files into $(VIDEO_DIR)/"

lint:
	swiftlint lint --strict --quiet

test:
	@mkdir -p $(BUILD_DIR)
	swiftc $(CORE_SRC) $(TEST_SRC) -o $(BUILD_DIR)/tests
	$(BUILD_DIR)/tests

# The real analyser on generated clips with a known flash rate. Pass video paths to measure them instead:
# `.build/smoke ~/Movies/LiveWallpaper/*.mp4` (read only).
smoke:
	@mkdir -p $(BUILD_DIR)
	swiftc -parse-as-library -framework AVFoundation $(CORE_SRC) $(SMOKE_SRC) -o $(BUILD_DIR)/smoke
	$(BUILD_DIR)/smoke

build: lint test smoke
	@mkdir -p $(BUILD_DIR)
	swiftc -O -framework AppKit -framework AVFoundation $(CORE_SRC) $(APP_SRC) -o $(BUILD_DIR)/videowallpaper
	@echo "✓ Built $(BUILD_DIR)/videowallpaper"

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
