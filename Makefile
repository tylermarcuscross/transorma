.DEFAULT_GOAL := help
SHELL := /bin/zsh

PROJECT := Transorma.xcodeproj
SCHEME := Transorma
DESTINATION ?= platform=macOS,arch=$(shell uname -m)
TOOLCHAIN := /bin/zsh Scripts/toolchain.sh
XCODEBUILD := $(TOOLCHAIN) xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
	-destination '$(DESTINATION)' -derivedDataPath .build/Xcode
DEVELOPMENT_BUILD := $(XCODEBUILD) -configuration Development
SWIFT_FILES := Package.swift App TransormaMailExtension Sources Tests

.PHONY: help build build-signed run xcode clean test test-core test-unit test-ui build-diagnostics lint format verify index reindex archive-unsigned doctor

help:
	@printf '%s\n' \
		'make build             Build the development app, extension, and test bundles' \
		'make build-signed      Build the Mail-enabled Debug app using your Xcode account' \
		'make run               Open the UI preview (no email processing)' \
		'make xcode             Open the native project in Xcode' \
		'make clean             Remove generated builds, archives, and editor indexes' \
		'make test              Run all Xcode tests, including UI automation' \
		'make test-core         Run the independent Swift package tests' \
		'make test-unit         Run core and app model tests through Xcode' \
		'make test-ui           Run only UI automation' \
		'make lint / format     Check style or format all Swift sources' \
		'make verify            Check style, unit tests, and whitespace' \
		'make index / reindex   Refresh editor settings / clean build and refresh' \
		'make archive-unsigned  Validate a Release archive without signing' \
		'make doctor            Show the selected toolchain and editor adapter'

build:
	$(DEVELOPMENT_BUILD) build-for-testing
	/bin/zsh Scripts/editor.sh index --if-installed

build-signed:
	$(XCODEBUILD) -configuration Debug -allowProvisioningUpdates -allowProvisioningDeviceRegistration build

run: build
	@printf '%s\n' 'Opening the development preview. This build does not unsubscribe or move email.'
	open -n .build/Xcode/Build/Products/Development/Transorma.app

xcode:
	open $(PROJECT)

clean:
	rm -rf -- .build .compile .compile.lock

test:
	$(DEVELOPMENT_BUILD) test
	/bin/zsh Scripts/editor.sh index --if-installed

test-core:
	$(TOOLCHAIN) xcrun swift test

test-unit:
	$(DEVELOPMENT_BUILD) test -skip-testing:AppUITests
	/bin/zsh Scripts/editor.sh index --if-installed

test-ui:
	$(DEVELOPMENT_BUILD) test -only-testing:AppUITests
	/bin/zsh Scripts/editor.sh index --if-installed

build-diagnostics:
	$(TOOLCHAIN) xcrun swift build --product transorma-diagnostics

lint:
	$(TOOLCHAIN) xcrun swift-format lint --strict --configuration .swift-format --recursive $(SWIFT_FILES)

format:
	$(TOOLCHAIN) xcrun swift-format format --in-place --configuration .swift-format --recursive $(SWIFT_FILES)

# Keep these checks sequential even when make is invoked with -j.
verify:
	$(MAKE) lint
	$(MAKE) test-unit
	git diff --check

index:
	/bin/zsh Scripts/editor.sh index

reindex:
	$(DEVELOPMENT_BUILD) clean build-for-testing
	/bin/zsh Scripts/editor.sh index

archive-unsigned:
	$(XCODEBUILD) -configuration Release -archivePath .build/Archives/Transorma.xcarchive \
		archive CODE_SIGNING_ALLOWED=NO

doctor:
	$(TOOLCHAIN) xcodebuild -version
	$(TOOLCHAIN) xcrun swift --version
	$(TOOLCHAIN) xcrun --sdk macosx --show-sdk-version
	/bin/zsh Scripts/editor.sh doctor
