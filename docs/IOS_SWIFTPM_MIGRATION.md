# iOS Swift Package Manager Migration

## Status

PixelCraft is migrating iOS plugin dependencies from CocoaPods toward Swift Package Manager (SwiftPM), but the migration must preserve the existing Rust/Flutter Rust Bridge native build path.

Current status on `feature/editor-product-ux`:

- Flutter toolchain baseline: Flutter 3.44.x / Dart 3.12.x or newer.
- iOS deployment target: 13.0.
- `saver_gallery`: pinned to `5.0.3`, a SwiftPM-compatible release that preserves the existing `androidRelativePath` API used by `ExportFileService`.
- `pixelcraft_engine`: **not migrated to SwiftPM yet**.
- CocoaPods remains required for `pixelcraft_engine` because its podspec runs the Cargokit Rust build script and force-loads the generated `libpixelcraft_engine.a` into the iOS target.

## Why `pixelcraft_engine` cannot be converted by adding only `Package.swift`

The current native integration is not a normal source-only Flutter plugin. The iOS podspec performs two essential build/link steps:

```text
CocoaPods target
  -> Cargokit build_pod.sh
  -> cargo builds Rust static library
  -> ${BUILT_PRODUCTS_DIR}/libpixelcraft_engine.a
  -> OTHER_LDFLAGS -force_load
  -> Runner links Rust symbols used by flutter_rust_bridge
```

A minimal Swift package manifest that only exposes `Classes/dummy_file.c` would remove the CocoaPods warning, but it would not reproduce the Rust build phase or the `-force_load` linker contract. That would risk a successful Xcode project resolution followed by missing FRB/Rust symbols at link or runtime.

For that reason PixelCraft keeps the existing podspec until the SwiftPM path can reproduce all of the following:

1. Build the `rust/` crate for device and simulator architectures.
2. Rebuild when Rust sources or Cargo metadata change.
3. Place the native archive where Xcode can consume it.
4. Link the archive into Runner without dead-stripping FRB entry points.
5. Work for Debug, Profile and Release.
6. Preserve Flutter Rust Bridge code generation and existing Cargokit behavior.
7. Pass physical-device native-engine smoke tests.

## `saver_gallery` migration

PixelCraft previously used:

```yaml
saver_gallery: ^4.1.2
```

It is now pinned to:

```yaml
saver_gallery: 5.0.3
```

The 5.0.3 line supports SwiftPM while retaining the API shape currently used by PixelCraft:

```dart
SaverGallery.saveImage(
  bytes,
  quality: 100,
  fileName: fileName,
  androidRelativePath: 'Pictures/PixelCraft',
  skipIfExists: false,
)
```

PixelCraft intentionally did not jump directly to a newer release with additional breaking API changes during the G4 verification window. The dependency migration and editor behavior should not be changed in the same step unless required.

## iOS deployment target

The Xcode project already targets iOS 13.0. The Podfile now declares the same value explicitly:

```ruby
platform :ios, '13.0'
```

This keeps CocoaPods, SwiftPM-enabled plugins and the Runner target aligned.

## Migration strategy for `pixelcraft_engine`

Treat this as a native build-system migration, not a manifest-only cleanup.

Recommended phases:

### Phase 1 — isolate the Rust build contract

Create a deterministic script callable outside CocoaPods that accepts Xcode environment/architecture inputs and produces a known archive/output directory.

The script should reuse Cargokit behavior where practical rather than duplicate target-selection logic.

### Phase 2 — SwiftPM build-tool integration prototype

Prototype either:

- a SwiftPM build-tool plugin that invokes the Rust builder; or
- an Xcode Runner build phase paired with a local Swift package target.

The prototype must produce and link the same Rust artifact as the podspec path.

### Phase 3 — dual-path verification

Keep CocoaPods as the reference implementation while comparing:

```text
CocoaPods/Cargokit build
vs
SwiftPM/native build path
```

Verify:

- simulator arm64
- physical-device arm64
- Debug
- Profile
- Release
- clean build after deleting DerivedData
- incremental rebuild after editing Rust source
- FRB API call smoke test
- full-resolution Rust export

### Phase 4 — remove the podspec path

Only remove `rust_builder/ios/pixelcraft_engine.podspec` after the SwiftPM path passes the same native-engine and product smoke gates.

## Verification commands

Host checks:

```bash
flutter pub get
flutter analyze
flutter test
make rust-fmt
make rust-clippy
make rust-test
```

iOS native verification should additionally include a real device:

```bash
flutter clean
flutter pub get
flutter run -d <ios-device-id>
```

Then verify:

- app launches without missing native symbols
- an image can be loaded into the Rust engine
- Adjust/Creative/Film semantic commits still work
- Undo/Redo still call Rust successfully
- full-resolution export succeeds
- gallery save succeeds

## Decision rule

Do **not** remove CocoaPods solely to eliminate Flutter's deprecation warning. Remove it only when SwiftPM reproduces the native Rust build/link contract and the replacement path is verified on CI and physical iOS hardware.
