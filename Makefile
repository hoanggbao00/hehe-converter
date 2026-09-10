PROJECT := MediaDrop.xcodeproj
SCHEME := MediaDrop
DESTINATION := platform=macOS,arch=arm64
BUILD_ROOT := $(CURDIR)/build
APP := $(BUILD_ROOT)/Debug/MediaDrop.app
RELEASE_APP := $(BUILD_ROOT)/Release/MediaDrop.app

.PHONY: generate build release test run reset-onboarding clean open

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
		-destination '$(DESTINATION)' \
		SYMROOT=$(BUILD_ROOT) \
		CODE_SIGNING_ALLOWED=NO \
		STRIP_INSTALLED_PRODUCT=YES \
		COPY_PHASE_STRIP=YES \
		DEPLOYMENT_POSTPROCESSING=YES

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
	defaults delete com.hoanggbao.MediaDrop didPresentFFmpegOnboarding 2>/dev/null || true

clean:
	rm -rf build DerivedData
	xcodebuild clean -project $(PROJECT) -scheme $(SCHEME)

open: generate
	open $(PROJECT)
