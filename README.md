# PixelCraft

PixelCraft is an offline-first mobile photo editor and film-simulation camera built with Flutter, Rust, Metal, and OpenGL ES.

The architecture separates semantic authority from interactive rendering:

- **Rust is authoritative** for committed editing semantics, recipes, history, checkpoints, recovery, and full-resolution export.
- **Native GPU is preview-only** for low-latency camera/editor interaction where the requested operation graph can be reproduced faithfully.

Normal PixelCraft editing/export flows do not require user images to leave the device.

## Current status

As of 2026-08-12:

```text
G1  Camera GPU Preview                          CLOSED
G2  Editor GPU Preview Foundation               CLOSED / MERGED
G3  Production Rendering Pipeline               CLOSED / MERGED
G4  Product Editor UX / Session Workflow        CLOSED / MERGED
G5  Editing Feature Completeness                CLOSED / VERIFIED
G6  Reliability / Performance / Device Matrix   CLOSED / VERIFIED

P0  pixelcraft_engine package extraction        MERGED
P1  pixelcraft_gpu package extraction           MERGED
P2  pixelcraft_editing package extraction       MERGED
P3  pixelcraft_film package extraction          MERGED

G7A Release Engineering / Store Preparation     MERGED — PR #18
G7B Store Account Integration / Beta Upload     BLOCKED BY EXTERNAL ACCOUNTS
```

G7A merged into `main` as:

```text
507875b2e1187e2bc2f0a6d0535b77dc0455b69f
```

The final G7A PR head passed full CI in run #221 (`31611799174`). That run included package-boundary checks, Rust tests, editing/film/GPU package analyze/tests, Flutter analyze/tests, golden/native packaging, Android release packaging, iOS release no-codesign packaging, and wgpu Linux/macOS/Windows.

Old PR #10 was audited after G7A merge and is now **CLOSED / SUPERSEDED**. Its implementation was recreated and expanded by PR #18; it must not be merged as an alternate G7 line.

G7B remains blocked until Apple Developer/App Store Connect and Google Play Console accounts are available.

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
├── lib/                          # Flutter app shell, UI, state, platform adapters
├── rust/                         # authoritative Rust image engine
├── packages/
│   ├── pixelcraft_engine/        # FRB/CargoKit build integration
│   ├── pixelcraft_gpu/           # preview-only Flutter GPU plugin
│   ├── pixelcraft_editing/       # pure-Dart editing/configuration contracts
│   └── pixelcraft_film/          # pure-Dart Film Profile orchestration
├── android/
├── ios/
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

Packages must not depend back on root app source. `tool/check_package_boundaries.sh` enforces the package graph in CI.

## Packages

### `pixelcraft_engine`

Flutter FFI/build-integration package around the root Rust engine. It owns Flutter Rust Bridge integration, CargoKit build glue, platform native packaging, and generated builder normalization. Editing semantics remain authoritative in `rust/`.

### `pixelcraft_gpu`

Preview-only Flutter plugin for native GPU infrastructure.

- Android: Camera2/OpenGL ES camera preview.
- iOS: AVFoundation/Metal camera preview and native Editor GPU preview.
- Android Editor preview currently stays on the valid Rust/product path; there is no Android native Editor GPU channel/view yet.

### `pixelcraft_editing`

Pure-Dart reusable editing/configuration contracts:

- Edit Graph schema/models
- adjustment catalog/ranges/neutrals
- Film Profile schema/configuration/import mapping
- deterministic Film Profile → Editor recipe materialization

It does not own Flutter UI, GPU rollout policy, persistence, or pixel processing.

### `pixelcraft_film`

Pure-Dart Film Profile product/domain orchestration:

- `FilmProfileRepository`
- `FilmProfileLibrary`
- `FilmProfileImportService`
- exact/approximated/unsupported import-report propagation
- `FilmProfileDraft` creator defaults/clamping/reset/metadata normalization/composition

Filesystem storage remains app-owned through `FilmProfileStore`; canonical Film LUT data remains Rust-owned.

## Editing model

Rust retains the untouched source, reduced Editor preview, recipe/history state, and Apply checkpoint.

```text
operations = [ ... semantic edits ... ]
cursor
checkpoint_cursor
```

Typical interaction:

```text
slider drag
  -> GPU preview where a verified native Editor path exists

slider release
  -> Rust semantic commit/replace
  -> authoritative Rust preview
  -> recovery persistence
```

Unsupported/unavailable GPU paths keep the valid Rust preview.

## Camera GPU preview

Android:

```text
Camera2
 -> SurfaceTexture / external OES texture
 -> OpenGL ES Film LUT
 -> Flutter PlatformView
```

iOS:

```text
AVCaptureVideoDataOutput
 -> CVPixelBuffer
 -> CVMetalTextureCache
 -> Metal Film LUT
 -> Flutter PlatformView
```

Capture returns a clean source image/file path. Live frame buffers stay native.

## Film Profiles

Film Profiles are versioned reusable Tone/Color/Texture/Curve/HSL configuration. They exclude source-image bytes, crop/rotate session state, Editor history/checkpoints, and captured GPU pixels.

Creation/import orchestration is handled by `pixelcraft_film`; configuration/mapping semantics remain in `pixelcraft_editing`; applying a profile materializes a normal Rust-backed recipe path.

## G7A release engineering

Current release identity:

```text
app display name: Pixel Craft
version: 0.1.0+1
Android applicationId: dev.cnxdev.pixelcraft
Android min/target/compile SDK: 24 / 36 / 36
iOS bundle identifier: dev.cnxdev.pixelcraft
iOS deployment target: 13.0
```

Release CI produces:

```text
Android release APK
  - no debug signing
  - Rust native library packaged for arm64-v8a / armeabi-v7a / x86_64
  - generated Film/Creative LUT assets packaged

iOS release --no-codesign Runner.app
  - pixelcraft_engine.framework present
  - Film/Creative LUT assets present
```

Android microphone permission is explicitly removed because the still-camera fallback uses `enableAudio: false`.

Privacy/recovery audit verifies:

- recovery state is local private app-support data;
- at most three coherent recovery generations are retained;
- abandoned recovery `.tmp` files are cleaned during load/save;
- Discard removes recovery data;
- export/share is user initiated;
- the current dependency set contains no analytics, advertising, or remote crash-reporting SDK.

See `docs/G7A_RELEASE_READINESS.md` and `docs/G7A_PRIVACY_STORE_DRAFTS.md`.

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

Or:

```bash
make setup
make run
```

After changing Rust APIs:

```bash
make codegen
```

Useful validation:

```bash
make check
make gpu-lut-verify
make verify-native
```

## Native integration notes

`pixelcraft_engine` is the Flutter build plugin, while the authoritative crate remains `rust/`. FRB can regenerate a root `rust_builder/`; normalize it back into the package with:

```bash
python3 tool/normalize_rust_builder_layout.py
# or
make integrate
```

On Android, if `libpixelcraft_engine.so` is missing:

```bash
make repair
make verify-native
```

On iOS, `pixelcraft_engine` and `pixelcraft_gpu` currently rely on CocoaPods-based native integration. See `docs/IOS_SWIFTPM_MIGRATION.md`.

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
Android release artifact
iOS release --no-codesign artifact
```

Latest fully verified G7A run:

```text
run #221
run id: 31611799174
HEAD: d5e0aab14a0ae9a5b8124a0b37fef78249cbbeb5
SUCCESS
```

Unsigned/no-codesign artifacts are packaging evidence only. Signed RC physical-device smoke and actual TestFlight/Play validation belong to G7B.

## Documentation

- `docs/PROJECT_HANDOFF.md` — canonical continuation status and next action
- `docs/CODE_WALKTHROUGH.md` — application/runtime/package/release architecture
- `docs/G7A_RELEASE_READINESS.md` — G7A evidence/checklist
- `docs/G7A_ANDROID_SIGNING.md` — Android signing setup
- `docs/G7A_PRIVACY_STORE_DRAFTS.md` — offline privacy/Data Safety/App Privacy drafts
- package `README.md` / `CODE_WALKTHROUGH.md` files — package-specific contracts
- `docs/IOS_SWIFTPM_MIGRATION.md` — iOS dependency migration constraints

Current continuation is **post-G7A**. PR #10 is closed/superseded. G7B remains blocked until Apple/Google store accounts are available; account-independent maintenance or product work can continue from `docs/PROJECT_HANDOFF.md`.

## License

MIT
