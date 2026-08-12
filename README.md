# PixelCraft

PixelCraft is an offline-first mobile photo editor and film-simulation camera built with Flutter, Rust, Metal, and OpenGL ES.

The architecture deliberately separates semantic authority from interactive rendering:

- **Rust is authoritative** for committed editing semantics, recipes, history, checkpoints, recovery, and full-resolution export.
- **Native GPU is preview-only** for low-latency camera/editor interaction where the current operation graph can be represented faithfully.

Images do not need to leave the device.

## Current status

As of 2026-08-12:

```text
G1  Camera GPU Preview                          CLOSED
G2  Editor GPU Preview Foundation               CLOSED
G3  Production Rendering Pipeline               CLOSED
G4  Product Editor UX / Session Workflow        CLOSED
G5  Editing Feature Completeness                CLOSED / VERIFIED
G6  Reliability / Performance / Device Matrix   CLOSED / VERIFIED

P0  pixelcraft_engine package extraction        MERGED
P1  pixelcraft_gpu package extraction           MERGED
P2  pixelcraft_editing package extraction       MERGED
P3  pixelcraft_film package extraction          FINALIZATION — PR #17
G7  Release / Beta / Store Readiness            DEFERRED UNTIL P3 MERGES
```

P1 physical smoke passed on both iOS and Android. P2 merged after package-boundary, Flutter, Rust, GPU, golden, and native packaging gates were green. P3 implementation is complete enough for final review and its latest pre-final-doc implementation HEAD (`cbd70e509018eed1842c162e85b463662e0905f4`) passed full CI in run #202 (`31598466536`). Final documentation commits require one fresh green CI before PR #17 is marked Ready or merged.

## Canonical runtime flow

```text
Camera / imported image
        ↓
clean source
        ↓
Flutter UI + control state
        ↓
GPU interactive preview when faithfully representable
        ↓ gesture release / command
Rust semantic edit / recipe
        ↓
authoritative preview + history + checkpoint
        ↓
full-resolution Rust replay/export
```

## Architecture contracts

1. Rust owns committed edit semantics.
2. GPU preview is never final-render authority.
3. Camera Film is preview-only; capture remains clean.
4. Live camera buffers never cross Dart MethodChannel or Flutter Rust Bridge.
5. Film/Creative LUT data originates from Rust-owned canonical data.
6. Unsupported GPU operation order falls back rather than silently reordering.
7. Native GPU failure fails closed to a valid Rust/product state.
8. Film Profiles are reusable configuration, not per-image sessions or captured pixels.
9. Imported recipe fields report exact, approximated, or unsupported mappings explicitly.
10. New effects are defined and tested in Rust first; GPU support is enabled only when faithful.

## Monorepo layout

```text
PixelCraft/
├── lib/                          # Flutter app shell, UI, platform adapters, compatibility exports
├── rust/                         # authoritative Rust image engine
├── packages/
│   ├── pixelcraft_engine/        # FRB/CargoKit build integration
│   ├── pixelcraft_gpu/           # preview-only Flutter GPU plugin
│   ├── pixelcraft_editing/       # pure-Dart editing/configuration contracts
│   └── pixelcraft_film/          # pure-Dart Film Profile product orchestration
├── android/                      # Android app shell
├── ios/                          # iOS app shell
├── test/
├── tool/
└── docs/
```

Dependency direction:

```text
PixelCraft App
 ├── pixelcraft_film
 ├── pixelcraft_gpu
 ├── pixelcraft_editing
 └── pixelcraft_engine

pixelcraft_film -> pixelcraft_editing
pixelcraft_gpu  -> pixelcraft_editing

pixelcraft_editing -> Dart SDK only
pixelcraft_engine  -> repository rust/ crate through build integration
```

Packages must not depend back on app source. `tool/check_package_boundaries.sh` enforces the package graph in CI.

## Packages

### `pixelcraft_engine`

Flutter FFI/build package for the repository-level Rust engine.

Owns:

- Flutter Rust Bridge integration
- CargoKit build glue
- platform native packaging
- generated `rust_builder` normalization

Does not own editing semantics; those remain in `rust/`.

- [`packages/pixelcraft_engine/README.md`](packages/pixelcraft_engine/README.md)
- [`packages/pixelcraft_engine/CODE_WALKTHROUGH.md`](packages/pixelcraft_engine/CODE_WALKTHROUGH.md)

### `pixelcraft_gpu`

Preview-only Flutter plugin for native GPU preview infrastructure.

Current platform scope:

- **Android:** Camera2/OpenGL ES camera preview path and camera control/runtime registration.
- **iOS:** AVFoundation/Metal camera preview plus the implemented native Editor GPU preview path.

Android does **not** currently provide the Editor GPU channel/view used by `GpuEditorRenderPlan`; Android Editor preview therefore stays on the Rust/product path until an Android Editor implementation is added and parity-verified.

Owns:

- app-independent Dart GPU transport/session infrastructure
- Android Camera2/OpenGL ES camera runtime
- iOS AVFoundation/Metal camera and Editor runtime
- plugin registration
- diagnostics/frame pacing

Does not own committed edit semantics or exported pixels.

- [`packages/pixelcraft_gpu/README.md`](packages/pixelcraft_gpu/README.md)
- [`packages/pixelcraft_gpu/CODE_WALKTHROUGH.md`](packages/pixelcraft_gpu/CODE_WALKTHROUGH.md)

### `pixelcraft_editing`

Pure-Dart editing/configuration contracts shared by the app and infrastructure packages.

Owns reusable non-rendering contracts such as:

- Edit Graph document/node/mask/overlay models
- semantic adjustment catalog, ranges, groups, units, and neutral values
- Film Profile schema/configuration models and import mapping report
- deterministic Film Profile → Editor recipe materialization

It does **not** own GPU capability rollout, Flutter state/UI, or pixel processing. Rust remains authoritative for committed image semantics.

- [`packages/pixelcraft_editing/README.md`](packages/pixelcraft_editing/README.md)
- [`packages/pixelcraft_editing/CODE_WALKTHROUGH.md`](packages/pixelcraft_editing/CODE_WALKTHROUGH.md)

### `pixelcraft_film`

Pure-Dart Film Profile product/domain orchestration introduced in P3.

Current responsibilities include:

- `FilmProfileRepository` persistence contract
- `FilmProfileLibrary` load/save/delete/duplicate/import workflow
- `FilmProfileImportService` for PixelCraft profile JSON vs generic recipe classification
- exact/approximated/unsupported import-report propagation
- `FilmProfileDraft` creator defaults, neutral initialization, clamping/reset, metadata normalization, and deterministic profile composition

Filesystem storage remains app-owned through `FilmProfileStore`; canonical Film LUT data remains Rust-owned.

- [`packages/pixelcraft_film/README.md`](packages/pixelcraft_film/README.md)
- [`packages/pixelcraft_film/CODE_WALKTHROUGH.md`](packages/pixelcraft_film/CODE_WALKTHROUGH.md)

## Editing model

Rust retains the untouched source, reduced Editor preview, recipe/history state, and Apply checkpoint.

Conceptually:

```text
operations = [ ... semantic edits ... ]
cursor
checkpoint_cursor
```

Operations before `checkpoint_cursor` belong to the last Apply checkpoint. Operations after it form the active draft.

Typical interaction:

```text
slider drag
  -> GPU preview only where a verified native Editor path exists and is representable

slider release
  -> Rust semantic commit/replace
  -> authoritative Rust preview
  -> recovery persistence
```

Unsupported or unavailable GPU paths simply keep the valid Rust preview.

## Camera GPU preview

Android eligible path:

```text
Camera2
 -> SurfaceTexture / external OES texture
 -> OpenGL ES Film LUT
 -> Flutter PlatformView
```

iOS eligible path:

```text
AVCaptureVideoDataOutput
 -> CVPixelBuffer
 -> CVMetalTextureCache
 -> Metal Film LUT
 -> Flutter PlatformView
```

Capture returns a clean source image/file path. Live frame buffers stay native.

## Film Profiles

PixelCraft supports versioned reusable Film Profiles with Tone, Color, Texture, Curve, and HSL parameters.

A Film Profile deliberately excludes:

- source image data
- crop/rotate state
- Editor history
- checkpoint state
- captured GPU pixels

Creation/import orchestration may run through `pixelcraft_film`, while profile configuration/mapping semantics remain in `pixelcraft_editing`.

Film creator semantics now use `FilmProfileDraft` for reusable default/clamp/reset/build behavior while Flutter retains widgets, controllers, navigation, and ID generation.

Loading a Film Profile materializes normal Rust recipe operations, so it participates in Apply/Discard, history, recovery, and export.

## Requirements

- Flutter 3.44 or newer
- Dart 3.12 or newer
- Rust stable
- `flutter_rust_bridge_codegen` 2.12.0
- Android Studio / Android SDK
- Xcode + CocoaPods for iOS
- iOS 13.0 or newer

## Setup

```bash
git clone https://github.com/dexter-cnx/PixelCraft.git
cd PixelCraft
./tool/bootstrap.sh
flutter run
```

Or use the Makefile:

```bash
make help
make setup
make run
```

After changing Rust APIs:

```bash
make codegen
```

Useful validation targets:

```bash
make check
make gpu-lut-verify
make verify-native
```

## Native integration notes

### Rust / CargoKit

`pixelcraft_engine` is the Flutter build plugin, but the authoritative crate remains `rust/`.

FRB integration can regenerate a root-level `rust_builder/`. Normalize it back into `packages/pixelcraft_engine` with:

```bash
python3 tool/normalize_rust_builder_layout.py
```

or:

```bash
make integrate
```

### Android

If `libpixelcraft_engine.so` is missing from the APK:

```bash
make repair
make verify-native
```

Manual check:

```bash
unzip -l build/app/outputs/flutter-apk/app-debug.apk | grep libpixelcraft_engine.so
```

### iOS

`pixelcraft_engine` and `pixelcraft_gpu` currently rely on CocoaPods-based native integration. CocoaPods should not be removed until the Rust build/link and Metal plugin packaging paths are fully reproduced by an alternative integration.

See [`docs/IOS_SWIFTPM_MIGRATION.md`](docs/IOS_SWIFTPM_MIGRATION.md).

## Validation gates

CI validates:

```text
package dependency boundaries
FRB generation / committed bridge checks
Rust fmt / clippy / tests
G6 image characterization
GPU LUT parity
pixelcraft_editing analyze / tests
pixelcraft_film analyze / tests
pixelcraft_gpu analyze / tests
Flutter analyze
state tests
GPU plan/session tests
widget/golden tests
Android native packaging smoke
iOS native packaging smoke
wgpu core Linux / macOS / Windows
```

Latest verified P3 implementation run before the final documentation-only commits:

```text
run #202
run id: 31598466536
HEAD: cbd70e509018eed1842c162e85b463662e0905f4
SUCCESS
```

Native architecture changes additionally require physical-device smoke on supported iOS and Android devices before closure. Pure-Dart/docs-only P3 finalization does not automatically require a new device smoke cycle.

## Documentation

- [`docs/PROJECT_HANDOFF.md`](docs/PROJECT_HANDOFF.md) — canonical continuation status and current next action
- [`docs/CODE_WALKTHROUGH.md`](docs/CODE_WALKTHROUGH.md) — current application/runtime/package architecture
- [`packages/pixelcraft_engine/CODE_WALKTHROUGH.md`](packages/pixelcraft_engine/CODE_WALKTHROUGH.md) — FRB/CargoKit/native engine integration
- [`packages/pixelcraft_gpu/CODE_WALKTHROUGH.md`](packages/pixelcraft_gpu/CODE_WALKTHROUGH.md) — GPU control plane and native preview runtime
- [`packages/pixelcraft_editing/CODE_WALKTHROUGH.md`](packages/pixelcraft_editing/CODE_WALKTHROUGH.md) — pure editing/configuration contracts
- [`packages/pixelcraft_film/CODE_WALKTHROUGH.md`](packages/pixelcraft_film/CODE_WALKTHROUGH.md) — Film Profile product/domain orchestration
- [`docs/IOS_SWIFTPM_MIGRATION.md`](docs/IOS_SWIFTPM_MIGRATION.md) — iOS dependency migration constraints

Current continuation is **P3 finalization / PR #17**. After P3 merges, return to G7 release-readiness by rebasing/recreating the preserved pre-refactor work over the post-P3 `main`.

## License

MIT
