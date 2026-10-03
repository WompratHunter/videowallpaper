BINARY    := $(HOME)/.local/bin/videowallpaper
SRC       := VideoWallpaper.swift
PLIST_SRC := com.videowallpaper.plist.template
PLIST_DST := $(HOME)/Library/LaunchAgents/com.videowallpaper.plist
LABEL     := com.videowallpaper
VIDEO_DIR := $(HOME)/Movies/LiveWallpaper

.PHONY: install uninstall build

install: build
	@mkdir -p $(HOME)/.local/bin $(VIDEO_DIR) $(HOME)/Library/Logs
	@sed 's|__HOME__|$(HOME)|g' $(PLIST_SRC) > $(PLIST_DST)
	@launchctl unload $(PLIST_DST) 2>/dev/null || true
	@launchctl load $(PLIST_DST)
	@echo "✓ Installed. Drop .mp4 files into $(VIDEO_DIR)/"

build:
	@mkdir -p $(HOME)/.local/bin
	swiftc -O -framework AppKit -framework AVFoundation $(SRC) -o $(BINARY)
	@echo "✓ Built $(BINARY)"

uninstall:
	@launchctl unload $(PLIST_DST) 2>/dev/null || true
	@rm -f $(BINARY) $(PLIST_DST)
	@echo "✓ Uninstalled (video folder left intact)"
