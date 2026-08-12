# PixelCraft

PixelCraft is an offline-first mobile photo editor and film-emulation camera built with Flutter, Rust, and native GPU preview runtimes.

The core architectural rule is simple:

> **Rust owns committed image semantics. GPU owns low-latency preview only. Flutter owns product UI and control flow.**

## Current architecture

After the P0/P1 package extraction, PixelCraft is moving toward a package-oriented monorepo:

```text
PixelCraft/
├── apps/
│   └── pixelcraft/                # target app shell
├── packages/
│   ├── pixelcraft_engine/         # Flutter FFI/native build integration for Rust
│   ├── pixelcraft_gpu/            # preview-only GPU control plane + native runtime
│   ├── pixelcraft_editing/        # planned P2 editing domain package
│   └── pixelcraft_film/           # planned film/profile package
├── rust/                           # authoritative image engine and recipe semantics
├── docs/
└── melos.yaml
```

The current root Flutter app still contains application code that will be migrated incrementally into `apps/pixelcraft` and domain packages.

## Responsibility boundaries

| Layer | Responsibility |
|---|---|
| Flutter app | UI, gestures, navigation, Riverpod state projection, product workflow |
| `pixelcraft_engine` | FRB/CargoKit/native build integration for the repository Rust crate |
| Rust `rust/` | authoritative edits, recipe, history, checkpoints, recovery and full-resolution export |
| `pixelcraft_gpu` | preview-only Dart control plane plus Android OpenGL ES/Camera2 and iOS Metal/AVFoundation runtime |
| Native GPU | realtime camera/editor preview only; never final render authority |

Hard contracts:

1. Rust owns committed edit semantics, recipe, history, checkpoints, recovery and export.
2. GPU preview is never the final source of truth.
3. Camera Film is preview-only; captured source remains clean.
4. Live camera frame buffers never cross Dart `MethodChannel` or Flutter Rust Bridge.
5. Canonical Film/Creative LUT data originates from Rust-owned data.
6. Unsupported operation order or native failure falls back to a valid Rust/product state.
7. New effects are defined and tested in Rust first; GPU support is optional and must be faithful.
8. Film Profiles are reusable configuration data, not captured pixels or per-image session state.

## Package status

### `packages/pixelcraft_engine`

P0 extracted the Flutter FFI/native build plugin into a dedicated package. It contains the CargoKit/platform glue required to compile and bundle the repository-level Rust engine.

See [`packages/pixelcraft_engine/README.md`](packages/pixelcraft_engine/README.md).

### `packages/pixelcraft_gpu`

P1 extracted the reusable preview control plane and native GPU runtime into a Flutter plugin package.

It contains:

- Dart camera/editor GPU bridges
- GPU render-plan/draft-session support
- Android OpenGL ES + Camera2 runtime
- iOS Metal + AVFoundation runtime
- diagnostics and frame-pacing bridges

The app retains thin adapters where GPU policy still depends on app-owned editing models. Those are the main P2 extraction target.

See [`packages/pixelcraft_gpu/README.md`](packages/pixelcraft_gpu/README.md).

## Rendering model

```text
Camera / imported image
        ↓
clean source image
        ↓
Flutter product state
        ↓
interactive native GPU preview when faithfully representable
        ↓ gesture release / command
Rust semantic recipe
        ↓
authoritative reduced preview + history + checkpoint
        ↓
full-resolution Rust replay/export
```

### Camera preview

Android eligible path:

```text
Camera2
 -> SurfaceTexture / OES
 -> OpenGL ES canonical LUT/effects
 -> Android PlatformView
```

iOS eligible path:

```text
AVCaptureVideoDataOutput
 -> CVPixelBuffer
 -> CVMetalTextureCache
 -> Metal canonical LUT/effects
 -> UIKit PlatformView
```

If native preview is unavailable or fails, PixelCraft fails closed to its valid fallback path.

### Editor preview

Interactive GPU preview may represent only operations whose order and semantics match the authoritative Rust recipe. Unsupported graphs do not get silently reordered or approximated.

## Rust engine

Rust authority lives under:

```text
rust/src/api.rs
rust/src/engine.rs
rust/src/filters.rs
rust/src/advanced_filters.rs
```

Rust retains:

- untouched source bytes
- reduced editor preview
- Apply checkpoint preview
- complete operation list
- cursor / checkpoint cursor
- undo / redo state

Export always replays the authoritative recipe from the clean source. Native GPU pixels are never export input.

## Film Profiles

PixelCraft supports reusable Film Profiles that can be created, edited, duplicated, imported and applied to an editor session.

A Film Profile deliberately does not contain:

- source image
- crop/rotate session state
- Editor history
- checkpoint cursor
- captured GPU pixels

Imported recipe fields are classified as `exact`, `approximated`, or `unsupported`; unsupported settings must never be silently discarded.

## Development requirements

- Flutter 3.44+
- Dart 3.12+
- Rust stable
- Android Studio / Android SDK
- Xcode for iOS
- iOS 13+
- `flutter_rust_bridge_codegen` 2.12.0

## Common workflow

```bash
make help
make setup
make codegen
make check
```

Run the app:

```bash
make run
```

Specify a device when needed:

```bash
make run DEVICE=<device-id>
```

Native integration repair/verification:

```bash
make repair
make verify-native
```

Useful targets:

```bash
make codegen
make codegen-watch
make rust-fmt
make rust-clippy
make rust-test
make gpu-lut-verify
make golden-test
make run-release
make adb-abi
```

## CI / validation gates

The primary CI validates:

- FRB regeneration consistency
- Rust fmt / clippy / tests
- G6 image characterization
- GPU LUT parity
- Flutter analyze
- state tests
- GPU plan/session tests
- widget tests
- Android native packaging smoke
- golden tests
- iOS native packaging smoke

P1 was closed only after CI passed and physical smoke testing succeeded on both iOS and Android.

Before release, use at minimum:

```bash
cargo fmt --manifest-path rust/Cargo.toml --all -- --check
cargo clippy --manifest-path rust/Cargo.toml --all-targets -- -D warnings
cargo test --manifest-path rust/Cargo.toml
flutter analyze
flutter test
make verify-native
```

## Current roadmap

```text
G1  Camera GPU Preview                          CLOSED
G2  Editor GPU Preview Foundation               CLOSED
G3  Production Rendering Pipeline               CLOSED
G4  Product Editor UX / Session Workflow        CLOSED
G5  Editing Feature Completeness                CLOSED / VERIFIED
G6  Reliability / Performance / Device Matrix   CLOSED / VERIFIED
P0  Extract pixelcraft_engine                   CLOSED / MERGED
P1  Extract pixelcraft_gpu                      CLOSED / MERGED
P2  Extract pure editing models/semantics       NEXT
G7  Release / Beta / Store Readiness            PRESERVED / TO REBASE
```

P2 should move app-owned pure editing models such as `EditGraphDocument` / `EditNodeType` into `packages/pixelcraft_editing`, allowing remaining GPU renderer/capability adapters to stop depending on root app code.

## Documentation

- [`docs/CODE_WALKTHROUGH.md`](docs/CODE_WALKTHROUGH.md)
- [`docs/PROJECT_HANDOFF.md`](docs/PROJECT_HANDOFF.md)
- [`docs/G6_RELIABILITY_MATRIX.md`](docs/G6_RELIABILITY_MATRIX.md)
- [`docs/IOS_SWIFTPM_MIGRATION.md`](docs/IOS_SWIFTPM_MIGRATION.md)
- [`packages/pixelcraft_engine/README.md`](packages/pixelcraft_engine/README.md)
- [`packages/pixelcraft_gpu/README.md`](packages/pixelcraft_gpu/README.md)

## License

MIT
