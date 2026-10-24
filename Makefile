PRODUCT := Splatoon3Screensaver
BUILD_DIR := build
DIST_DIR := dist
PACKAGE_NAME := splatoon3-boot.saver
BUNDLE := $(BUILD_DIR)/$(PRODUCT).saver
PACKAGE_BUNDLE := $(DIST_DIR)/$(PACKAGE_NAME)
CONTENTS := $(BUNDLE)/Contents
MACOS := $(CONTENTS)/MacOS
RESOURCES := $(CONTENTS)/Resources
SAVER_SWIFT_SOURCES := Sources/Renderer.swift Sources/Settings.swift Sources/PowerMonitor.swift Sources/ConfigSheetController.swift Sources/Splatoon3ScreensaverView.swift
METAL_SOURCE := Shaders/Splatoon3.metal
MIN_MACOS := 13.0
# Releases build ARCHS="arm64 x86_64" for a universal binary.
ARCHS ?= $(shell uname -m)
# Releases stamp the bundle version, e.g. VERSION=1.0.6 BUILD_NUMBER=42.
VERSION ?=
BUILD_NUMBER ?=

.PHONY: all clean install package FORCE

all: $(BUNDLE)

$(BUNDLE): FORCE
	@command -v xcrun >/dev/null || (echo "xcrun is required. Install Xcode." && exit 1)
	@xcrun --find metal >/dev/null || (echo "The Metal compiler is unavailable. Install full Xcode and run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" && exit 1)
	rm -rf "$(BUILD_DIR)/module-cache"
	@mkdir -p "$(MACOS)" "$(RESOURCES)" "$(BUILD_DIR)/module-cache"
	cp Resources/Info.plist "$(CONTENTS)/Info.plist"
	$(if $(VERSION),plutil -replace CFBundleShortVersionString -string "$(VERSION)" "$(CONTENTS)/Info.plist")
	$(if $(BUILD_NUMBER),plutil -replace CFBundleVersion -string "$(BUILD_NUMBER)" "$(CONTENTS)/Info.plist")
	cp Resources/bubble-mask.raw "$(RESOURCES)/bubble-mask.raw"
	cp Resources/Shadertoy/seed_*.raw "$(RESOURCES)/"
	xcrun -sdk macosx metal -std=macos-metal2.4 -mmacosx-version-min=$(MIN_MACOS) \
		-fmodules-cache-path="$(BUILD_DIR)/module-cache" \
		"$(METAL_SOURCE)" -o "$(RESOURCES)/default.metallib"
	set -e; for arch in $(ARCHS); do \
		swiftc -target $$arch-apple-macos$(MIN_MACOS) -parse-as-library -O -wmo \
			-module-cache-path "$(BUILD_DIR)/module-cache" \
			-emit-library -module-name $(PRODUCT) \
			-o "$(BUILD_DIR)/$(PRODUCT)-$$arch.dylib" \
			$(SAVER_SWIFT_SOURCES) \
			-framework AppKit -framework ScreenSaver -framework Metal -framework QuartzCore -framework IOKit; \
	done
ifeq ($(words $(ARCHS)),1)
	cp "$(BUILD_DIR)/$(PRODUCT)-$(ARCHS).dylib" "$(MACOS)/$(PRODUCT)"
else
	lipo -create $(foreach arch,$(ARCHS),"$(BUILD_DIR)/$(PRODUCT)-$(arch).dylib") -output "$(MACOS)/$(PRODUCT)"
endif

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
