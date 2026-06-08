PRODUCT := Splatoon3Screensaver
BUILD_DIR := build
DIST_DIR := dist
PACKAGE_NAME := splatoon3-boot.saver
BUNDLE := $(BUILD_DIR)/$(PRODUCT).saver
PACKAGE_BUNDLE := $(DIST_DIR)/$(PACKAGE_NAME)
CONTENTS := $(BUNDLE)/Contents
MACOS := $(CONTENTS)/MacOS
RESOURCES := $(CONTENTS)/Resources
SAVER_SWIFT_SOURCES := Sources/Renderer.swift Sources/Settings.swift Sources/ConfigSheetController.swift Sources/Splatoon3ScreensaverView.swift
METAL_SOURCE := Shaders/Splatoon3.metal
MIN_MACOS := 13.0

.PHONY: all clean install package FORCE

all: $(BUNDLE)

$(BUNDLE): FORCE
	@command -v xcrun >/dev/null || (echo "xcrun is required. Install Xcode." && exit 1)
	@xcrun --find metal >/dev/null || (echo "The Metal compiler is unavailable. Install full Xcode and run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" && exit 1)
	rm -rf "$(BUILD_DIR)/module-cache"
	@mkdir -p "$(MACOS)" "$(RESOURCES)" "$(BUILD_DIR)/module-cache"
	cp Resources/Info.plist "$(CONTENTS)/Info.plist"
	cp Resources/bubble-mask.raw "$(RESOURCES)/bubble-mask.raw"
	xcrun -sdk macosx metal -std=macos-metal2.4 -mmacosx-version-min=$(MIN_MACOS) \
		-fmodules-cache-path="$(BUILD_DIR)/module-cache" \
		"$(METAL_SOURCE)" -o "$(RESOURCES)/default.metallib"
	swiftc -target $(shell uname -m)-apple-macos$(MIN_MACOS) -parse-as-library -O \
		-module-cache-path "$(BUILD_DIR)/module-cache" \
		-emit-library -module-name $(PRODUCT) \
		-o "$(BUILD_DIR)/$(PRODUCT).dylib" \
		$(SAVER_SWIFT_SOURCES) \
		-framework AppKit -framework ScreenSaver -framework Metal -framework QuartzCore
	cp "$(BUILD_DIR)/$(PRODUCT).dylib" "$(MACOS)/$(PRODUCT)"

install: package
	@mkdir -p "$$HOME/Library/Screen Savers"
	rm -rf "$$HOME/Library/Screen Savers/$(PRODUCT).saver"
	rm -rf "$$HOME/Library/Screen Savers/$(PACKAGE_NAME)"
	ditto "$(PACKAGE_BUNDLE)" "$$HOME/Library/Screen Savers/$(PACKAGE_NAME)"
	xattr -cr "$$HOME/Library/Screen Savers/$(PACKAGE_NAME)"
	-pkill -x "System Settings"
	-pkill -x Wallpaper
	-pkill -x ScreenSaverEngine
	-pkill -x legacyScreenSaver
	rm -rf "$${TMPDIR%/T/}/C/com.apple.wallpaper.extension.legacy/com.apple.wallpaper.legacy.thumbnails"
	@echo "Installed $(PACKAGE_NAME) to $$HOME/Library/Screen Savers"
	@echo "Cleared Wallpaper screen saver thumbnail cache"
	@echo "Closed System Settings and restarted Wallpaper processes so the new build is loaded"

package: all
	@mkdir -p "$(DIST_DIR)"
	rm -rf "$(PACKAGE_BUNDLE)"
	ditto "$(BUNDLE)" "$(PACKAGE_BUNDLE)"
	@echo "Built $(PACKAGE_BUNDLE)"

clean:
	rm -rf "$(BUILD_DIR)" "$(DIST_DIR)"

FORCE:
