# pixelcraft_engine Code Walkthrough

`pixelcraft_engine` is PixelCraft's Flutter FFI/build-integration package for the repository-level Rust image engine.

It exists to make the Rust crate consumable by Flutter across supported platforms. It does **not** own the editing semantics themselves.

## 1. Responsibility boundary

Canonical ownership:

```text
Flutter app
   ↓
pixelcraft_engine
   ↓ Flutter Rust Bridge / CargoKit
root rust/ crate
   ↓
authoritative image semantics
```

`pixelcraft_engine` owns:

- Flutter plugin metadata and package wiring
- Flutter Rust Bridge integration
- CargoKit native build glue
- Android/iOS/macOS/Linux/Windows packaging integration
- normalization of generated FRB `rust_builder` layout

`pixelcraft_engine` does not own:

- edit recipes
- history semantics
- Apply checkpoints
- recovery policy
- filter behavior
- Film Profile semantics
- full-resolution export policy

Those remain authoritative in `rust/`.

## 2. Package layout

```text
packages/pixelcraft_engine/
├── android/
├── ios/
├── linux/
├── macos/
├── windows/
├── cargokit/
├── lib/
├── pubspec.yaml
├── README.md
└── CODE_WALKTHROUGH.md
```

The package is internal to the monorepo:

```yaml
publish_to: none
```

The authoritative Rust crate is deliberately not nested inside this package:

```text
PixelCraft/
├── packages/pixelcraft_engine/
└── rust/
```

This keeps the build plugin separate from the semantic engine.

## 3. Flutter dependency wiring

The root Flutter app consumes the package using a path dependency:

```yaml
pixelcraft_engine:
  path: packages/pixelcraft_engine
```

The generated Dart FRB API used by the app is still generated from the root Rust API configuration. `pixelcraft_engine` provides the native artifact integration required for those bindings to work on device.

Conceptually:

```text
Dart generated bindings
   ↓
FRB runtime
   ↓
pixelcraft_engine platform plugin
   ↓
CargoKit native artifact
   ↓
pixelcraft_engine Rust library
```

## 4. Rust source of truth

Important root Rust files include:

```text
rust/src/api.rs
rust/src/engine.rs
rust/src/filters.rs
rust/src/advanced_filters.rs
rust/src/film_profiles.rs
```

The exact list evolves, but the rule does not:

> Semantic image behavior belongs in the root Rust crate, not in the Flutter build package.

If a new editing feature changes output pixels or recipe semantics, implement and test it in Rust first.

## 5. FRB code generation flow

PixelCraft pins Flutter Rust Bridge code generation.

Typical flow:

```text
rust/src/api.rs
   ↓
flutter_rust_bridge_codegen
   ↓
generated Rust bridge
   +
generated Dart bridge
   ↓
Flutter app calls Rust API
```

Recommended command:

```bash
make codegen
```

or directly through project tooling:

```bash
./tool/codegen.sh
```

FRB may regenerate a conventional root-level directory:

```text
rust_builder/
```

PixelCraft's monorepo layout normalizes that generated integration back into:

```text
packages/pixelcraft_engine/
```

Use:

```bash
python3 tool/normalize_rust_builder_layout.py
```

or:

```bash
make integrate
```

Do not treat a newly generated root `rust_builder/` as a new architecture decision.

## 6. CargoKit integration

CargoKit is responsible for compiling and packaging the root Rust crate into artifacts suitable for Flutter platform builds.

The important path invariant after P0 is:

```text
packages/pixelcraft_engine/<platform glue>
        ↓ relative path
rust/
```

Because `pixelcraft_engine` moved one directory deeper during P0, platform scripts use adjusted relative paths back to `rust/`.

Examples conceptually:

```text
Android plugin  → ../../../rust
Apple plugin    → ../../../rust
Linux/Windows   → equivalent normalized relative path
```

Exact scripts should be treated as build infrastructure, not semantic engine code.

## 7. Android runtime packaging

Android build flow:

```text
Flutter Gradle build
   ↓
pixelcraft_engine Android plugin
   ↓
CargoKit
   ↓
compile Rust for target ABI
   ↓
libpixelcraft_engine.so
   ↓
APK/AAB
```

A common failure is:

```text
libpixelcraft_engine.so is missing from APK
```

Recovery path:

```bash
make repair
make verify-native
```

Manual verification:

```bash
unzip -l build/app/outputs/flutter-apk/app-debug.apk | grep libpixelcraft_engine.so
```

For a typical ARM64 device the artifact should appear under:

```text
lib/arm64-v8a/
```

## 8. iOS runtime packaging

iOS build flow:

```text
Flutter/CocoaPods build
   ↓
pixelcraft_engine pod/plugin
   ↓
CargoKit Rust build phase
   ↓
static Rust archive
   ↓
link into Runner
```

The current iOS integration still depends on CocoaPods/CargoKit semantics. A SwiftPM migration must reproduce the same Rust build, architecture selection, archive output, and linker behavior before CocoaPods can be removed safely.

See:

```text
docs/IOS_SWIFTPM_MIGRATION.md
```

## 9. Gradle 9 compatibility

Flutter 3.44+ can expose Gradle 9 compatibility issues in generated CargoKit scripts.

PixelCraft includes tooling to patch the generated integration rather than manually editing generated files each time.

Useful commands:

```bash
make patch-cargokit
make repair
make verify-native
```

The normalization/patch tooling is part of the package integration contract.

## 10. Failure model

`pixelcraft_engine` should fail loudly when the native library cannot be built or packaged.

It must never silently fall back to a different implementation of committed editing semantics.

Examples of valid failures:

```text
Rust compile error
FRB generation mismatch
missing native artifact
linker failure
unsupported target build
```

These are build/integration failures and should remain visible in CI.

## 11. Testing and validation

Primary validation layers:

```bash
cargo fmt --manifest-path rust/Cargo.toml --all -- --check
cargo clippy --manifest-path rust/Cargo.toml --all-targets -- -D warnings
cargo test --manifest-path rust/Cargo.toml
flutter analyze
make verify-native
```

CI additionally exercises Android and iOS packaging smoke paths so changes to native build glue do not pass based on Dart/Rust unit tests alone.

P0 was considered complete only after native packaging CI passed.

## 12. How to extend this package safely

When changing `pixelcraft_engine`, first classify the change.

### Build/integration change

Examples:

- new platform configuration
- CargoKit path fix
- linker flag
- FRB package wiring

This belongs here.

### Image-semantic change

Examples:

- new filter
- recipe operation
- history behavior
- export behavior

This belongs in `rust/`, not here.

### Flutter app behavior

Examples:

- UI state
- navigation
- editor tool behavior

This belongs in the app or a higher-level domain package, not here.

## 13. Architectural invariant

The most important invariant is:

```text
pixelcraft_engine = native build/FFI boundary
rust/             = image semantic authority
```

Keeping those responsibilities separate prevents generated/native build infrastructure from becoming a second implementation of PixelCraft's editing model.
