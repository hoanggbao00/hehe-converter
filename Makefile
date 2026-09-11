PROJECT := HeheConverter.xcodeproj
SCHEME := HeheConverter
DESTINATION := platform=macOS,arch=arm64
RELEASE_DESTINATION := generic/platform=macOS
BUILD_ROOT := $(CURDIR)/build
APP := $(BUILD_ROOT)/Debug/HeheConverter.app
RELEASE_APP := $(BUILD_ROOT)/Release/HeheConverter.app
DMG := $(BUILD_ROOT)/Release/HeheConverter.dmg
DMG_STAGE := $(BUILD_ROOT)/dmg
DMG_RW := $(BUILD_ROOT)/HeheConverter-rw.dmg
DMG_MOUNT := /Volumes/HeheConverter

.PHONY: generate build release dmg test run reset-onboarding clean open

generate:
	xcodegen generate

build: generate
	xcodebuild build \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination '$(DESTINATION)' \
		SYMROOT=$(BUILD_ROOT) \
		CODE_SIGNING_ALLOWED=NO

release: generate
	xcodebuild build \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration Release \
		-destination '$(RELEASE_DESTINATION)' \
		SYMROOT=$(BUILD_ROOT) \
		ARCHS="arm64 x86_64" \
		ONLY_ACTIVE_ARCH=NO \
		CODE_SIGNING_ALLOWED=NO \
		STRIP_INSTALLED_PRODUCT=YES \
		COPY_PHASE_STRIP=YES \
		DEPLOYMENT_POSTPROCESSING=YES

dmg: release
	@test ! -e "$(DMG_MOUNT)" || (echo 'Eject existing HeheConverter volume first' >&2; exit 1)
	rm -rf "$(DMG_STAGE)" "$(DMG_RW)" "$(DMG)"
	mkdir -p "$(DMG_STAGE)"
	ditto "$(RELEASE_APP)" "$(DMG_STAGE)/HeheConverter.app"
	ln -s /Applications "$(DMG_STAGE)/Applications"
	hdiutil create -volname "HeheConverter" -srcfolder "$(DMG_STAGE)" -ov -format UDRW "$(DMG_RW)"
	hdiutil attach "$(DMG_RW)" -readwrite -noverify -noautoopen -mountpoint "$(DMG_MOUNT)"
	mkdir -p "$(DMG_MOUNT)/.fseventsd"
	touch "$(DMG_MOUNT)/.fseventsd/no_log"
	@osascript -e 'tell application "Finder"' \
		-e 'tell disk "HeheConverter"' \
		-e 'open' \
		-e 'set current view of container window to icon view' \
		-e 'set toolbar visible of container window to false' \
		-e 'set statusbar visible of container window to false' \
		-e 'set icon size of icon view options of container window to 72' \
		-e 'set arrangement of icon view options of container window to not arranged' \
		-e 'set position of item "Applications" of container window to {110, 110}' \
		-e 'set position of item "HeheConverter.app" of container window to {300, 110}' \
		-e 'set bounds of container window to {100, 100, 520, 330}' \
		-e 'update without registering applications' \
		-e 'delay 2' \
		-e 'close container window' \
		-e 'delay 1' \
		-e 'open' \
		-e 'set bounds of container window to {100, 100, 520, 330}' \
		-e 'update without registering applications' \
		-e 'delay 2' \
		-e 'close container window' \
		-e 'end tell' \
		-e 'end tell'
	@i=0; while [ ! -f "$(DMG_MOUNT)/.DS_Store" ] && [ $$i -lt 10 ]; do sleep 1; i=$$((i + 1)); done
	@test -s "$(DMG_MOUNT)/.DS_Store" || (hdiutil detach "$(DMG_MOUNT)"; echo 'Finder did not save DMG layout' >&2; exit 1)
	sync
	rm -rf "$(DMG_MOUNT)/.fseventsd"
	sync
	hdiutil detach "$(DMG_MOUNT)"
	hdiutil convert "$(DMG_RW)" -format UDZO -o "$(DMG)"
	rm -rf "$(DMG_STAGE)" "$(DMG_RW)"

test: generate
	xcodebuild test \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination '$(DESTINATION)' \
		SYMROOT=$(BUILD_ROOT) \
		CODE_SIGNING_ALLOWED=NO

run: build
	open $(APP)

reset-onboarding:
	defaults delete com.hoanggbao.HeheConverter didPresentFFmpegOnboarding 2>/dev/null || true

clean:
	rm -rf build DerivedData
	xcodebuild clean -project $(PROJECT) -scheme $(SCHEME)

open: generate
	open $(PROJECT)
