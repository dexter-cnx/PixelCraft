# pixelcraft_engine

`pixelcraft_engine` is PixelCraft's internal Flutter FFI/native build package for the repository-level Rust image engine.

It is **not** the image-processing authority itself. The authoritative engine remains in the top-level `rust/` crate. This package exists to make that Rust engine consumable from Flutter in a stable package boundary.

## Ownership

```text
Flutter app
   ↓
pixelcraft_engine
   ↓ FRB / CargoKit / native packaging
rust/
```

Rust owns:

- committed edit semantics
- operation recipe
- history / undo / redo
- Apply checkpoints
- recovery serialization contract
- full-resolution replay/export
- canonical Film/Creative LUT generation

`pixelcraft_engine` owns:

- Flutter package boundary for native engine integration
- CargoKit build glue
- Android/iOS native packaging integration
- FRB-facing generated/native bridge support
- normalization of generated builder layout

## Repository layout

```text
packages/pixelcraft_engine/
├── android/
├── ios/
├── cargokit/
├── lib/
├── pubspec.yaml
└── README.md

rust/
├── src/
├── film_profiles/
├── creative_luts/
└── Cargo.toml
```

The package is internal to the PixelCraft monorepo:

```yaml
publish_to: none
```

## Important invariant

Do not move authoritative image semantics into Dart or platform-specific plugin code merely to make integration easier.

The intended direction remains:

```text
Flutter UI/control
    ↓
FRB
    ↓
Rust semantic engine
```

GPU preview is a separate concern handled by `pixelcraft_gpu`; it must not become an alternate committed-render authority.

## FRB / CargoKit workflow

PixelCraft uses `flutter_rust_bridge_codegen` 2.12.0 and CargoKit for native build integration.

Typical commands from repository root:

```bash
make codegen
make integrate
make repair
make verify-native
```

After Rust API changes:

```bash
make codegen
```

Continuous generation:

```bash
make codegen-watch
```

If FRB regeneration creates a temporary root-level `rust_builder/`, normalize it back into this package with:

```bash
python3 tool/normalize_rust_builder_layout.py
```

or simply:

```bash
make integrate
```

## Android packaging

The package must produce and bundle the Rust shared library into the final APK/AAB.

A useful verification is:

```bash
make verify-native
```

For a typical arm64 Android device the APK should contain:

```text
lib/arm64-v8a/libpixelcraft_engine.so
```

When native packaging is broken, use:

```bash
make repair
make verify-native
```

## iOS packaging

The current iOS native engine integration still depends on CargoKit/CocoaPods build behavior. Do not remove the existing Rust build/link contract merely because Swift Package Manager is being adopted elsewhere.

The migration requirement is stricter than adding a `Package.swift`: any replacement must reproduce Rust compilation, target architecture selection, archive generation and linker behavior.

See:

- `docs/IOS_SWIFTPM_MIGRATION.md`

## Validation

Engine/package changes should pass at minimum:

```bash
cargo fmt --manifest-path rust/Cargo.toml --all -- --check
cargo clippy --manifest-path rust/Cargo.toml --all-targets -- -D warnings
cargo test --manifest-path rust/Cargo.toml
flutter analyze
make verify-native
```

CI also regenerates the FRB bridge and verifies that generated native bridge files remain committed/consistent.

## Relationship to other packages

```text
pixelcraft_editing   (planned pure editing domain)
        ↓
pixelcraft_gpu       (preview only)
        ↓ where native preview needs engine-aligned contracts
pixelcraft_engine
        ↓
rust/
```

Avoid dependency cycles. In particular, `pixelcraft_engine` must not depend on app source.

## Status

P0 package extraction is complete and merged. The package is now the canonical Flutter/native integration boundary for the Rust engine.
