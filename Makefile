# Askance — the commands you actually need.
#
# Dart has no equivalent of npm scripts in pubspec.yaml; the `flutter` CLI is
# the task runner. This file is only here so the flags we care about are
# remembered for you. Every target is a one-line command you can run directly.

DEVICE ?=
APK    := build/app/outputs/flutter-apk/app-release.apk

.DEFAULT_GOAL := help

## help: list the targets
help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/## /  /'

## devices: what is plugged in or reachable
devices:
	flutter devices

# --- day to day ------------------------------------------------------------
# This is the loop you want almost always: it installs a debug build and stays
# attached. Press r to hot reload, R to hot restart, q to quit. Edits to Dart
# land in under a second, so there is no reason to rebuild by hand.
#
#   make run DEVICE=58181JEBF00222
#
# Impeller is used in debug too, so anything about how the engine *renders*
# reproduces here. Only speed differs from release.

## run: hot-reload session on DEVICE (see `make devices`)
run:
	flutter run $(if $(DEVICE),-d $(DEVICE),)

## phone: hot-reload session on the first attached Android device
phone:
	flutter run -d $$(adb devices | awk 'NR==2{print $$1}')

## mac: hot-reload session on macOS
mac:
	flutter run -d macos

## web: hot-reload session in Chrome
web:
	flutter run -d chrome

# --- release builds --------------------------------------------------------
# Worth doing before you trust performance numbers, or when checking anything
# that AOT and release-mode Impeller might change.

## apk: release APK for this machine's attached arm64 phone
apk:
	flutter build apk --release --target-platform android-arm64

## apk-all: release APK for every Android ABI (what you would upload)
apk-all:
	flutter build apk --release

## bundle: Play Store app bundle
bundle:
	flutter build appbundle --release

## install: push the last release APK onto the attached phone
install:
	adb install -r $(APK)

## ship-phone: build release and install it, in one step
ship-phone: apk install

## ios-sim: build for the iOS simulator (no signing needed)
ios-sim:
	flutter build ios --simulator --debug

## ios: build for a real iPhone (needs your signing set up in Xcode)
ios:
	flutter build ios --release

## macos-app: release macOS build
macos-app:
	flutter build macos --release

## web-build: release web build into build/web
web-build:
	flutter build web --release

## serve: build for web and serve it on :8000
serve: web-build
	cd build/web && python3 -m http.server 8000

# --- housekeeping ----------------------------------------------------------

## test: run the test suite
test:
	flutter test

## analyze: static analysis
analyze:
	flutter analyze

## format: format lib/ test/ tool/
format:
	dart format lib test tool

## check: what to run before committing
check: format analyze test

## icons: regenerate every launcher icon from design/logo
icons:
	flutter test tool/generate_icons.dart

## outdated: dependencies with newer versions
outdated:
	flutter pub outdated

## clean: throw away build output
clean:
	flutter clean

.PHONY: help devices run phone mac web apk apk-all bundle install ship-phone \
        ios-sim ios macos-app web-build serve test analyze format check icons \
        outdated clean
