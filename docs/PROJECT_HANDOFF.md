# PixelCraft Project Handoff

## Purpose

Canonical continuation document for repository **PixelCraft** and product **Dextryx Pixels**.

For a new session:

1. read this file first;
2. inspect `main`, active PRs, review threads, and latest CI;
3. continue from **Current next action**;
4. repository state and recorded CI/device evidence override older chat history.

Recommended continuation prompt:

```text
อ่าน docs/PROJECT_HANDOFF.md ใน repo PixelCraft แล้วทำต่อจาก Current next action
```

Last refresh: **2026-08-16. Product direction is platform-adaptive: phone/tablet are camera-first; desktop is editor/open/drop-first. PixelCraft remains the camera/photo-editing/image-processing product. Nixin/Dextryx Images remains the image-management product and may invoke PixelCraft through a future versioned external-edit contract. Cross-cutting PF foundations are now explicitly defined: easy_localization, Riverpod, preferences/service boundaries, typed processing state, adaptive navigation, and future-safe source contracts.**

---

# 1. Product identity

```text
master brand: Dextryx
product: Dextryx Pixels
installed label: Dxtr Pixs
short mark: DXTR PIXS or DXTR + pixel/film symbol
repository: PixelCraft
Flutter/Dart package family: dxtr_pixs_*
Android applicationId: dev.cnxdev.pixelcraft
iOS bundle id: dev.cnxdev.pixelcraft
```

Rules:

- user-facing copy uses **Dextryx Pixels**;
- launcher/home-screen label uses **Dxtr Pixs**;
- repository name and app identifiers remain unchanged unless a separate migration is approved;
- historical evidence may retain the name that existed when produced;
- native ABI/runtime identifiers and persisted schema names are not branding concerns.

---

# 2. Canonical product boundary — PixelCraft vs Nixin

## PixelCraft / Dextryx Pixels

**Primary role: camera + photo editor + image-processing product.**

Owns:

```text
mobile/tablet camera experience
edit session UX
Rust authoritative recipe/history/checkpoint
image-processing semantics
GPU preview
Film Profiles / Creative filters
adjustments / transforms / masks
full-resolution render/export
editor recovery/session continuity
```

PixelCraft may keep a small editor-local source/recovery layer only when needed for continuity. It is not the long-lived DAM/catalog product.

PixelCraft must not grow by default into:

```text
Workplaces hierarchy
large library/catalog management
folder ingestion/archive management
ratings/flags/keywords catalog systems
large-scale metadata browsing/search
Lightroom-style DAM behavior
```

## Nixin / Dextryx Images

**Primary role: image manager / catalog / Workplaces product.**

Nixin owns asset identity, long-lived organization, browsing, catalog metadata, import, source management, collections, and future library workflows.

## Reusable PixelCraft modules

Nixin may consume stable, explicitly reusable PixelCraft modules/packages for bounded capabilities. Reuse must not import PixelCraft app-internal UI/state or transfer ownership of Nixin catalog identity.

## Future external-edit direction

```text
Nixin / Dextryx Images
  owns asset/catalog identity
  ↓ PixelCraftEditRequest
PixelCraft / Dextryx Pixels
  owns edit session + processing + render/export
  ↓ PixelCraftEditResult
Nixin resumes asset management
```

Guardrails:

1. Nixin remains authoritative for Workplaces/catalog/asset identity.
2. PixelCraft/Rust remains authoritative for PixelCraft edit recipes and pixel-processing semantics.
3. The protocol must be versioned before implementation.
4. Do not make Nixin depend on `HomeScreen`, `ProductEditorScreen`, or other app-internal Flutter classes.
5. Prefer a narrow request/result contract that can later be transported by deep link, Android intent, iOS share/open-in, desktop launch arguments, or another explicit mechanism.

---

# 3. Canonical platform product flow

## Phone and tablet — camera-first

Phone and tablet share the same mental model. Tablet may adapt layout for larger screens, but the launch behavior remains camera-first.

```text
App launch
   ↓
Camera
```

Target camera shell:

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

Rules:

- center bottom = **Shutter**;
- bottom left = **Gallery** / recent-source entry;
- bottom right = camera controls/settings surface;
- Film, Filter, and Adjust are available without leaving Camera;
- verified GPU paths provide low-latency preview where faithful;
- unsupported GPU operations fall back safely rather than diverging from Rust semantics.

### Camera capture target

```text
clean camera capture
+ selected Film / Filter / Adjust configuration
        ↓
Rust authoritative full-resolution render
        ↓
JPEG output
        ↓
MediaSaveService
        ↓
system Gallery
        ↓
remain in Camera
```

Hard rules:

1. camera capture remains clean internally;
2. live preview pixels are never final-render authority;
3. camera result saved by the PF flow is JPEG;
4. shutter does not force the user into the editor after every capture;
5. after save, Camera remains active;
6. recent thumbnail/confirmation may update;
7. tapping the recent thumbnail may enter the editor for additional work.

### Gallery/editor target

```text
Gallery
 -> choose source
 -> preserve original source untouched
 -> Product Editor
 -> Film / Filter / Adjust / transforms / future masks
 -> Rust full-resolution render
 -> save processed result to Gallery / explicit destination
```

Source-format rule:

- JPEG remains JPEG source;
- PNG remains PNG source;
- WebP remains WebP source;
- future RAW remains RAW source;
- output format is a separate decision from source preservation.

## Desktop — editor/open/drop-first

Desktop must **not** launch into the mobile camera shell.

```text
App launch
   ↓
Editor launcher / open / drop surface
```

Primary desktop input:

```text
Open Image / Drag & Drop
```

Secondary/future inputs:

```text
Open Recent
Paste Image
Capture from Camera
Open With / external edit request
Nixin external edit
```

Desktop editor direction:

```text
┌──────────────┬──────────────────────┬──────────────┐
│ Film/Filter  │                      │ Adjustments  │
│ Presets/Mask │    image preview     │ Light/Color  │
│              │                      │ Detail/Curve │
├──────────────┴──────────────────────┴──────────────┤
│ context strip / thumbnails / history / compare    │
└───────────────────────────────────────────────────┘
```

Panels should be collapsible. Desktop remains an editor, not a DAM/library clone.

---

# 4. Architecture invariants

```text
Flutter   = UI / control / presentation plane
Riverpod  = Flutter application/UI orchestration
Rust      = authoritative image semantics / recipe / history / checkpoint / recovery / export
Metal     = iOS realtime GPU preview
OpenGL ES = Android realtime camera preview
```

Hard contracts:

1. Rust owns committed edits, recipe/history/checkpoint/recovery, and full-resolution render/export.
2. GPU rendering is preview-only and never final-render authority.
3. Camera Film/Filter/Adjust preview never bakes the live preview framebuffer into the authoritative source.
4. Live camera buffers never cross MethodChannel or Flutter Rust Bridge.
5. Canonical Film/Creative LUT data is Rust-owned.
6. Native/GPU failure fails closed to valid Rust/product state.
7. Unsupported Rust operation order falls back; never silently reorder for GPU.
8. Film Profiles are reusable configuration, not per-image pixels/sessions.
9. Imported recipe fields report exact / approximated / unsupported mappings.
10. New effects are Rust-first; GPU support is enabled only when faithful.
11. Riverpod may orchestrate UI/transient preview state but must not become canonical recipe/history authority.
12. AI segmentation/restoration is optional capability and never committed-image authority.
13. Do not casually replace mobile Metal/OpenGL ES runtime with wgpu.
14. Editor-local workspace/catalog state is metadata/navigation state only and never authoritative edit/pixel state.
15. Recovery generations remain crash/session recovery and are not catalog identity.
16. Long-lived image-management ownership belongs to Nixin.
17. External-edit integration must use explicit request/result contracts rather than app-internal UI coupling.

---

# 5. Current milestone status

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
G7B Store Account Integration / Beta Upload    DEFERRED INDEFINITELY / NOT SCHEDULED

UX-01 Modern import/add-photo entry flow        CLOSED / VERIFIED
UX-02 Home / Workspace modernization            CLOSED / VERIFIED
W1A/W1B editor-local catalog contract/storage  CLOSED / VERIFIED
W1C acquisition/catalog/Home integration       CLOSED / VERIFIED
W1D DAM-style multi-item expansion              CANCELLED AS DEFAULT DIRECTION

PF0 Platform-flow foundations                   NEXT / NOT IMPLEMENTED
PF1 Camera-first mobile/tablet shell             PLANNED
PF2 Unified Camera Film/Filter/Adjust UX         PLANNED
PF3 Capture-process-save-to-Gallery              PLANNED
PF4 Gallery-to-editor source flow                PLANNED
PF5 External edit request/result contract        PLANNED FOUNDATION ONLY

MobileSAM / ONNX segmentation                   FUTURE / NOT ACTIVATED
Real RAW development                            FUTURE / NOT ACTIVATED
O1 Dart 3.13 native tree-shaking / RecordUse    FUTURE / DEFERRED / DO NOT START NOW
```

`PF0` is a cross-cutting foundation slice introduced to avoid embedding platform behavior directly into screens before PF1-PF5.

Historical G7 PR #10 is closed/superseded. Do not reopen it.

---

# 6. PF0 — platform-flow foundations

PF0 should be implemented before or as the first slice of PF1.

## Localization

Use **easy_localization**.

Initial locales:

```text
en
th
```

Locale policy:

```text
device th_* -> th
device en_* -> en
unsupported locale -> en
fallback -> en
```

Initial resource layout:

```text
assets/translations/en.json
assets/translations/th.json
```

New user-facing Flutter strings should be localized rather than hardcoded.

## State management

Use **Riverpod** as the Flutter state-management standard. `ProviderScope` already exists at the app root.

Recommended state boundaries:

```text
AppPreferencesState
CameraState
LiveLookState
EditorUiState
ProcessingJobState
ExternalEditState   # future orchestration
```

Do not add Bloc/GetX or another competing global state framework without an explicit architectural reason.

Riverpod is not image-processing authority.

## Preferences

Introduce an abstraction such as:

```text
AppPreferencesStore
```

Candidate values:

```text
last camera lens
grid enabled
flash/camera UI preference
last Film id + strength
last Filter id + strength
theme
optional locale override
last editor UI tool
```

Do **not** add Hive merely as future-proofing. Use a lightweight replaceable backend until a real database use case appears.

## Application services

Introduce or converge toward explicit service boundaries:

```text
MediaPickerService
MediaSaveService
PermissionService
CapabilityRegistry
ProcessingJob coordinator/state
AppRouter / navigation abstraction
```

### MediaPickerService

Returns source information without inventing edit semantics or DAM identity.

### MediaSaveService

Common output path for:

- camera JPEG results;
- editor Gallery exports;
- future explicit save-copy destinations.

### PermissionService

Centralize Camera/Gallery/save permission state, denied/restricted behavior, and localized presentation mapping.

### CapabilityRegistry

UI should query capability rather than infer behavior only from platform names.

Examples:

```text
native camera GPU preview available
Film realtime preview available
Creative Filter realtime preview available
specific Adjust preview support
source-format support
future segmentation/RAW support
```

## Processing job state

Use an explicit job model for longer processing/saving work:

```text
idle
processing
saving
completed
failed
```

Prevent duplicate shutter/export submission while the relevant job is active.

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

Map these to localized user messages at the presentation boundary.

## Navigation

Introduce a lightweight route/navigation abstraction instead of expanding direct `Navigator.push` calls across every screen.

Target intent flows:

```text
Mobile/tablet
Launch -> Camera -> Gallery Picker -> Editor -> Export -> Camera

Desktop
Launch -> Open/Drop -> Editor -> Export

Future external edit
Nixin request -> Editor -> PixelCraftEditResult -> caller
```

## Format-aware source descriptor

Do not make new input contracts assume every file is JPEG/PNG.

A source descriptor should be able to carry:

```text
uri/path
mime type / format
source provenance
optional caller-owned external id
metadata needed for opening/returning
```

This is required so future RAW and Nixin integration do not force a redesign of source identity.

---

# 7. Existing implementation relevant to PF1-PF4

Current runtime still boots Rust and returns `HomeScreen`; PF1 changes platform routing.

Existing camera foundation already provides:

- native GPU camera preview on supported iOS/Android paths;
- Flutter `camera` fallback;
- camera switch;
- Film preview and strength control;
- permission/lifecycle handling;
- clean capture path;
- capture -> editor handoff.

PF work must reuse this foundation rather than build a second camera stack.

Current capture opens the editor after taking a picture. PF3 changes this to authoritative processing + JPEG save + remain in Camera.

Existing `WorkspaceCatalogStore` remains useful only for bounded continuity/reopen behavior. It must not become the primary launch experience or a DAM.

Existing `EditorSessionStore` remains coherent edit recovery and is separate from preferences/catalog concerns.

---

# 8. Film and Filter status

Film and Creative Filter are already substantial production foundations.

Film:

```text
EditOperation::FilmProfile { id, strength }
33x33x33 canonical LUTs
Rust-authoritative replay/export
verified realtime GPU LUT preview where supported
```

Current Film pack includes inspired looks such as:

```text
Provia
Velvia
Astia
E100
Ektar
Chrome 64
```

Creative filters include:

```text
grayscale
invert
vintage
oceanic
lofi
dramatic
golden
pastel_pink
```

PF2 is primarily a **camera UX integration milestone**, not a reinvention of Film/Filter semantics.

---

# 9. Future MobileSAM / ONNX segmentation

Future package direction:

```text
dxtr_pixs_segment
```

Status: **FUTURE / NOT ACTIVATED**.

When activated, segmentation should sit behind a replaceable mask-provider boundary:

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

Segmentation generates masks. It is not committed-image authority.

Do not mix MobileSAM implementation into PF0-PF5.

---

# 10. Future real RAW development

Future package direction:

```text
dxtr_pixs_raw
```

Status: **FUTURE / NOT ACTIVATED**.

A real RAW milestone must separately define:

- RAW decode/demosaic;
- Bayer/X-Trans support where applicable;
- black/white level normalization;
- camera WB/color matrices;
- highlight recovery;
- working color-space conversion;
- RAW-specific memory/performance policy;
- authoritative full-resolution replay/export.

PF source contracts must remain RAW-aware, but PF0-PF5 must not implement real RAW development unless explicitly activated.

---

# 11. Future external-edit contract

PF5 creates the foundation only; it does not implement a full Nixin integration automatically.

A future request may contain:

```text
version
sourceUri / sourcePath
sourceId?          # caller-owned identity
sourceMimeType
requestedMode
returnPolicy
metadata?
```

A future result may contain:

```text
version
outputUri / outputPath
outputMimeType
sourceId?
recipeReference?   # only if explicitly designed
metadata?
```

Rules:

1. Nixin owns its asset id and Workplaces membership.
2. PixelCraft owns its edit session/recipe semantics.
3. Do not make Nixin import PixelCraft widgets or app-internal providers.
4. Transport is separate from the request/result model.

---

# 12. Persistence boundaries

Keep responsibilities separated:

```text
EditorSessionStore
 = coherent edit-session recovery

WorkspaceCatalogStore
 = bounded editor-local source/reopen metadata

AppPreferencesStore
 = lightweight user/UI preferences

filesystem/system Gallery
 = image files

Rust recipe/history
 = authoritative editing semantics
```

Do not add a general database or Hive until an actual persistence problem requires one.

Do not repurpose `WorkspaceCatalogStore` into Nixin-style Workplaces, folder ingestion, bulk organization, ratings, flags, keywords, or a large catalog browser.

---

# 13. Package graph and naming

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

Future package family:

```text
dxtr_pixs_segment  MobileSAM/local segmentation
dxtr_pixs_restore  restoration capabilities
dxtr_pixs_raw      real RAW development
```

Native/runtime identifiers intentionally remain stable unless separately justified.

Boundary guard:

```text
tool/check_package_boundaries.sh
```

---

# 14. Verified recent baseline

Recent merged work includes:

```text
PR #20  Before/After Compare
PR #21  Film library search/origin filters
PR #22  Compare session/wide-layout fix
PR #23  Zoom / Fit controls
PR #24  precise numeric adjustment entry
PR #25  histogram channel inspector
PR #26  precise straighten angle entry
PR #27  Dextryx Pixels / Dxtr Pixs identity
PR #30  dxtr_pixs_* reusable package namespace
PR #33  deferred Dart 3.13 native tree-shaking plan
PR #37  direct primary Import acquisition path
PR #38  Home workspace modernization
PR #39  real persisted recent-edit card
PR #41  editor-local workspace catalog foundation
PR #42  acquisition/catalog/Home integration
PR #43  product-boundary correction: PixelCraft editor vs Nixin manager
```

Verified W1 baseline before the platform-flow pivot:

```text
PR #42 final head: 1218ec44d0d9938a89b7f7ab294b0a55a2f435b5
PR #42 PR CI: #362 / 31930004255 / success
PR #42 merge: a5d015587a9eab0125d8605f91fff9307e8d0c11
main CI after #42: #363 / 31930570158 / success
```

PR #43 is merged. Do not infer resulting-main CI status unless exact evidence is available.

Historical G7 PR #10 remains closed/superseded.

---

# 15. Deferred work

## O1 — Dart 3.13 RecordUse / native tree-shaking

**FUTURE / DEFERRED / DO NOT START NOW.**

Detailed plan:

```text
docs/FUTURE_DART_3_13_NATIVE_TREE_SHAKING.md
```

## G7B

**DEFERRED INDEFINITELY / NOT SCHEDULED.**

Neither O1 nor G7B blocks PF0-PF5.

---

# 16. Reliability / device evidence

G6 is closed/verified.

```text
main app id: dev.cnxdev.pixelcraft
DO NOT uninstall or overwrite installed main app during verifier runs
temporary verifier id: dev.cnxdev.pixelcraft.g6verify

iPhone 11 UDID: 00008030-0004694C3E68C02E
10 reliability cycles: PASS
manual physical checklist: completed
```

Historical evidence must not be rewritten to newer branding.

---

# 17. Release baseline

Android:

```text
applicationId: dev.cnxdev.pixelcraft
marketing version: 0.1.0 pre-1.0 beta/RC
build: 1
minSdk: 24
targetSdk: 36
compileSdk: 36
release must not use debug signing
RECORD_AUDIO must remain absent
```

iOS:

```text
bundle id: dev.cnxdev.pixelcraft
deployment target: 13.0
pixelcraft_engine native integration remains required
Film/Creative GPU LUT assets remain required
release --no-codesign is part of CI validation
```

---

# 18. Verification rules

1. Never claim CI/test/device/build/store validation passed unless actually run or explicitly reported.
2. Never commit signing secrets, certificates, provisioning profiles, passwords, or store credentials.
3. Never ship Android production artifacts with debug signing.
4. Do not weaken Rust authority, GPU fail-closed behavior, or package boundaries.
5. A PR being green is not enough to declare a slice complete; verify resulting `main` push CI after merge.
6. Do not import Nixin roadmap items into PixelCraft; implement only the external-edit boundary explicitly approved here.
7. Do not bind Nixin to PixelCraft app-internal UI classes/providers.
8. Mobile/tablet camera-first and desktop editor-first are product policies; do not collapse them into one generic Home UI.
9. Camera live preview pixels are never final-render authority.
10. Camera captures saved by PF3 are JPEG outputs generated through the authoritative processing path.
11. Gallery/external source inputs remain untouched; output is separate.
12. Riverpod is UI/application orchestration only; Rust remains edit authority.
13. Localization begins with en/th, device detection, fallback en.
14. Do not introduce Hive without a concrete persistence requirement.
15. Do not start MobileSAM, real RAW, O1, or G7B as part of PF0-PF5 unless explicitly activated.

Standard verification:

```text
bash tool/check_package_boundaries.sh
make gpu-lut-verify
make verify-native
flutter analyze
flutter test
```

PF-specific tests should cover:

```text
platform-adaptive root routing
phone/tablet camera launch
desktop open/drop launch
locale device detection + fallback
preferences boundaries
permission/error mapping
processing-job duplicate-action prevention
source preservation
camera capture -> JPEG save -> remain in Camera
Gallery -> editor -> export
external-edit model versioning/serialization when PF5 starts
```

---

# 19. Current next action

Implement **PF0 + PF1 first**.

Required first slice:

1. add `easy_localization` foundation with `en` + `th`, device locale detection, fallback `en`;
2. standardize Riverpod application-state boundaries without moving canonical edit semantics out of Rust;
3. add `AppPreferencesStore` abstraction with a lightweight backend; do not add Hive yet;
4. define `MediaPickerService`, `MediaSaveService`, `PermissionService`, `CapabilityRegistry`, typed `ProcessingJobState`, and a lightweight route/navigation boundary;
5. define a format-aware source descriptor that can later support RAW and external caller identity;
6. introduce platform-adaptive root routing after Rust bootstrap;
7. phone/tablet launch directly into the existing camera foundation;
8. desktop launches an editor/open/drop-oriented surface rather than the mobile camera shell;
9. mobile/tablet camera bottom hierarchy becomes Gallery / Shutter / Controls;
10. preserve current verified GPU/Rust contracts and camera permission/lifecycle hardening;
11. keep Home/Workspace code only as bounded continuity/recovery support while the new root stabilizes;
12. do not start MobileSAM, real RAW, O1, G7B, Hive migration, or Nixin DAM work.

Then proceed in order:

```text
PF0 platform-flow foundations
 -> PF1 camera-first mobile/tablet + desktop editor-first shell
 -> PF2 unified camera Film/Filter/Adjust UX
 -> PF3 capture + authoritative render + JPEG Gallery save + remain in Camera
 -> PF4 Gallery source -> editor -> Gallery export
 -> PF5 versioned external-edit request/result foundation for future Nixin integration
```

Update `docs/CODE_WALKTHROUGH.md`, `README.md`, tests, and this handoff as each PF slice lands.
