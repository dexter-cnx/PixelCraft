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
RUST_BUILDER_DIR ?= packages/dxtr_pixs_engine
GPU_CRATE_DIR ?= packages/dxtr_pixs_gpu/rust
GPU_LUT_DIR ?= build/gpu_luts

DEVICE_FLAG := $(if $(strip $(DEVICE)),-d $(DEVICE),)

.PHONY: help doctor frb-info install-frb platforms pub-get ensure-rust-plugin integrate codegen codegen-watch \
        setup repair patch-cargokit app-icon film-luts creative-luts gpu-luts gpu-lut-verify gpu-native-test g3-device-verify run run-release clean clean-all \
        format-check analyze test test-unit test-gpu test-widget test-fast package-check gpu-check device-safety-check package-boundaries ci-fast preflight \
        golden-test golden-update native-test profile-native test-full rust-fmt rust-clippy rust-test check build-apk build-apk-release verify-native adb-abi

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
	@$(FLUTTER) pub deps --style=compact 2>/dev/null | grep -F 'dxtr_pixs_engine' >/dev/null

integrate: install-frb platforms ## Install CargoKit integration
	$(FRB_CODEGEN) integrate --template app --no-write-lib --no-integration-test \
		--rust-crate-name pixelcraft_engine --rust-crate-dir $(RUST_CRATE_DIR)
	@python3 tool/normalize_rust_builder_layout.py
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

film-luts: ## Materialize Film Profile Pack v2 as inspectable 33^3 .cube files
	PIXELCRAFT_EXPORT_LUT_DIR="$(CURDIR)/$(RUST_CRATE_DIR)/film_profiles" \
		$(CARGO) check --manifest-path $(RUST_CRATE_DIR)/Cargo.toml
	@for profile in provia_inspired velvia_inspired astia_inspired e100_inspired ektar_inspired chrome64_inspired; do \
		file="$(RUST_CRATE_DIR)/film_profiles/$$profile/lut.cube"; \
		test -f "$$file"; \
		grep -q '^LUT_3D_SIZE 33$$' "$$file"; \
		test "$$(grep -E '^[0-9.-]+[[:space:]]+[0-9.-]+[[:space:]]+[0-9.-]+$$' "$$file" | wc -l | tr -d ' ')" = "35937"; \
	done
	@echo "[Pixel Craft] Film Profile Pack v2 materialized: 6 x 33^3 LUTs"

creative-luts: ## Materialize photon-rs creative filters as canonical 33^3 .cube files
	$(CARGO) run --quiet --manifest-path $(RUST_CRATE_DIR)/Cargo.toml \
		--bin generate_creative_luts -- --output "$(CURDIR)/$(RUST_CRATE_DIR)/creative_luts"
	@for profile in vintage oceanic lofi dramatic golden pastel_pink; do \
		file="$(RUST_CRATE_DIR)/creative_luts/$$profile/lut.cube"; \
		test -f "$$file"; \
		grep -q '^LUT_3D_SIZE 33$$' "$$file"; \
		test "$$(grep -E '^[0-9.-]+[[:space:]]+[0-9.-]+[[:space:]]+[0-9.-]+$$' "$$file" | wc -l | tr -d ' ')" = "35937"; \
	done
	@echo "[Pixel Craft] Creative Filter LUTs materialized: 6 x 33^3 LUTs"

gpu-luts: film-luts creative-luts ## Generate deterministic RGBA8 33^3 LUT atlases for native GPU preview
	python3 tool/generate_gpu_lut_atlas.py --output "$(GPU_LUT_DIR)"
	python3 tool/generate_gpu_creative_lut_atlas.py --output "$(GPU_LUT_DIR)"
	python3 tool/generate_gpu_native_parity_fixture.py --output "$(GPU_LUT_DIR)/native_parity.json"

gpu-lut-verify: film-luts creative-luts ## Verify Film and Creative GPU atlas sampling parity
	python3 tool/generate_gpu_lut_atlas.py --verify-only
	python3 tool/generate_gpu_creative_lut_atlas.py --verify-only

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

format-check: ## Fail if tracked Dart files require formatting
	@git ls-files '*.dart' -z | xargs -0 dart format --output=none --set-exit-if-changed

analyze: ## Run Flutter analyzer
	$(FLUTTER) analyze

test: test-unit test-gpu test-widget ## Run Dart unit, GPU plan/session and widget tests, excluding goldens

test-unit: ## Run controller/state tests
	$(FLUTTER) test test/state

test-gpu: ## Run GPU presentation/render-plan unit tests
	$(FLUTTER) test test/gpu

test-widget: ## Run widget tests
	$(FLUTTER) test test/ui --exclude-tags=golden

test-fast: test ## Run fast host-side Flutter tests without goldens/integration/device suites

package-check: ## Analyze/test split Flutter packages without platform builds
	@set -euo pipefail; \
	for pkg in packages/dxtr_pixs_editing packages/dxtr_pixs_film; do \
		echo "[Pixel Craft] Dart package check: $$pkg"; \
		(cd "$$pkg" && dart pub get && dart analyze && dart test); \
	done; \
	for pkg in packages/dxtr_pixs_engine packages/dxtr_pixs_gpu; do \
		echo "[Pixel Craft] Flutter package check: $$pkg"; \
		(cd "$$pkg" && $(FLUTTER) pub get && $(FLUTTER) analyze); \
		if [ -d "$$pkg/test" ]; then (cd "$$pkg" && $(FLUTTER) test); fi; \
	done

gpu-check: ## Run cheap shared GPU/native Rust formatting, lint and tests on the host
	$(CARGO) fmt --manifest-path $(GPU_CRATE_DIR)/Cargo.toml --all -- --check
	$(CARGO) clippy --manifest-path $(GPU_CRATE_DIR)/Cargo.toml --all-targets -- -D warnings
	$(CARGO) test --manifest-path $(GPU_CRATE_DIR)/Cargo.toml

device-safety-check: ## Verify G6 verifier isolation and primary app identifier policy
	bash tool/ci_device_safety_guard.sh

ci-fast: ## Mandatory cheap CI gate before platform/native build jobs
	@$(MAKE) format-check
	@$(MAKE) pub-get
	@$(MAKE) analyze
	@$(MAKE) package-boundaries
	@$(MAKE) test-fast
	@$(MAKE) package-check
	@$(MAKE) rust-fmt
	@$(MAKE) rust-clippy
	@$(MAKE) rust-test
	@$(MAKE) gpu-check
	@$(MAKE) device-safety-check

preflight: ## Run the same fast checks locally before pushing
	@$(MAKE) ci-fast

package-boundaries: ## Verify package dependency direction contracts
	bash tool/check_package_boundaries.sh

golden-test: ## Compare UI with committed golden PNG files
	$(FLUTTER) test test/golden

golden-update: ## Create or update golden PNG files
	$(FLUTTER) test --update-goldens test/golden

native-test: ensure-rust-plugin ## Run real Rust bridge smoke test on DEVICE
	@test -n "$(DEVICE)" || { echo "ERROR: use DEVICE=<device-id>" >&2; exit 1; }
	$(FLUTTER) test integration_test/native_engine_smoke_test.dart -d $(DEVICE)

gpu-native-test: ensure-rust-plugin ## Run Android OpenGL LUT shader harness on DEVICE
	@test -n "$(DEVICE)" || { echo "ERROR: use DEVICE=<device-id>" >&2; exit 1; }
	$(FLUTTER) test integration_test/gpu_preview_harness_test.dart -d $(DEVICE)

g3-device-verify: ensure-rust-plugin ## Run isolated G3 iOS GPU verification app; DEVICE=<ios-device-id>
	@test -n "$(DEVICE)" || { echo "ERROR: use DEVICE=<ios-device-id>" >&2; exit 1; }
	DEVICE="$(DEVICE)" FLUTTER="$(FLUTTER)" bash tool/verify_g3_device.sh

profile-native: ensure-rust-plugin ## Print device timing and RSS metrics; DEVICE=<id>
	@test -n "$(DEVICE)" || { echo "ERROR: use DEVICE=<device-id>" >&2; exit 1; }
	$(FLUTTER) test integration_test/performance_profile_test.dart -d $(DEVICE)

rust-fmt: ## Check Rust formatting
	$(CARGO) fmt --manifest-path $(RUST_CRATE_DIR)/Cargo.toml --all -- --check

rust-clippy: ## Run strict Rust lints
	$(CARGO) clippy --manifest-path $(RUST_CRATE_DIR)/Cargo.toml --all-targets -- -D warnings

rust-test: ## Run Rust unit tests
	$(CARGO) test --manifest-path $(RUST_CRATE_DIR)/Cargo.toml

test-full: analyze rust-fmt rust-clippy rust-test gpu-lut-verify test golden-test ## Run complete host-side suite

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
