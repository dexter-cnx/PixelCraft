#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

command -v flutter >/dev/null || { echo "Flutter 3.22+ is required"; exit 1; }
command -v cargo >/dev/null || { echo "Rust is required"; exit 1; }

# Create only missing native platform scaffolding while preserving source files.
flutter create --platforms=android,ios,macos,windows,linux --org dev.pixelcraft .
flutter pub get

if ! command -v flutter_rust_bridge_codegen >/dev/null; then
  cargo install flutter_rust_bridge_codegen --version 2.12.0
fi

# Cargokit/native platform integration is idempotent for a freshly-created app.
flutter_rust_bridge_codegen integrate --no-write-lib --no-integration-test --rust-crate-name pixelcraft_engine --rust-crate-dir rust
flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml
flutter pub get

echo "PixelCraft is ready. Run: flutter run"
