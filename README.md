# PixelCraft

**Dextryx Pixels** (`Dxtr Pixs`) is an offline-first camera, photo editor, and image-processing product built with Flutter, Rust, Metal, and OpenGL ES.

PixelCraft uses a platform-adaptive shell:

- **phone + tablet:** camera-first;
- **desktop:** editor/open/drop-first;
- **future Nixin integration:** explicit external-edit request/result contract.

PixelCraft is not the long-lived DAM/library product. **Nixin / Dextryx Images** owns Workplaces, cataloging, organization, browsing, and large-library workflows.

## Mobile and tablet flow

```text
Launch
  ↓
Greeting / permissions when required
  ↓
Camera
  ├── Film
  ├── Filter
  ├── Adjust
  ├── Composition Guide
  ├── Gallery
  ├── Shutter
  └── Controls
```

Camera capture is authoritative and remains camera-first:

```text
clean camera JPEG
+ selected Film / Filter / Adjust
        ↓
Rust full-resolution render
        ↓
JPEG output
        ↓
MediaSaveService
        ↓
system Gallery
        ↓
remain in Camera
```

Live GPU pixels are preview-only and never become final-render authority. Opening Film/Filter does not perform a real still capture. Bounded live thumbnail snapshots are used for preview support instead of streaming camera buffers through MethodChannel or Flutter Rust Bridge.

The complete Rust capture render transaction is serialized because the current Rust image engine is process-global. Concurrent background captures therefore cannot interleave `loadImage`, edit operations, and `exportImage`.

## Camera UX

The mobile/tablet camera shell provides:

- bottom-left Gallery entry;
- bottom-center Shutter;
- bottom-right Controls;
- Film, Filter, and Adjust trays;
- native GPU camera preview on supported Android/iOS paths;
- Flutter `camera` fallback;
- lens switching, flash, torch, mirror, zoom, image ratio;
- Camera Controls sheet with explicit Close button;
- Composition Guide styles: Thirds, Golden Ratio, Golden Spiral;
- procedural Golden Spiral rendering with persistent flip;
- persistent guide-color swatches: White, Black, Red, Yellow, Green, Cyan.

Composition guides are UI overlays only and are never baked into captured/saved pixels.

On Android, native renderer recreation after resume/external activity restores lens direction, flash, torch, mirror, enabled state, and active CameraLook.

## Gallery/editor flow

```text
Gallery
 -> choose source
 -> preserve original source untouched
 -> Editor
 -> Film / Filter / Adjust / transforms / masks
 -> Rust full-resolution render
 -> save processed result to Gallery / explicit destination
```

The source remains immutable input. JPEG stays JPEG source, PNG stays PNG source, WebP stays WebP source, and future RAW input remains RAW source. Export format is a separate output decision.

## Desktop

Desktop launches into an editor/open/drop surface rather than the mobile camera shell:

```text
Open Image / Drag & Drop
        ↓
Editor
        ↓
Film / Filter / Adjust / transforms / masks
        ↓
Export / Save Copy
```

## Architecture

```text
Flutter UI / Riverpod application state
        ↓
GPU low-latency preview where faithful
        ↓ commit / capture / export
Rust semantic edit engine
        ↓
recipe / history / checkpoint / recovery
        ↓
full-resolution replay / export
```

Hard contracts:

1. Rust is authoritative for committed edit semantics and full-resolution render/export.
2. GPU is preview-only.
3. Clean camera capture remains the authoritative source.
4. Live camera frame buffers never cross Dart MethodChannel or Flutter Rust Bridge as a continuous stream.
5. Film/Creative canonical LUT data remains Rust-owned.
6. Unsupported GPU operation ordering falls back instead of silently changing semantics.
7. Riverpod orchestrates UI/transient state and does not become a second canonical recipe engine.
8. PixelCraft editor-local metadata never becomes a general DAM catalog.

## Current milestone status

```text
G1-G6                                      CLOSED / VERIFIED
P0-P3 package extraction                   MERGED
PKG-01 dxtr_pixs_* namespace consolidation COMPLETE
G7A Release Engineering                    MERGED
G7B Store Account Integration              DEFERRED INDEFINITELY

PF0 Platform-flow foundations              ROUTING FOUNDATION MERGED (#50)
PF1 Camera-first mobile/tablet shell        IMPLEMENTED
PF2 Unified Camera Film/Filter/Adjust UX    IMPLEMENTED
PF3 Capture-process-save-to-Gallery         MERGED (#52)
PF4 Gallery-to-editor source flow           MERGED (#55)
PF5 External edit request/result contract   MERGED (#56)

MobileSAM / ONNX                            FUTURE / NOT ACTIVATED
Real RAW development                        FUTURE / NOT ACTIVATED
Dart 3.13 RecordUse/native tree-shaking     FUTURE / DEFERRED
```

PF3 physical validation passed on Android and iPhone. PF4 and PF5 are merged; PF5 final exact head `69e317b4cb153f09c3a926d6aab6964ca9fd410d` passed Pixel Craft CI #781 before merge commit `8df08f090c6d2e001526004ef15c9ae652b6a471`.

## State management and localization

PixelCraft uses **Riverpod** for Flutter application/UI orchestration and **easy_localization** for user-facing localization.

Initial locales:

```text
en
th
```

Canonical edit operations, history, checkpoints, and export semantics remain Rust-owned.

## Package graph

```text
PixelCraft app
 ├── dxtr_pixs_film
 ├── dxtr_pixs_gpu
 ├── dxtr_pixs_editing
 └── dxtr_pixs_engine

dxtr_pixs_film    -> dxtr_pixs_editing
dxtr_pixs_gpu     -> dxtr_pixs_editing
dxtr_pixs_editing -> Dart SDK only
dxtr_pixs_engine  -> repository rust/ crate
```

## Product identity

```text
master brand: Dextryx
product: Dextryx Pixels
installed label: Dxtr Pixs
repository: PixelCraft
Android applicationId: dev.cnxdev.pixelcraft
iOS bundle id: dev.cnxdev.pixelcraft
```

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

Install repository hooks once per clone:

```bash
make hooks-install
```

## CI and local validation

Recommended local entrypoint:

```bash
make preflight
```

Focused commands:

```bash
make format
make format-check
make pre-push
make analyze
make test-fast
make gpu-check
make ci-fast
```

`dart-format-check` is read-only. When formatting differs, diagnostics are generated from temporary copies so local staged/unstaged/untracked work is not rewritten merely to print the canonical diff.

Branch protection should require stable always-present contexts such as `Fast CI` and `CI Gate`; conditional platform jobs should not be required individually.

## Documentation

- `docs/PROJECT_HANDOFF.md` — canonical continuation status and execution order
- `docs/CODE_WALKTHROUGH.md` — runtime and architecture walkthrough
- `docs/CI_ARCHITECTURE.md` — CI DAG and validation policy
- `docs/LOCAL_DEVELOPMENT.md` — local formatting/pre-push workflow
- `docs/FUTURE_DART_3_13_NATIVE_TREE_SHAKING.md` — deferred Dart 3.13 plan

## License

MIT
