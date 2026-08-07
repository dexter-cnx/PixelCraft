SHELL := /usr/bin/env bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

FLUTTER ?= flutter
CARGO ?= cargo
FRB_CODEGEN ?= $(HOME)/.cargo/bin/flutter_rust_bridge_codegen
FRB_VERSION ?= 2.12.0
DEVICE ?=
APK ?= build/app/outputs/flutter-apk/app-debug.apk
RUST_CRATE_DIR ?= rust
RUST_BUILDER_DIR ?= rust_builder

DEVICE_FLAG := $(if $(strip $(DEVICE)),-d $(DEVICE),)

.PHONY: help doctor frb-info install-frb platforms pub-get ensure-rust-plugin integrate codegen codegen-watch \
        setup repair patch-cargokit app-icon run run-release clean clean-all analyze test test-unit test-widget \
        golden-test golden-update native-test profile-native test-full rust-fmt rust-clippy rust-test check \
        build-apk build-apk-release verify-native adb-abi

help: ## Show available commands
	@printf "Pixel Craft development commands\n\n"
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z0-9_.-]+:.*## / {printf "  %-20s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

doctor: ## Check Flutter, Rust and Android tooling
	@command -v $(FLUTTER) >/dev/null
	@command -v $(CARGO) >/dev/null
	@$(FLUTTER) --version
	@$(CARGO) --version
	@rustc --version
	@$(FLUTTER) doctor -v

frb-info: ## Show FRB executable and version
	@type -a flutter_rust_bridge_codegen 2>/dev/null || true
	@if [ -x "$(FRB_CODEGEN)" ]; then "$(FRB_CODEGEN)" --version; fi

install-frb: doctor ## Install pinned FRB codegen
	@current=""; if [ -x "$(FRB_CODEGEN)" ]; then current="$$($(FRB_CODEGEN) --version 2>/dev/null || true)"; fi; \
	case "$$current" in *"$(FRB_VERSION)"*) echo "[Pixel Craft] Using $$current" ;; \
	*) $(CARGO) install flutter_rust_bridge_codegen --version "$(FRB_VERSION)" --locked --force ;; esac
	@"$(FRB_CODEGEN)" --version

platforms: doctor ## Create missing Android and iOS projects
	$(FLUTTER) create --platforms=android,ios --org dev.pixelcraft .

pub-get: ## Resolve Flutter dependencies
	$(FLUTTER) pub get

ensure-rust-plugin: ## Verify local Rust plugin registration
	@test -f "$(RUST_BUILDER_DIR)/pubspec.yaml"
	@$(FLUTTER) pub deps --style=compact 2>/dev/null | grep -F 'pixelcraft_engine' >/dev/null

integrate: install-frb platforms ## Install CargoKit integration
	$(FRB_CODEGEN) integrate --template app --no-write-lib --no-integration-test \
		--rust-crate-name pixelcraft_engine --rust-crate-dir $(RUST_CRATE_DIR)
	@test -d $(RUST_BUILDER_DIR)/cargokit
	@$(MAKE) patch-cargokit
	@$(MAKE) pub-get
	@$(MAKE) ensure-rust-plugin

patch-cargokit: ## Patch CargoKit for Gradle 9 and Android SDK 36
	@python3 tool/patch_cargokit_gradle9.py

codegen: install-frb ## Regenerate Dart/Rust bridge
	$(FRB_CODEGEN) generate --config-file flutter_rust_bridge.yaml

codegen-watch: install-frb ## Watch and regenerate bridge
	$(FRB_CODEGEN) generate --config-file flutter_rust_bridge.yaml --watch

app-icon: pub-get ## Generate Pixel Craft launcher icons for Android and iOS
	$(FLUTTER) test tool/generate_app_icon_test.dart
	$(FLUTTER) pub run flutter_launcher_icons

setup: integrate codegen clean-all pub-get ensure-rust-plugin app-icon ## First-time setup

repair: doctor install-frb platforms integrate codegen clean-all pub-get ensure-rust-plugin app-icon ## Repair integration

run: ensure-rust-plugin ## Run debug app; DEVICE=<id>
	$(FLUTTER) run $(DEVICE_FLAG)

run-release: ensure-rust-plugin ## Run release app; DEVICE=<id>
	$(FLUTTER) run --release $(DEVICE_FLAG)

clean: ## Flutter clean
	$(FLUTTER) clean

clean-all: clean ## Remove Flutter, Gradle and Rust outputs
	rm -rf build android/.gradle $(RUST_CRATE_DIR)/target

analyze: ## Run Flutter analyzer
	$(FLUTTER) analyze

test: test-unit test-widget ## Run Dart unit and widget tests, excluding goldens

test-unit: ## Run controller/state tests
	$(FLUTTER) test test/state

test-widget: ## Run widget tests
	$(FLUTTER) test test/ui --exclude-tags=golden

golden-test: ## Compare UI with committed golden PNG files
	$(FLUTTER) test test/golden

golden-update: ## Create or update golden PNG files
	$(FLUTTER) test --update-goldens test/golden

native-test: ensure-rust-plugin ## Run real Rust bridge smoke test on DEVICE
	@test -n "$(DEVICE)" || { echo "ERROR: use DEVICE=<device-id>" >&2; exit 1; }
	$(FLUTTER) test integration_test/native_engine_smoke_test.dart -d $(DEVICE)

profile-native: ensure-rust-plugin ## Print device timing and RSS metrics; DEVICE=<id>
	@test -n "$(DEVICE)" || { echo "ERROR: use DEVICE=<device-id>" >&2; exit 1; }
	$(FLUTTER) test integration_test/performance_profile_test.dart -d $(DEVICE)

rust-fmt: ## Check Rust formatting
	$(CARGO) fmt --manifest-path $(RUST_CRATE_DIR)/Cargo.toml --all -- --check

rust-clippy: ## Run strict Rust lints
	$(CARGO) clippy --manifest-path $(RUST_CRATE_DIR)/Cargo.toml --all-targets -- -D warnings

rust-test: ## Run Rust unit tests
	$(CARGO) test --manifest-path $(RUST_CRATE_DIR)/Cargo.toml

test-full: analyze rust-fmt rust-clippy rust-test test golden-test ## Run complete host-side suite

check: test-full ## Alias for the complete host-side suite

build-apk: ensure-rust-plugin ## Build debug APK
	$(FLUTTER) build apk --debug

build-apk-release: ensure-rust-plugin ## Build release APK
	$(FLUTTER) build apk --release

verify-native: build-apk ## Verify Rust .so files in APK
	@expected="libpixelcraft_engine.so"; matches="$$(unzip -Z1 "$(APK)" | grep -E "^lib/[^/]+/$${expected}$$" || true)"; \
	if [ -z "$$matches" ]; then echo "ERROR: $$expected is missing" >&2; exit 1; fi; \
	printf '%s\n' "$$matches"

adb-abi: ## Show connected Android ABI
	@adb shell getprop ro.product.cpu.abi
