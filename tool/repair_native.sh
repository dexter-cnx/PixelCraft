#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

FRB_VERSION="2.12.0"

echo "[PixelCraft] Checking prerequisites..."
command -v flutter >/dev/null || { echo "Flutter is required" >&2; exit 1; }
command -v cargo >/dev/null || { echo "Rust/Cargo is required" >&2; exit 1; }

if ! command -v flutter_rust_bridge_codegen >/dev/null; then
  cargo install flutter_rust_bridge_codegen --version "$FRB_VERSION" --locked
fi

# Ensure platform folders exist before FRB adds Cargokit integration.
flutter create --platforms=android,ios --org dev.pixelcraft .
flutter pub get

echo "[PixelCraft] Installing Cargokit integration..."
flutter_rust_bridge_codegen integrate \
  --template app \
  --no-write-lib \
  --no-integration-test \
  --rust-crate-name pixelcraft_engine \
  --rust-crate-dir rust

echo "[PixelCraft] Regenerating bridge..."
flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml

# Remove stale build outputs that may have been produced before native integration.
flutter clean
rm -rf build android/.gradle rust/target
flutter pub get

echo
if [[ ! -d rust_builder/cargokit ]]; then
  echo "ERROR: rust_builder/cargokit was not created." >&2
  echo "Run: flutter_rust_bridge_codegen integrate --template app" >&2
  exit 1
fi

echo "[PixelCraft] Native integration repaired."
echo "Run: flutter run"
