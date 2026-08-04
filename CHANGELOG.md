# Changelog

## 0.2.0

- Added `photon-rs 0.3.3` as an internal creative-filter backend.
- Added grayscale, invert, vintage, oceanic, lofi, dramatic, golden and pastel-pink filters.
- Added explicit Photon preset validation.
- Added Rayon intensity blending for creative filters.
- Replaced cumulative slider processing with begin/preview/commit transactions.
- Changed history behavior to one undo entry per completed slider gesture.
- Retained stateless filter API for compatibility and benchmark use.

## Documentation

- Added `docs/CODE_WALKTHROUGH.md` covering startup, Flutter/Riverpod flow, FRB bindings, Rust engine transactions, filters, histogram, undo/redo, benchmarking, memory behavior, and recommended next improvements.

## 0.1.3

- Added an explicit Cargokit repair script for Android native-library bundling.
- Made bootstrap verify that `rust_builder/cargokit` exists.
- Added troubleshooting for `libpixelcraft_engine.so not found`.

## Gradle 9 / Flutter 3.44 compatibility

- Added `tool/patch_cargokit_gradle9.py`.
- Replaced CargoKit's removed `Project.exec` calls with injected `ExecOperations`.
- `make integrate`, `make setup`, and `make repair` now patch generated CargoKit automatically.
