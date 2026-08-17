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

PF2 provides a unified Camera look state containing independent Film, Creative Filter, and realtime Adjust layers. The native preview executes the frozen semantic order:

```text
Adjust -> Film -> Creative Filter
```

Android uses OpenGL ES and iOS uses Metal for preview. Rust remains authoritative for final image semantics and saved pixels.

Target PF3 shutter behavior remains:

```text
Shutter
 -> clean camera capture
 -> apply selected Film / Filter / Adjust through Rust-authoritative processing
 -> JPEG output
 -> save to system Gallery
 -> remain in Camera
```

Until PF3 lands, PF2 temporarily hands the clean capture and the selected `CameraLookState` to the existing Rust-backed editor path.

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

Gallery-picked sources remain neutral and do not automatically inherit the current Camera look.

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
9. PF2 does not pre-compose the complete look into one 33³ LUT; Film and Creative LUT stages remain sequential with direct Adjust/exact Creative operations.

## PF2 current status

```text
PR: #48
branch: feature/pf2-unified-camera-look
implementation baseline: b4451dce62bd877435cdab4ddd69c3f69cc037cd
CI: #420 / run 31946914217 — SUCCESS
implementation: COMPLETE
physical-device validation: PENDING
PR state: OPEN / DRAFT
```

Automated gates on the implementation baseline are green. PF2 is intentionally not marked complete/ready because the direct per-frame native shader stages still require physical-device validation for frame pacing and runtime behavior.

Canonical PF2 docs:

```text
docs/PF2_CAMERA_LOOK_CONTRACT.md
docs/PF2_DEVICE_VALIDATION_CHECKLIST.md
```

The physical-device gate covers:

- neutral preview baseline;
- Film selection and strength;
- every Creative Filter class;
- brightness/contrast/saturation continuous sliders;
- Film + Filter + Adjust coexistence;
- rapid-switch/latest-value-wins stress;
- sustained preview/frame pacing and thermal observation;
- lens switching and lifecycle pause/resume;
- shutter + temporary capture/editor handoff;
- Gallery source neutrality;
- runtime fail-closed fallback where safely inducible;
- EN/TH controls;
- regression smoke.

PR #48 should remain Draft until the required device checklist passes and evidence is recorded.

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

## Application services

Platform-flow work converges on explicit service boundaries rather than screen-specific platform calls:

```text
AppPreferencesStore
MediaPickerService
MediaSaveService
PermissionService
CapabilityRegistry
ProcessingJob orchestration
App route/navigation abstraction
```

`MediaSaveService` is the target common path for PF3 camera JPEG results and editor exports to system Gallery.

Error handling maps typed failures such as permission denied, camera unavailable, decode failure, unsupported source, render failure, and save failure into localized UI messages.

## Future-safe source contract

Source handling remains format-aware and does not assume every input is JPEG/PNG.

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

A corresponding `PixelCraftEditResult` returns the edited output without transferring Nixin Workplaces/catalog authority into PixelCraft.

This contract is a **planned foundation only**; full Nixin integration is not part of PF2/PF3.

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
PKG-02 existing-package ownership audit         PLANNED AFTER PF FLOW STABILIZES
PKG-03 camera package extraction review         DEFER UNTIL AFTER PF3

G7A Release Engineering / Store Preparation    MERGED
G7B Store Account Integration / Beta Upload    DEFERRED INDEFINITELY

PF0 Platform-flow foundations                  MERGED / ACTIVE FOUNDATION
PF1 Camera-first mobile/tablet shell            MERGED
PF2 Unified Camera Film/Filter/Adjust UX        IMPLEMENTED / DEVICE VALIDATION PENDING — PR #48
PF3 Capture-process-save-to-Gallery             PLANNED
PF4 Gallery-to-editor source flow               PLANNED
PF5 External edit request/result foundation     PLANNED FOUNDATION ONLY

MobileSAM / ONNX segmentation                  FUTURE / NOT ACTIVATED
Real RAW development                           FUTURE / NOT ACTIVATED
Dart 3.13 native tree-shaking / RecordUse       FUTURE / DEFERRED / DO NOT START NOW
```

## Verification

Standard automated verification includes:

```text
bash tool/check_package_boundaries.sh
make gpu-lut-verify
make verify-native
flutter analyze
flutter test
```

For PF2 closure, also run the complete physical-device checklist in:

```text
docs/PF2_DEVICE_VALIDATION_CHECKLIST.md
```

Do not claim device validation from CI alone.
