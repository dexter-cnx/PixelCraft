FLUTTER ?= flutter
DART ?= dart
CARGO ?= cargo
FRB ?= flutter_rust_bridge_codegen
DEVICE ?=
APK ?= build/app/outputs/flutter-apk/app-debug.apk
RUST_CRATE_DIR ?= rust
RUST_BUILDER_DIR ?= rust_builder
GPU_LUT_DIR ?= build/gpu_luts

DEVICE_FLAG := $(if $(strip $(DEVICE)),-d $(DEVICE),)

.PHONY: help doctor frb-info install-frb platforms pub-get ensure-rust-plugin integrate codegen codegen-watch \
        setup repair patch-cargokit app-icon film-luts creative-luts gpu-luts gpu-lut-verify gpu-native-test run run-release clean clean-all \
        analyze test test-unit test-gpu test-widget golden-test golden-update native-test profile-native test-full \
        rust-fmt rust-clippy rust-test check build-apk build-apk-release verify-native adb-abi

help: ## Show available commands
	@printf "Pixel Craft development commands\n\n"
	@awk 'BEGIN {FS = ":.*## ";} /^[a-zA-Z0-9_-]+:.*## / {printf "  %-22s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

doctor: ## Show Flutter / Dart / Rust toolchain versions
	$(FLUTTER) --version
	$(DART) --version
	$(CARGO) --version
	rustc --version

frb-info: ## Show Flutter Rust Bridge codegen version
	$(FRB) --version

install-frb: ## Install the pinned Flutter Rust Bridge codegen CLI
	$(CARGO) install flutter_rust_bridge_codegen --version 2.12.0 --locked

platforms: ## Install Android/iOS Flutter platform artifacts
	$(FLUTTER) precache --android --ios

pub-get: ## Resolve Flutter dependencies
	$(FLUTTER) pub get

ensure-rust-plugin: ## Verify local pixelcraft_engine package is present
	@test -f "$(RUST_BUILDER_DIR)/pubspec.yaml" || { echo "ERROR: missing $(RUST_BUILDER_DIR)/pubspec.yaml" >&2; exit 1; }

integrate: ## Integrate CargoKit / Flutter Rust Bridge host files
	$(FRB) integrate

codegen: ## Regenerate Flutter Rust Bridge Dart/Rust/Swift bindings
	$(FRB) generate

codegen-watch: ## Watch Rust API changes and regenerate bindings
	$(FRB) generate --watch

patch-cargokit: ## Apply local CargoKit compatibility patch when required
	@python3 tool/patch_cargokit.py

app-icon: ## Generate application launcher icons
	$(DART) run flutter_launcher_icons

film-luts: ## Materialize Film Profile Pack v2 as inspectable 33^3 .cube files
	$(CARGO) run --quiet --manifest-path $(RUST_CRATE_DIR)/Cargo.toml \
		--bin generate_film_luts -- --output "$(CURDIR)/$(RUST_CRATE_DIR)/film_luts"
	@for profile in provia_inspired velvia_inspired astia_inspired e100_inspired ektar_inspired chrome64_inspired; do \
		file="$(RUST_CRATE_DIR)/film_luts/$$profile/lut.cube"; \
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

analyze: ## Run Flutter analyzer
	$(FLUTTER) analyze

test: test-unit test-gpu test-widget ## Run Dart unit/GPU/widget tests, excluding goldens

test-unit: ## Run controller/state tests
	$(FLUTTER) test test/state

test-gpu: ## Run GPU presentation/render-plan unit tests
	$(FLUTTER) test test/gpu

test-widget: ## Run widget tests
	$(FLUTTER) test test/ui --exclude-tags=golden

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
	adb shell getprop ro.product.cpu.abi
