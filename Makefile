PRODUCT := Splatoon3Screensaver
PREVIEW_PRODUCT := Splatoon3Preview
BUILD_DIR := build
BUNDLE := $(BUILD_DIR)/$(PRODUCT).saver
PREVIEW_APP := $(BUILD_DIR)/$(PREVIEW_PRODUCT).app
CONTENTS := $(BUNDLE)/Contents
MACOS := $(CONTENTS)/MacOS
RESOURCES := $(CONTENTS)/Resources
SHARED_SWIFT_SOURCES := Sources/Renderer.swift Sources/Settings.swift
SAVER_SWIFT_SOURCES := $(SHARED_SWIFT_SOURCES) Sources/ConfigSheetController.swift Sources/Splatoon3ScreensaverView.swift
PREVIEW_SWIFT_SOURCES := $(SHARED_SWIFT_SOURCES) PreviewApp/main.swift
METAL_SOURCE := Shaders/Splatoon3.metal
MIN_MACOS := 13.0

.PHONY: all clean install preview run-preview

all: $(BUNDLE)

$(BUNDLE): $(SAVER_SWIFT_SOURCES) $(METAL_SOURCE) Resources/Info.plist Resources/bubble-mask.raw
	@command -v xcrun >/dev/null || (echo "xcrun is required. Install Xcode." && exit 1)
	@xcrun --find metal >/dev/null || (echo "The Metal compiler is unavailable. Install full Xcode and run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" && exit 1)
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
		-framework AppKit -framework ScreenSaver -framework Metal -framework MetalKit -framework QuartzCore
	cp "$(BUILD_DIR)/$(PRODUCT).dylib" "$(MACOS)/$(PRODUCT)"

preview: $(PREVIEW_APP)

$(PREVIEW_APP): $(PREVIEW_SWIFT_SOURCES) $(METAL_SOURCE) PreviewApp/Info.plist Resources/bubble-mask.raw
	@command -v xcrun >/dev/null || (echo "xcrun is required. Install Xcode." && exit 1)
	@xcrun --find metal >/dev/null || (echo "The Metal compiler is unavailable. Install full Xcode and run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" && exit 1)
	@mkdir -p "$(PREVIEW_APP)/Contents/MacOS" "$(PREVIEW_APP)/Contents/Resources" "$(BUILD_DIR)/module-cache"
	cp PreviewApp/Info.plist "$(PREVIEW_APP)/Contents/Info.plist"
	cp Resources/bubble-mask.raw "$(PREVIEW_APP)/Contents/Resources/bubble-mask.raw"
	xcrun -sdk macosx metal -std=macos-metal2.4 -mmacosx-version-min=$(MIN_MACOS) \
		-fmodules-cache-path="$(BUILD_DIR)/module-cache" \
		"$(METAL_SOURCE)" -o "$(PREVIEW_APP)/Contents/Resources/default.metallib"
	swiftc -target $(shell uname -m)-apple-macos$(MIN_MACOS) -O \
		-module-cache-path "$(BUILD_DIR)/module-cache" \
		-o "$(PREVIEW_APP)/Contents/MacOS/$(PREVIEW_PRODUCT)" \
		$(PREVIEW_SWIFT_SOURCES) \
		-framework AppKit -framework Metal -framework MetalKit -framework QuartzCore

run-preview: preview
	"$(PREVIEW_APP)/Contents/MacOS/$(PREVIEW_PRODUCT)"

install: all
	@mkdir -p "$$HOME/Library/Screen Savers"
	rm -rf "$$HOME/Library/Screen Savers/$(PRODUCT).saver"
	ditto "$(BUNDLE)" "$$HOME/Library/Screen Savers/$(PRODUCT).saver"
	xattr -cr "$$HOME/Library/Screen Savers/$(PRODUCT).saver"
	@echo "Installed $(PRODUCT).saver to $$HOME/Library/Screen Savers"

clean:
	rm -rf "$(BUILD_DIR)"
