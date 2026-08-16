# PixelCraft Code Walkthrough

Repository: **PixelCraft**  
Product: **Dextryx Pixels**

## 1. Product scope

PixelCraft is the **camera + photo editor + image-processing product**.

It owns:

- phone/tablet camera UX;
- editor UX and session lifecycle;
- Rust-authoritative recipe/history/checkpoint semantics;
- Film, Creative Filter, Adjust, transforms, and masks;
- realtime GPU preview where faithful;
- full-resolution render/export;
- editor recovery and source reopening continuity.

**Nixin / Dextryx Images** is the separate image-management product. It owns Workplaces, asset identity, import/catalog organization, browsing, collections, and large-library UX.

PixelCraft must not evolve into a second DAM by default.

---

## 2. Platform shell policy

### Phone and tablet

Phone and tablet are **camera-first**.

After Rust/bootstrap readiness, the target root is the camera surface rather than `HomeScreen`.

```text
launch
  ↓
Camera
  ├── Film / Filter / Adjust
  └── Gallery / Shutter / Controls
```

Tablet may use more space in landscape, but it keeps the same mental model and actions as phone.

### Desktop

Desktop is **editor/open/drop-first**.

```text
launch
  ↓
Open / Drop surface
  ↓
Product Editor
```

Primary desktop inputs:

- Open Image;
- Drag & Drop.

Secondary/future inputs may include Open Recent, Paste Image, Capture from Camera, Open With, and future Nixin external-edit requests.

Desktop does not reuse the camera-first launch shell merely for UI uniformity.

---

## 3. Current implementation vs target

Current `lib/main.dart` still boots Rust and then returns `HomeScreen`.

Current camera implementation is exposed through:

```text
lib/ui/screens/camera_film_preview_screen.dart
 -> camera_film_preview_screen_g1.dart
```

The existing camera foundation already contains:

- iOS native GPU camera preview;
- Android native GPU camera preview;
- Flutter `camera` fallback;
- camera permission/lifecycle handling;
- camera switching;
- Film realtime preview + strength;
- clean capture;
- capture -> editor handoff.

PF1 should reuse this stack and change the product shell around it rather than creating another camera implementation.

---

## 4. Target mobile/tablet camera hierarchy

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

Bottom hierarchy:

- **left:** Gallery/recent-source entry;
- **center:** Shutter, primary action;
- **right:** camera controls/settings surface.

`Film`, `Filter`, and `Adjust` should be camera-context tools rather than separate top-level destinations.

Camera controls may include lens switch, flash, exposure compensation, grid, aspect/capture options, and secondary settings as platform capability allows.

---

## 5. Camera processing semantics

Live Camera preview is transient.

```text
Camera frames
  ↓
GPU preview state
  ↓
Film / Filter / Adjust appearance
```

The live framebuffer is never final output authority.

Target shutter flow:

```text
clean camera capture
+ selected look configuration
        ↓
Rust authoritative processing
        ↓
JPEG
        ↓
MediaSaveService
        ↓
system Gallery
        ↓
remain in Camera
```

The user is not forced into the editor after every shutter press.

After save, a recent thumbnail/confirmation can update. Tapping that thumbnail may open the editor for additional work.

---

## 6. Gallery/editor source flow

Target Gallery flow:

```text
Gallery picker
  ↓
source descriptor
  ↓
Product Editor
  ↓
Rust session
  ↓
Film / Filter / Adjust / transforms / masks
  ↓
full-resolution render
  ↓
MediaSaveService
  ↓
system Gallery / explicit export destination
```

The source is treated as immutable input.

Do not rewrite the source merely because PixelCraft processes it.

Examples:

```text
JPEG source -> remains JPEG source
PNG source  -> remains PNG source
WebP source -> remains WebP source
future RAW  -> remains RAW source
```

Output format is separate from source preservation.

---

## 7. Flutter state management

PixelCraft standardizes on **Riverpod** for application/UI orchestration.

`ProviderScope` already exists at the app root; do not introduce Bloc/GetX or another competing global state framework without a concrete architectural need.

Recommended state boundaries:

```text
AppPreferencesState
CameraState
LiveLookState
EditorUiState
ProcessingJobState
ExternalEditState    # future
```

### Riverpod may own

- camera initialization/permission UI state;
- active lens/flash/grid UI preferences;
- selected Film/Filter/Adjust mode;
- transient live-preview values;
- loading/progress/error presentation;
- selected editor tool;
- export/save job state;
- future external-edit orchestration state.

### Riverpod must not own as authority

```text
canonical edit recipe
operation ordering semantics
undo/redo history authority
checkpoint authority
full-resolution export semantics
```

Those remain Rust-owned.

Conceptually:

```text
Flutter widgets
      ↓
Riverpod UI/application state
      ↓ commands
GPU transient preview / Rust engine
      ↓
Rust authoritative recipe/history
```

---

## 8. LiveLookState vs committed edit state

Camera interaction needs a deliberate split:

```text
LiveLookState
  Film
  Film strength
  Filter
  Filter strength
  temporary Adjust values
```

These values drive low-latency preview and capture configuration.

They are not automatically equivalent to a committed editor history.

On capture/export, the selected configuration is converted into the existing Rust-authoritative processing path.

This prevents Flutter state from becoming a parallel image engine.

---

## 9. Localization

PixelCraft should use **easy_localization** for all new user-facing Flutter UI.

Initial locales:

```text
en
th
```

Locale policy:

```text
device th_* -> th
device en_* -> en
anything else -> en
fallback -> en
```

Initial asset layout:

```text
assets/translations/en.json
assets/translations/th.json
```

Strings such as Gallery, Film, Filter, Adjust, Processing, Saving, Camera permission errors, source errors, export errors, and settings labels should be translation keys rather than hardcoded UI strings.

If a future in-app language override is added, it belongs to `AppPreferencesState`; system locale remains the default behavior.

---

## 10. Preferences persistence

Do **not** add Hive merely to have a database available.

Introduce an abstraction such as:

```text
AppPreferencesStore
```

It may persist lightweight user preferences:

```text
lastLens
gridEnabled
flash preference
camera UI preferences
lastFilmId
lastFilmStrength
lastFilterId
lastFilterStrength
theme
optional locale override
last editor UI tool
```

The backend should remain replaceable and lightweight.

Preferences are never image recipe authority.

Existing persistence responsibilities stay separate:

```text
EditorSessionStore
 = latest coherent editing-session recovery

WorkspaceCatalogStore
 = bounded editor-local source/reopen metadata

AppPreferencesStore
 = user/UI preferences

Rust recipe
 = authoritative edit semantics
```

---

## 11. App/service boundaries

The camera-first/platform-adaptive work should stop screens from directly owning every platform concern.

Target service boundaries:

```text
AppPreferencesStore
MediaPickerService
MediaSaveService
PermissionService
CapabilityRegistry
ProcessingJob coordinator/state
AppRouter / route abstraction
```

### MediaPickerService

Responsible for platform source selection and returning a source descriptor without inventing edit semantics.

### MediaSaveService

Common output path for:

- camera JPEG results;
- editor exports to Gallery;
- future save-copy/export destination handling.

### PermissionService

Centralize permission state and mapping for:

- Camera;
- Gallery/photo access where required;
- save/write behavior where platform rules require permission;
- opening system Settings after denied/restricted states.

### CapabilityRegistry

Expose runtime/platform capability such as:

- native camera GPU preview available;
- Film realtime preview supported;
- Creative Filter realtime preview supported;
- specific Adjust preview support;
- source-format support;
- future segmentation/RAW support.

UI should not guess capability from platform names alone.

---

## 12. Processing job model

Longer work needs explicit state rather than ad-hoc booleans scattered through screens.

Suggested state:

```text
idle
processing
saving
completed
failed
```

Where applicable, use existing latest-request-wins/coalescing semantics for interactive preview work.

Shutter/export actions should be protected against duplicate submission while the relevant operation is active.

Typed failures should cover at least:

```text
cameraUnavailable
permissionDenied
permissionRestricted
decodeFailed
unsupportedSource
renderFailed
saveFailed
```

Map technical failures to localized UI messages at the presentation boundary.

---

## 13. Navigation boundary

Current code uses direct `Navigator.push` in several places. The platform-flow milestone should introduce a lightweight route/navigation abstraction before navigation complexity grows further.

Target flows:

```text
Mobile/tablet
Launch -> Camera -> Gallery Picker -> Editor -> Export -> Camera

Desktop
Launch -> Open/Drop -> Editor -> Export

Future external edit
Nixin request -> Editor -> PixelCraftEditResult -> caller
```

The router should model intent, not encode Nixin-specific business logic into PixelCraft screens.

---

## 14. Source descriptor and future external edit

Use a format-aware source contract rather than assuming all inputs are JPEG/PNG.

A future external-edit request may contain:

```text
version
sourceUri / sourcePath
sourceId?           # caller-owned external identity
sourceMimeType
requestedMode
returnPolicy
metadata?
```

The future result may contain:

```text
version
outputUri / outputPath
outputMimeType
sourceId?
recipeReference?    # only if explicitly designed
metadata?
```

Nixin remains authoritative for its asset identity and Workplaces. PixelCraft remains authoritative for its edit session and processing semantics.

Do not bind the protocol to `HomeScreen`, `ProductEditorScreen`, or internal Flutter widget classes.

---

## 15. Editor-local catalog and recovery

Current implementation:

```text
lib/core/editor_session_store.dart
lib/core/workspace_catalog_store.dart
```

`WorkspaceCatalogStore` is retained only for bounded continuity/reopen behavior.

It is not a product library database.

Do not extend it by default into:

```text
Workplaces
folder ingestion
bulk organization
ratings / flags / keywords
large catalog browser
archive management
Lightroom-style DAM
```

Those belong to Nixin / Dextryx Images.

---

## 16. Rust authority / engine

```text
Flutter app
   ↓
dxtr_pixs_engine
   ↓ FRB / CargoKit
rust/
```

Rust owns:

- untouched source;
- reduced preview;
- semantic operations;
- undo/redo cursor;
- checkpoint cursor;
- recovery recipe;
- full-resolution replay/export.

Useful commands:

```bash
make codegen
make integrate
make repair
make verify-native
```

---

## 17. GPU preview

Package:

```text
packages/dxtr_pixs_gpu/
```

Mobile policy:

```text
Android -> Camera2/OpenGL ES camera preview
iOS     -> AVFoundation/Metal camera preview + Metal editor preview
```

Do not casually replace this runtime with wgpu.

Unsupported/missing native GPU capability must fall back to a valid Rust/product path rather than changing semantics.

---

## 18. Film and Creative Filter

Film Profiles are first-class Rust operations and use canonical 33x33x33 LUT data.

Current inspired Film pack includes:

- Provia;
- Velvia;
- Astia;
- E100;
- Ektar;
- Chrome 64.

Creative Filter foundation includes grayscale/invert and canonical LUT-backed presets such as:

- vintage;
- oceanic;
- lofi;
- dramatic;
- golden;
- pastel pink.

Camera PF2 should integrate these capabilities into one camera tool surface rather than duplicate their processing semantics.

---

## 19. Future MobileSAM / ONNX

Future package direction:

```text
dxtr_pixs_segment
```

When activated, segmentation should sit behind a replaceable mask-provider boundary.

Conceptually:

```text
source / reduced analysis image
  ↓
MaskProvider
  ↓
local MobileSAM/ONNX implementation
  ↓
mask result
  ↓
PixelCraft edit semantics
```

Segmentation generates masks; it is not image-processing authority.

Do not activate this as part of PF1-PF5.

---

## 20. Future real RAW

Future package direction:

```text
dxtr_pixs_raw
```

A real RAW milestone must explicitly define:

- decoding/demosaic;
- Bayer/X-Trans handling where supported;
- black/white level normalization;
- camera WB/color matrices;
- highlight recovery;
- working color-space conversion;
- memory/performance policy;
- authoritative full-resolution replay/export.

Source contracts created during PF work must remain RAW-aware so the future implementation does not require redesigning application input identity.

Do not activate RAW development as part of PF1-PF5.

---

## 21. Package graph

```text
PixelCraft App
 ├── dxtr_pixs_film
 ├── dxtr_pixs_gpu
 ├── dxtr_pixs_editing
 └── dxtr_pixs_engine

dxtr_pixs_film    -> dxtr_pixs_editing
dxtr_pixs_gpu     -> dxtr_pixs_editing
dxtr_pixs_editing -> Dart SDK only
dxtr_pixs_engine  -> repository rust/ crate
```

Future package family:

```text
dxtr_pixs_segment
dxtr_pixs_restore
dxtr_pixs_raw
```

Native ABI/library/channel/persisted schema identifiers remain stable unless separately approved.

---

## 22. Current milestone sequence

```text
PF1 Camera-first mobile/tablet shell
 -> PF2 Unified Camera Film/Filter/Adjust UX
 -> PF3 Capture + Rust render + JPEG Gallery save + stay in camera
 -> PF4 Gallery source -> editor -> Gallery export
 -> PF5 Versioned external-edit request/result foundation
```

Cross-cutting PF foundations:

```text
easy_localization: en + th, device detect, fallback en
Riverpod as Flutter state-management standard
AppPreferencesStore abstraction
MediaPickerService
MediaSaveService
PermissionService
CapabilityRegistry
ProcessingJob state/error model
adaptive route/navigation boundary
format-aware source descriptor
future-safe Nixin/RAW/MobileSAM interfaces
```

Not part of PF1-PF5 unless separately activated:

```text
Hive migration
second state-management framework
Workplaces/DAM expansion
MobileSAM implementation
real RAW implementation
Dart 3.13 RecordUse work
G7B store account work
```

---

## 23. Verification gates

```bash
bash tool/check_package_boundaries.sh
make gpu-lut-verify
make verify-native
flutter analyze
flutter test
```

New PF implementation should add targeted tests for:

- platform-adaptive root routing;
- phone/tablet camera launch;
- desktop open/drop launch;
- locale selection/fallback;
- preferences boundaries;
- processing-job duplicate-action prevention;
- source preservation;
- camera capture -> JPEG save -> remain in camera;
- Gallery -> editor -> export flow;
- external-edit model serialization/versioning when PF5 begins.

A PR head being green is not enough to close a slice; verify resulting `main` push CI.

---

## 24. Current continuation point

The next implementation milestone is **PF1 — Camera-first mobile/tablet shell**.

Start by establishing the platform root, localization/state/preferences/service foundations, then move the existing verified camera implementation into the primary phone/tablet experience without creating a second camera or processing authority.

See `docs/PROJECT_HANDOFF.md` for the canonical execution order and historical evidence.
