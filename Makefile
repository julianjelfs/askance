# Askance — the commands you actually need.
#
# Dart has no equivalent of npm scripts in pubspec.yaml; the `flutter` CLI is
# the task runner. This file is only here so the flags worth remembering are
# remembered for you. Every target is a one-line command you can run directly.
#
# Picking a device
# ----------------
# `flutter run` with nothing specified and several devices attached prints a
# numbered list and asks. Fine interactively, useless in a script.
#
# `-d` matches a device's **id or name**, case-insensitively: exact match
# first, then by prefix. There is no substring match, and no `-d android` or
# `-d ios` — `macos` and `chrome` only work because those are literally the
# device ids. So `-d pixel` finds "Pixel 9a", but `-d iphone` finds nothing
# when the phone is called "Julian Jelfs's iPhone".
#
# One session drives one device: `-d` is single-valued, so a second `-d`
# overrides the first rather than adding to it. `-d all` is the only way to
# drive several at once, and it takes every connected device except web and
# Fuchsia — with a Mac attached, macOS comes along too. To drive exactly two
# phones, run `make android` and `make iphone` in two terminals; each gets its
# own hot reload.
#
# ANDROID and IPHONE below are resolved from whatever is attached, by a script
# that refuses to guess when two devices of the same kind are present rather
# than quietly deploying to whichever it saw first. Override per-invocation
# (`make iphone IPHONE=00008110-...`) or export them in your shell.

ANDROID ?=
IPHONE  ?=
DEVICE  ?=

PICK := ./tool/pick-device.sh
APK  := build/app/outputs/flutter-apk/app-release.apk

.DEFAULT_GOAL := help

## help: list the targets
help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/## /  /'

## devices: what is plugged in or reachable, with the ids -d wants
devices:
	flutter devices

# --- day to day ------------------------------------------------------------
# This is the loop you want almost always: it installs a debug build and stays
# attached. Press r to hot reload, R to hot restart, q to quit. Edits to Dart
# land in under a second, so there is rarely a reason to rebuild by hand.
#
# Impeller is used in debug too, so anything about how the engine *renders*
# reproduces here. Only speed differs from release.

## run: hot-reload session on DEVICE=<id or name prefix>
run:
	flutter run $(if $(DEVICE),-d $(DEVICE),)

## android: hot-reload session on the attached Android
android:
	@id=$${ANDROID:-$$($(PICK) android)} && flutter run -d "$$id"

## iphone: hot-reload session on the attached iPhone (needs signing in Xcode)
iphone:
	@id=$${IPHONE:-$$($(PICK) ios)} && flutter run -d "$$id"

## mac: hot-reload session on macOS
mac:
	flutter run -d macos

## web: hot-reload session in Chrome
web:
	flutter run -d chrome

## all: one session driving every attached device (phones *and* macOS)
all:
	flutter run -d all

# --- release builds --------------------------------------------------------
# Worth doing before you trust performance numbers, or when checking anything
# that AOT and release-mode Impeller might change.

## apk: release APK for an arm64 phone (fast; not for distribution)
apk:
	flutter build apk --release --target-platform android-arm64

## apk-all: release APK covering every Android ABI
apk-all:
	flutter build apk --release

## bundle: Play Store app bundle
bundle:
	flutter build appbundle --release

## install: push the last release APK onto the Android device
install:
	@id=$${ANDROID:-$$($(PICK) android)} && adb -s "$$id" install -r $(APK)

## ship-android: build a release APK and install it, in one step
ship-android: apk install

## ship-iphone: run a release build on the iPhone
ship-iphone:
	@id=$${IPHONE:-$$($(PICK) ios)} && flutter run --release -d "$$id"

## build-ios-sim: build for the iOS simulator (no signing needed)
build-ios-sim:
	flutter build ios --simulator --debug

## build-ios: build for a real iPhone (needs signing set up in Xcode)
build-ios:
	flutter build ios --release

## build-macos: release macOS build
build-macos:
	flutter build macos --release

## build-web: release web build into build/web
build-web:
	flutter build web --release

## serve: build for web and serve it on :8000
serve: build-web
	cd build/web && python3 -m http.server 8000

# GitHub Pages cannot serve a private repository on a free plan, so the site
# lives in a public repository holding only the compiled output; the source
# stays here. This rebuilds and force-pushes — the output repo has no history
# worth keeping.

## deploy-web: build for web and publish to julianjelfs.github.io/askance-web
# --wasm compiles the Dart to WebAssembly, which runs the CPU side of the
# engine markedly faster than the JavaScript fallback; browsers without
# WasmGC get that fallback automatically from the same build.
deploy-web:
	flutter build web --wasm --release --base-href /askance-web/
	cd build/web && touch .nojekyll && git init -q -b main && \
	git add -A && (git commit -q -m "Deploy web build" || true) && \
	git push -q --force git@github.com:julianjelfs/askance-web.git main
	@echo "https://julianjelfs.github.io/askance-web/"

# --- housekeeping ----------------------------------------------------------

## logs: follow the Android device log, this app only
logs:
	@id=$${ANDROID:-$$($(PICK) android)} && \
	adb -s "$$id" logcat --pid=$$(adb -s "$$id" shell pidof -s com.julianjelfs.askance)

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

.PHONY: help devices run android iphone mac web all apk apk-all bundle \
        install ship-android ship-iphone build-ios-sim build-ios build-macos \
        build-web serve logs test analyze format check icons outdated clean
