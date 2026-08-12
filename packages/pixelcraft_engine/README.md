# pixelcraft_engine

Flutter FFI/build-integration package for PixelCraft's Rust image engine.

`pixelcraft_engine` contains the Flutter Rust Bridge and CargoKit/platform glue required to compile and bundle the repository-level `rust/` crate into Flutter applications.

> This package is build/FFI infrastructure. The authoritative editing semantics remain in the root `rust/` crate.

## Responsibilities

`pixelcraft_engine` owns:

- Flutter plugin/package wiring
- Flutter Rust Bridge integration
- CargoKit build glue
- Android/iOS/macOS/Linux/Windows native packaging integration
- normalization of generated FRB `rust_builder` layout

It does **not** own:

- edit recipes
- history/checkpoint semantics
- filter behavior
- Film Profile semantics
- recovery policy
- full-resolution export behavior

## Repository relationship

```text
PixelCraft app
   ↓
packages/pixelcraft_engine
   ↓ FRB / CargoKit
rust/
   ↓
authoritative image engine
```

The package is internal to the PixelCraft monorepo:

```yaml
publish_to: none
```

The root app depends on it through:

```yaml
pixelcraft_engine:
  path: packages/pixelcraft_engine
```

## FRB / CargoKit workflow

Regenerating Flutter Rust Bridge integration can create a conventional root-level:

```text
rust_builder/
```

PixelCraft normalizes that generated integration back into this package.

Use:

```bash
python3 tool/normalize_rust_builder_layout.py
```

or:

```bash
make integrate
```

After changing Rust APIs:

```bash
make codegen
```

## Validation

Recommended checks from the repository root:

```bash
cargo fmt --manifest-path rust/Cargo.toml --all -- --check
cargo clippy --manifest-path rust/Cargo.toml --all-targets -- -D warnings
cargo test --manifest-path rust/Cargo.toml
flutter analyze
make verify-native
```

CI also verifies Android and iOS native packaging paths.

## Troubleshooting

If Android builds but the APK does not contain `libpixelcraft_engine.so`:

```bash
make repair
make verify-native
```

Manual inspection:

```bash
unzip -l build/app/outputs/flutter-apk/app-debug.apk | grep libpixelcraft_engine.so
```

For Gradle/CargoKit compatibility repair:

```bash
make patch-cargokit
make repair
```

## Detailed walkthrough

For the package-level architecture, FRB flow, CargoKit/native packaging, failure model, and extension rules, see:

- [`CODE_WALKTHROUGH.md`](CODE_WALKTHROUGH.md)

For the overall application architecture, see:

- [`../../docs/CODE_WALKTHROUGH.md`](../../docs/CODE_WALKTHROUGH.md)
