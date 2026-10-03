APP       := $(HOME)/Applications/VideoWallpaper.app
BINARY    := $(APP)/Contents/MacOS/videowallpaper
BUILD_DIR := .build
APP_SRC   := $(wildcard Sources/App/*.swift)
CORE_SRC  := $(wildcard Sources/Core/*.swift)
TEST_SRC  := $(wildcard Tests/*.swift)
PLIST_SRC := com.videowallpaper.plist.template
PLIST_DST := $(HOME)/Library/LaunchAgents/com.videowallpaper.plist
LABEL     := com.videowallpaper
VIDEO_DIR := $(HOME)/Movies/LiveWallpaper

.PHONY: install uninstall build lint test

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

build: lint test
	@mkdir -p $(BUILD_DIR)
	swiftc -O -framework AppKit -framework AVFoundation $(CORE_SRC) $(APP_SRC) -o $(BUILD_DIR)/videowallpaper
	@echo "✓ Built $(BUILD_DIR)/videowallpaper"

uninstall:
	@launchctl unload $(PLIST_DST) 2>/dev/null || true
	@rm -rf $(APP) $(PLIST_DST)
	@echo "✓ Uninstalled (video folder left intact)"
