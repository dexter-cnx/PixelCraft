# PixelCraft

**Dextryx Pixels** (`Dxtr Pixs`) is an offline-first camera, photo editor, and image-processing product built with Flutter, Rust, Metal, and OpenGL ES.

PixelCraft uses a platform-adaptive product shell:

- **phone + tablet:** camera-first;
- **desktop:** editor/open/drop-first;
- **future Nixin integration:** explicit external-edit request/result contract.

PixelCraft is not the long-lived DAM/library product. **Nixin / Dextryx Images** owns Workplaces, cataloging, organization, browsing, and large-library workflows.

## Product flow

### Phone and tablet

Launch directly into Camera:

```text
┌─────────────────────────────┐
│                             │
│       live preview          │
│                             │
│   Film  Filter  Adjust      │
│                             │
├─────────────────────────────┤
│ Gallery   SHUTTER   Controls│
└─────────────────────────────┘
```

Target behavior:

```text
Shutter
 -> clean camera capture
 -> apply selected Film / Filter / Adjust through Rust-authoritative processing
 -> JPEG output
 -> save to system Gallery
 -> remain in Camera
```

Live GPU pixels are preview-only and never become final-render authority.

Gallery flow:

```text
Gallery
 -> choose source
 -> keep original source untouched
 -> Editor
 -> Film / Filter / Adjust / transforms / future masks
 -> Rust full-resolution render
 -> save processed result to Gallery
```

The original source format is preserved as source data. JPEG stays JPEG source, PNG stays PNG source, WebP stays WebP source, and a future RAW input remains RAW source. Export is a separate output decision.

### Desktop

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

Secondary/future inputs may include Open Recent, Paste Image, Capture from Camera, Open With, and external-edit requests.

The desktop editor should use collapsible multi-pane controls while remaining an editor, not a DAM/library clone.

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

1. **Rust is authoritative** for committed edit semantics, recipe/history/checkpoint/recovery, and full-resolution render/export.
2. **GPU is preview-only** and never final-render authority.
3. Camera Film/Filter/Adjust preview never replaces the clean capture source.
4. Live camera frame buffers never cross Dart MethodChannel or Flutter Rust Bridge.
5. Film/Creative canonical LUT data remains Rust-owned.
6. Unsupported GPU operation ordering falls back instead of silently changing semantics.
7. Flutter/Riverpod state orchestrates UI and transient preview state; it must not become a second canonical edit recipe.
8. PixelCraft editor-local source/recovery metadata never becomes a general DAM catalog.

## State management

PixelCraft standardizes on **Riverpod** for Flutter application/UI orchestration.

Recommended state boundaries:

```text
AppPreferencesState
CameraState
LiveLookState
EditorUiState
ProcessingJobState
ExternalEditState   # future contract orchestration
```

Riverpod may represent loading, selected tools, camera state, transient Film/Filter/Adjust preview values, progress, errors, and export state.

Canonical edit operations, history, checkpoints, and export semantics remain Rust-owned.

Do not add Bloc/GetX or another competing global state framework without an explicit architectural reason.

## Localization

PixelCraft uses **easy_localization** as the UI localization foundation.

Initial supported locales:

```text
en
th
```

Policy:

- detect the device locale by default;
- `th_*` selects Thai;
- `en_*` selects English;
- unsupported locales fall back to **English**;
- new user-facing Flutter strings should enter localization resources rather than being hardcoded.

Initial translation layout may use:

```text
assets/translations/en.json
assets/translations/th.json
```

## Preferences and persistence

Do **not** add Hive merely as a future-proofing dependency.

Use an `AppPreferencesStore` abstraction for lightweight preferences such as:

```text
last camera lens
grid / flash / camera UI preferences
last Film + strength
last Filter + strength
theme / optional locale override
last UI tool preferences
```

The persistence backend can remain lightweight and replaceable. It must not own image recipes or processing semantics.

Existing persistence remains separated by responsibility:

- `EditorSessionStore` — coherent editor recovery;
- `WorkspaceCatalogStore` — bounded editor-local source/reopen metadata only;
- filesystem/system Gallery — image files;
- Rust recipe — authoritative editing semantics.

## Application services for the platform-flow milestone

The next product-flow work should converge on explicit service boundaries rather than screen-specific platform calls:

```text
AppPreferencesStore
MediaPickerService
MediaSaveService
PermissionService
CapabilityRegistry
ProcessingJob orchestration
App route/navigation abstraction
```

`MediaSaveService` should be the common path for camera JPEG results and editor exports to system Gallery.

Error handling should map typed failures such as permission denied, camera unavailable, decode failure, unsupported source, render failure, and save failure into localized UI messages.

## Future-safe source contract

Source handling should remain format-aware and should not assume every input is JPEG/PNG.

A future external-edit request may carry fields such as:

```text
version
sourceUri / sourcePath
sourceId?          # external identity owned by caller
sourceMimeType
requestedMode
returnPolicy
metadata?
```

A corresponding `PixelCraftEditResult` should return the edited output without transferring Nixin Workplaces/catalog authority into PixelCraft.

This contract is a **planned foundation only**; full Nixin integration is not part of the current implementation slice.

## Current capability status

```text
G1  Camera GPU Preview                         CLOSED
G2  Editor GPU Preview Foundation              CLOSED / MERGED
G3  Production Rendering Pipeline              CLOSED / MERGED
G4  Product Editor UX / Session Workflow       CLOSED / MERGED
G5  Editing Feature Completeness               CLOSED / VERIFIED
G6  Reliability / Performance / Device Matrix  CLOSED / VERIFIED

P0-P3 package extraction                       MERGED
PKG-01 dxtr_pixs_* namespace consolidation     COMPLETE
G7A Release Engineering / Store Preparation    MERGED
G7B Store Account Integration / Beta Upload    DEFERRED INDEFINITELY

PF1 Camera-first mobile/tablet shell            NEXT / NOT IMPLEMENTED
PF2 Unified Camera Film/Filter/Adjust UX        PLANNED
PF3 Capture-process-save-to-Gallery             PLANNED
PF4 Gallery-to-editor source flow               PLANNED
PF5 External edit request/result contract       PLANNED FOUNDATION ONLY

MobileSAM / ONNX                               FUTURE / NOT ACTIVATED
Real RAW development                           FUTURE / NOT ACTIVATED
Dart 3.13 RecordUse/native tree-shaking        FUTURE / DEFERRED
```

## Film and Filter foundation

Film Profiles and Creative Filters are already real Rust-backed capabilities rather than fake UI controls.

Film uses first-class operations and canonical 33x33x33 LUT data with full-resolution replay/export. Current inspired looks include Provia, Velvia, Astia, E100, Ektar, and Chrome 64.

Creative filters include grayscale/invert and canonical LUT-backed presets such as vintage, oceanic, lofi, dramatic, golden, and pastel pink.

PF2 is therefore primarily camera UX integration over existing processing foundations.

## Future MobileSAM and RAW

Future package direction:

```text
dxtr_pixs_segment  # MobileSAM/local segmentation
dxtr_pixs_restore  # restoration capabilities
dxtr_pixs_raw      # real RAW development
```

These are not activated by the camera-first milestone.

A future MobileSAM/ONNX path should produce masks through a replaceable mask-provider boundary and must not become image-processing authority.

A future real RAW milestone must separately define decode/demosaic, camera color/WB, highlight recovery, working color space, memory/performance, full-resolution replay, and export behavior.

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
dxtr_pixs_engine  -> repository rust/ crate through build integration
```

Native ABI/runtime identifiers remain stable unless separately approved.

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

Validation:

```bash
bash tool/check_package_boundaries.sh
make gpu-lut-verify
make verify-native
flutter analyze
flutter test
```

A green PR head alone does not close a milestone; resulting `main` CI must also be verified.

## Documentation

- `docs/PROJECT_HANDOFF.md` — canonical continuation status and execution order
- `docs/CODE_WALKTHROUGH.md` — runtime, state, localization, service, and package architecture
- `docs/FILM_PROFILES_AND_RELIABILITY.md` — Film profile/reliability details
- `docs/FUTURE_DART_3_13_NATIVE_TREE_SHAKING.md` — deferred Dart 3.13 plan
- release/device evidence documents under `docs/`

## License

MIT
