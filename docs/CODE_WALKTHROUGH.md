# PixelCraft Code Walkthrough

Repository: **PixelCraft**  
Product: **Dextryx Pixels** (`Dxtr Pixs`)

## 1. Product scope

PixelCraft is the **camera + photo editor + image-processing product**.

It owns:

- phone/tablet camera UX;
- editor UX and session lifecycle;
- Rust-authoritative recipe/history/checkpoint semantics;
- Film, Creative Filter, Adjust, transforms, and masks;
- realtime GPU preview where faithful;
- full-resolution render/export;
- editor recovery and bounded source reopening continuity.

**Nixin / Dextryx Images** is the separate image-management product. It owns Workplaces, asset identity, import/catalog organization, browsing, collections, and large-library UX.

PixelCraft must not evolve into a second DAM by default.

---

## 2. Platform shell policy

### Phone and tablet

Phone and tablet are **camera-first**.

Target launch:

```text
launch
  ↓
Camera
  ├── Film / Filter / Adjust
  └── Gallery / Shutter / Controls
```

Tablet may adapt spacing/layout but keeps the same mental model.

### Desktop

Desktop is **editor/open/drop-first**.

```text
launch
  ↓
Open / Drop surface
  ↓
Product Editor
```

Primary inputs are Open Image and Drag & Drop. Secondary/future inputs may include Open Recent, Paste Image, Capture from Camera, Open With, and Nixin external-edit requests.

---

## 3. Current implementation vs target

Current `lib/main.dart` still boots Rust and returns `HomeScreen`.

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

PF1 should reuse this stack and change the product shell rather than creating another camera implementation.

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
- **right:** camera controls/settings.

Film, Filter, and Adjust are camera-context tools rather than separate top-level destinations.

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

---

## 6. Gallery/editor source flow

```text
Gallery picker
  ↓
format-aware source descriptor
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

The source is immutable input. Output is separate.

```text
JPEG source -> remains JPEG source
PNG source  -> remains PNG source
WebP source -> remains WebP source
future RAW  -> remains RAW source
```

---

## 7. Flutter state management

PixelCraft standardizes on **Riverpod** for application/UI orchestration.

`ProviderScope` already exists at the app root.

Recommended boundaries:

```text
AppPreferencesState
CameraState
LiveLookState
EditorUiState
ProcessingJobState
ExternalEditState    # future
```

Riverpod may own transient UI/application state such as camera initialization, selected lens, Film/Filter/Adjust preview values, progress, errors, selected editor tool, and export/save state.

Riverpod must not become authority for:

```text
canonical edit recipe
operation ordering semantics
undo/redo history
checkpoints
full-resolution export semantics
```

Those remain Rust-owned.

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

These values drive low-latency preview and capture configuration. They are not automatically committed editor history.

On capture/export, selected configuration is converted into the existing Rust-authoritative processing path.

---

## 9. Localization

Use **easy_localization** for new user-facing Flutter UI.

Initial locales:

```text
en
th
```

Policy:

```text
device th_* -> th
device en_* -> en
unsupported -> en
fallback -> en
```

Initial asset layout:

```text
assets/translations/en.json
assets/translations/th.json
```

---

## 10. Preferences persistence

Use an `AppPreferencesStore` abstraction rather than adding a general database prematurely.

Candidate preferences:

```text
lastLens
gridEnabled
flash preference
lastFilmId / strength
lastFilterId / strength
theme
optional locale override
last editor UI tool
```

Responsibilities stay separate:

```text
EditorSessionStore
 = coherent edit-session recovery

WorkspaceCatalogStore
 = bounded editor-local source/reopen metadata

AppPreferencesStore
 = user/UI preferences

Rust recipe/history
 = authoritative edit semantics
```

Do not add Hive without a concrete persistence requirement.

---

## 11. App/service boundaries

Target application boundaries:

```text
AppPreferencesStore
MediaPickerService
MediaSaveService
PermissionService
CapabilityRegistry
ProcessingJob coordinator/state
AppRouter / route abstraction
```

`MediaPickerService` returns source information without inventing edit semantics or DAM identity.

`MediaSaveService` is the common output boundary for camera JPEG results and editor Gallery exports.

`PermissionService` centralizes Camera/Gallery/save permission state and presentation mapping.

`CapabilityRegistry` exposes runtime capabilities rather than forcing UI to infer behavior from platform names alone.

---

## 12. Processing job model

Longer work uses explicit state:

```text
idle
processing
saving
completed
failed
```

Shutter/export should prevent duplicate submission while the relevant operation is active.

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

Presentation maps technical failures to localized user messages.

---

## 13. Navigation boundary

Target intent flows:

```text
Mobile/tablet
Launch -> Camera -> Gallery Picker -> Editor -> Export -> Camera

Desktop
Launch -> Open/Drop -> Editor -> Export

Future external edit
Nixin request -> Editor -> PixelCraftEditResult -> caller
```

The router models product intent and must not encode Nixin DAM business logic into PixelCraft screens.

---

## 14. Source descriptor and future external edit

Use a format-aware source contract.

Future request shape may contain:

```text
version
sourceUri / sourcePath
sourceId?           # caller-owned external identity
sourceMimeType
requestedMode
returnPolicy
metadata?
```

Future result may contain:

```text
version
outputUri / outputPath
outputMimeType
sourceId?
recipeReference?    # only if explicitly designed
metadata?
```

Nixin remains authoritative for Workplaces/catalog identity. PixelCraft remains authoritative for edit session and processing semantics.

---

## 15. Editor-local catalog and recovery

Current bounded persistence:

```text
lib/core/editor_session_store.dart
lib/core/workspace_catalog_store.dart
```

`WorkspaceCatalogStore` is retained only for continuity/reopen behavior. It is not a product library database.

Do not extend it by default into Workplaces, bulk ingestion, ratings/flags/keywords, archive management, or a Lightroom-style DAM.

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

Unsupported native/GPU capability must fall back to a valid Rust/product path rather than changing semantics.

---

## 18. Film and Creative Filter

Film Profiles are first-class Rust operations using canonical 33x33x33 LUT data.

Current inspired Film pack includes Provia, Velvia, Astia, E100, Ektar, and Chrome 64.

Creative Filter foundation includes grayscale/invert and canonical LUT-backed presets such as vintage, oceanic, lofi, dramatic, golden, and pastel pink.

PF2 integrates these capabilities into one camera tool surface rather than duplicating processing semantics.

---

## 19. Package graph

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

Package policy:

- consolidate ownership into existing packages before adding new ones;
- keep app services/navigation/preferences in the app unless reuse proves a stable package boundary;
- audit remaining `lib/core` ownership after PF0/PF1;
- defer `dxtr_pixs_camera` extraction until PF3 stabilizes capture and processing-handoff contracts.

Future package family only when activated:

```text
dxtr_pixs_segment
dxtr_pixs_restore
dxtr_pixs_raw
```

---

## 20. Future MobileSAM / ONNX

Future segmentation belongs behind a replaceable `MaskProvider` boundary.

```text
source / reduced analysis image
  ↓
MaskProvider
  ↓
local MobileSAM/ONNX
  ↓
mask result
  ↓
PixelCraft edit semantics
```

Segmentation generates masks and never becomes image-processing authority.

Do not activate this in PF0-PF5.

---

## 21. Future real RAW

Future package direction:

```text
dxtr_pixs_raw
```

A real RAW milestone must explicitly define decode/demosaic, Bayer/X-Trans handling, black/white normalization, camera WB/color matrices, highlight recovery, working color space, memory/performance policy, and authoritative full-resolution replay/export.

PF source contracts must stay RAW-aware without implementing RAW development now.

---

## 22. CI workflow

The repository uses an affected-validation DAG defined in `.github/workflows/ci.yml` and documented in `docs/CI_ARCHITECTURE.md`.

```text
Change Detection
      ↓
Fast CI
      ↓
selected affected/full validation
      ↓
CI Gate
```

Change domains include docs, Flutter app/packages, native/GPU, Android, iOS, macOS, Windows/Linux, package API, reliability, and CI/tooling.

Iterative PRs run only relevant expensive jobs. Full validation is forced for:

```text
push to main
merge_group
explicit full workflow dispatch
PR label ci:full
CI/tooling changes
```

Stable branch-protection contexts:

```text
Fast CI
CI Gate
```

Do not require every conditional platform job individually because unaffected jobs are intentionally skipped.

### Local preflight

Recommended entrypoint:

```bash
make preflight
```

Focused targets:

```bash
make format-check
make analyze
make test-fast
make gpu-check
make ci-fast
```

### FRB artifact reuse

Fast CI generates and verifies the complete FRB bridge, including companion Dart outputs under `lib/src/rust/**`, plus `rust/src/frb_generated.rs` and `ios/Runner/frb_generated.h`.

The generated bridge is uploaded as a run-scoped artifact and restored by platform jobs. `Native/GPU Core` still independently regenerates with pinned FRB codegen when selected to validate deterministic API/native drift.

### Reliability tiers

```text
Tier 1 = fast deterministic correctness
Tier 2 = sensitive-path automation, G6 failure injection, 12 MP characterization, device-safety guard
Tier 3 = complete hosted G6 automation up to 48 MP; physical device remains explicit/manual evidence
```

Hard device safety:

```text
main app: dev.cnxdev.pixelcraft
verifier: dev.cnxdev.pixelcraft.g6verify
```

Hosted CI must never uninstall/overwrite the main app or fabricate physical-device PASS evidence.

### Validated CI baseline

PR #49 full run #432 (`31951272254`) passed:

```text
Change Detection
Fast CI
Native/GPU Core
Golden Tests
Android Build
iOS Build
macOS Build
Windows Build
Linux Build
Reliability Tier 2
Reliability Tier 3
CI Gate
```

After PR merge, verify the resulting `main` push CI before declaring the CI slice closed.

---

## 23. Current milestone sequence

```text
PF0 platform-flow foundations
 -> PF1 Camera-first mobile/tablet shell + desktop editor-first root
 -> PF2 Unified Camera Film/Filter/Adjust UX
 -> PF3 Capture + Rust render + JPEG Gallery save + stay in Camera
 -> PKG-03 evaluate camera package extraction
 -> PF4 Gallery source -> editor -> Gallery export
 -> PF5 Versioned external-edit request/result foundation
```

Not part of PF0-PF5 unless separately activated:

```text
Hive migration
second global state-management framework
Workplaces/DAM expansion
MobileSAM implementation
real RAW implementation
Dart 3.13 RecordUse work
G7B store account work
```

---

## 24. Verification gates

Primary local gate:

```bash
make preflight
```

Additional targeted validation:

```bash
bash tool/check_package_boundaries.sh
make gpu-lut-verify
make verify-native
flutter analyze
flutter test
```

PF implementation should add targeted tests for platform-adaptive routing, mobile/tablet camera launch, desktop open/drop launch, locale fallback, preferences boundaries, duplicate processing prevention, source preservation, capture -> JPEG save -> remain in Camera, Gallery -> editor -> export, and future external-edit serialization/versioning.

A green PR head is not enough to close a slice; verify resulting `main` push CI.

---

## 25. Current continuation point

First finish PR #49 closure on the latest documentation-synced head, mark it Ready only after `Fast CI` + `CI Gate` are green, merge, and verify resulting `main` CI.

Then continue product work with **PF0 + PF1**. Establish platform root, localization/state/preferences/service foundations, then move the existing verified camera implementation into the primary phone/tablet experience without creating a second camera or processing authority.

See `docs/PROJECT_HANDOFF.md` for the canonical execution order and current status.
