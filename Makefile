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
        setup repair patch-cargokit run run-release clean clean-all analyze test rust-fmt rust-clippy \
        rust-test check build-apk build-apk-release verify-native adb-abi

help: ## Show available Make targets
	@printf "PixelCraft development commands\n\n"
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z0-9_.-]+:.*## / {printf "  %-20s %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@printf "\nExamples:\n"
	@printf "  make setup\n"
	@printf "  make run DEVICE=<device-id>\n"
	@printf "  make repair\n"
	@printf "  make verify-native\n"

doctor: ## Check required Flutter, Rust, Java and Android tooling
	@command -v $(FLUTTER) >/dev/null || { echo "ERROR: Flutter is required" >&2; exit 1; }
	@command -v $(CARGO) >/dev/null || { echo "ERROR: Rust/Cargo is required" >&2; exit 1; }
	@echo "== Flutter =="
	@$(FLUTTER) --version
	@echo
	@echo "== Rust =="
	@$(CARGO) --version
	@rustc --version
	@echo
	@$(FLUTTER) doctor -v

frb-info: ## Show every FRB executable on PATH and the pinned executable version
	@echo "== FRB executables on PATH =="
	@type -a flutter_rust_bridge_codegen 2>/dev/null || true
	@echo
	@echo "== Pinned executable =="
	@if [ -x "$(FRB_CODEGEN)" ]; then "$(FRB_CODEGEN)" --version; else echo "Not installed: $(FRB_CODEGEN)"; fi

install-frb: doctor ## Install or replace FRB codegen with the exact project version
	@current=""; \
	if [ -x "$(FRB_CODEGEN)" ]; then \
		current="$$($(FRB_CODEGEN) --version 2>/dev/null || true)"; \
	fi; \
	case "$$current" in \
		*"$(FRB_VERSION)"*) echo "[PixelCraft] Using $$current" ;; \
		*) \
			echo "[PixelCraft] Installing exact flutter_rust_bridge_codegen $(FRB_VERSION)..."; \
			$(CARGO) install flutter_rust_bridge_codegen --version "$(FRB_VERSION)" --locked --force; \
			;; \
	esac
	@"$(FRB_CODEGEN)" --version

platforms: doctor ## Create missing Android and iOS platform projects
	$(FLUTTER) create --platforms=android,ios --org dev.pixelcraft .

ensure-rust-plugin: ## Verify that Flutter depends on the generated local Rust plugin
	@test -f "$(RUST_BUILDER_DIR)/pubspec.yaml" || { \
		echo "ERROR: $(RUST_BUILDER_DIR)/pubspec.yaml is missing. Run: make integrate" >&2; \
		exit 1; \
	}
	@$(FLUTTER) pub deps --style=compact 2>/dev/null | grep -F 'pixelcraft_engine' >/dev/null || { \
		echo "ERROR: pixelcraft_engine is not registered as a path dependency." >&2; \
		echo "Check pubspec.yaml contains:" >&2; \
		echo "  pixelcraft_engine:" >&2; \
		echo "    path: rust_builder" >&2; \
		exit 1; \
	}

pub-get: ## Resolve Flutter dependencies
	$(FLUTTER) pub get

integrate: install-frb platforms ## Install FRB Cargokit native integration
	$(FRB_CODEGEN) integrate \
		--template app \
		--no-write-lib \
		--no-integration-test \
		--rust-crate-name pixelcraft_engine \
		--rust-crate-dir $(RUST_CRATE_DIR)
	@test -d $(RUST_BUILDER_DIR)/cargokit || { \
		echo "ERROR: $(RUST_BUILDER_DIR)/cargokit was not created" >&2; \
		exit 1; \
	}
	@$(MAKE) patch-cargokit
	@$(MAKE) pub-get
	@$(MAKE) ensure-rust-plugin

patch-cargokit: ## Patch FRB 2.12 CargoKit for Gradle 9 / AGP 9
	@command -v python3 >/dev/null || { echo "ERROR: python3 is required" >&2; exit 1; }
	@python3 tool/patch_cargokit_gradle9.py

codegen: install-frb ## Regenerate Dart/Rust bridge files
	$(FRB_CODEGEN) generate --config-file flutter_rust_bridge.yaml

codegen-watch: install-frb ## Regenerate bridge continuously while Rust API changes
	$(FRB_CODEGEN) generate --config-file flutter_rust_bridge.yaml --watch

setup: integrate codegen clean-all pub-get ensure-rust-plugin ## First-time project setup with Cargokit and bridge generation
	@echo
	@echo "[PixelCraft] Setup complete. Run: make run"

repair: doctor install-frb platforms integrate codegen clean-all pub-get ensure-rust-plugin ## Repair native integration and APK packaging
	@echo
	@echo "[PixelCraft] Native integration repaired. Run: make verify-native"

run: ensure-rust-plugin ## Run debug app; optionally DEVICE=<device-id>
	$(FLUTTER) run $(DEVICE_FLAG)

run-release: ensure-rust-plugin ## Run release app; optionally DEVICE=<device-id>
	$(FLUTTER) run --release $(DEVICE_FLAG)

clean: ## Run flutter clean
	$(FLUTTER) clean

clean-all: clean ## Remove stale Flutter, Gradle and Rust build outputs
	rm -rf build android/.gradle $(RUST_CRATE_DIR)/target

analyze: ## Run Flutter static analysis
	$(FLUTTER) analyze

test: ## Run Flutter tests
	$(FLUTTER) test

rust-fmt: ## Check Rust formatting
	$(CARGO) fmt --manifest-path $(RUST_CRATE_DIR)/Cargo.toml --all -- --check

rust-clippy: ## Run strict Rust lints
	$(CARGO) clippy --manifest-path $(RUST_CRATE_DIR)/Cargo.toml --all-targets -- -D warnings

rust-test: ## Run Rust unit tests
	$(CARGO) test --manifest-path $(RUST_CRATE_DIR)/Cargo.toml

check: analyze test rust-fmt rust-clippy rust-test ## Run Flutter and Rust validation

build-apk: ensure-rust-plugin ## Build Android debug APK
	$(FLUTTER) build apk --debug

build-apk-release: ensure-rust-plugin ## Build Android release APK
	$(FLUTTER) build apk --release

verify-native: build-apk ## Verify the Cargo library declared in rust/Cargo.toml is bundled in the APK
	@command -v unzip >/dev/null || { echo "ERROR: unzip is required" >&2; exit 1; }
	@command -v python3 >/dev/null || { echo "ERROR: python3 is required" >&2; exit 1; }
	@test -f "$(APK)" || { echo "ERROR: APK not found: $(APK)" >&2; exit 1; }
	@lib_name="$$(python3 -c 'import pathlib,tomllib; p=tomllib.loads(pathlib.Path("$(RUST_CRATE_DIR)/Cargo.toml").read_text()); print(p.get("lib",{}).get("name",p["package"]["name"]).replace("-","_"))')"; \
	expected="lib$${lib_name}.so"; \
	echo "Searching $(APK) for $$expected..."; \
	matches="$$(unzip -Z1 "$(APK)" | grep -E "^lib/[^/]+/$${expected}$$" || true)"; \
	if [ -z "$$matches" ]; then \
		echo "ERROR: $$expected is missing from the APK" >&2; \
		echo >&2; \
		echo "Shared libraries currently bundled:" >&2; \
		unzip -Z1 "$(APK)" | grep -E '^lib/[^/]+/.*\.so$$' | sort >&2 || true; \
		exit 1; \
	fi; \
	printf '%s\n' "$$matches"; \
	echo "[PixelCraft] Native Rust library is bundled correctly."

adb-abi: ## Show the ABI of the connected Android device
	@command -v adb >/dev/null || { echo "ERROR: adb is required" >&2; exit 1; }
	@adb shell getprop ro.product.cpu.abi
