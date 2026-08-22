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

Last refresh: **2026-08-22 — PF3 merged in PR #52; PF4 Gallery -> typed Editor source flow is active in PR #55.**

---

# 1. Product identity

```text
master brand: Dextryx
product: Dextryx Pixels
installed label: Dxtr Pixs
repository: PixelCraft
Flutter/Dart package family: dxtr_pixs_*
Android applicationId: dev.cnxdev.pixelcraft
iOS bundle id: dev.cnxdev.pixelcraft
```

Rules:

- user-facing copy uses **Dextryx Pixels**;
- launcher/home-screen label uses **Dxtr Pixs**;
- repository name and runtime app identifiers remain unchanged unless separately approved;
- native ABI/runtime identifiers and persisted schema names are not branding concerns.

---

# 2. Product boundary — PixelCraft vs Nixin

## PixelCraft / Dextryx Pixels

Primary role: **camera + photo editor + image-processing product**.

Owns:

```text
mobile/tablet camera experience
edit session UX
Rust authoritative recipe/history/checkpoint/recovery
image-processing semantics
GPU preview
Film Profiles / Creative Filters
adjustments / transforms / masks
full-resolution render/export
editor recovery/session continuity
```

PixelCraft may keep bounded editor-local source/recovery metadata for continuity. It is not the long-lived DAM/catalog product.

## Nixin / Dextryx Images

Primary role: **image manager / catalog / Workplaces product**.

Nixin owns asset identity, long-lived organization, browsing, catalog metadata, import, source management, collections, and future library workflows.

Future external edit must use an explicit versioned request/result contract. Nixin keeps asset/catalog authority; PixelCraft/Rust keeps edit/pixel authority.

---

# 3. Canonical platform flow

## Phone and tablet — camera-first

```text
App launch
   ↓
Greeting / permissions when required
   ↓
Camera
```

Target shell is now implemented:

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

- center bottom = Shutter;
- bottom left = Gallery;
- bottom right = Controls;
- Film, Filter, Adjust are Camera-context tools;
- unsupported GPU behavior fails closed/falls back safely.

### Camera capture

PF3 implementation:

```text
clean camera JPEG
+ selected Film / Filter / Adjust
+ image ratio / orientation / zoom
        ↓
CameraCapturePipeline
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

1. clean camera JPEG remains authoritative source;
2. preview framebuffer pixels are never final output;
3. PF3 output is JPEG;
4. Shutter does not force Editor navigation;
5. Camera remains active after save;
6. permission prompts do not interrupt an active shutter -> process -> save transaction.

### Gallery/editor

PF4 active flow:

```text
Gallery
 -> MediaPickerService
 -> MediaSourceDescriptor
 -> EditorSourceFactory
 -> typed EditorSource
 -> EditorRouteData.source
 -> Product Editor
 -> Film / Filter / Adjust / transforms / masks
 -> Rust full-resolution render
 -> save processed result to Gallery / explicit destination
```

Rules:

- preserve the original source untouched;
- Gallery/external sources do not inherit transient CameraLook;
- source provenance/MIME/external id/format identity remain attached to the typed source contract;
- current file-backed sources derive a path only at the Product Editor compatibility boundary;
- non-file typed sources fail closed until a supported resolver/decoder exists;
- RAW/HEIF identities may be represented without activating deferred RAW development.

## Desktop — editor/open/drop-first

Desktop launches into Open/Drop -> Editor, not the mobile camera shell and not a DAM/library clone.

---

# 4. Architecture invariants

```text
Flutter   = UI / control / presentation
Riverpod  = Flutter application/UI orchestration
Rust      = authoritative image semantics / recipe / history / checkpoint / recovery / export
Metal     = iOS realtime GPU preview
OpenGL ES = Android realtime camera preview
```

Hard contracts:

1. Rust owns committed edits and full-resolution render/export.
2. GPU rendering is preview-only.
3. Camera preview never replaces clean capture source.
4. Live camera buffers never cross MethodChannel/FRB as a continuous stream.
5. Canonical Film/Creative LUT data is Rust-owned.
6. Native/GPU failure fails closed to valid product state.
7. Riverpod must not become canonical recipe/history authority.
8. Long-lived image-management ownership belongs to Nixin.
9. External-edit integration uses explicit request/result contracts.
10. Do not casually replace mobile Metal/OpenGL ES runtime with wgpu.

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
PKG-02 existing-package ownership audit         PLANNED
PKG-03 camera package extraction review         AUDITED / DEFERRED

G7A Release Engineering / Store Preparation    MERGED
G7B Store Account Integration / Beta Upload    DEFERRED INDEFINITELY

UX-01 Modern import/add-photo entry flow        CLOSED / VERIFIED
UX-02 Home / Workspace modernization            CLOSED / VERIFIED
W1A/W1B editor-local catalog contract/storage  CLOSED / VERIFIED
W1C acquisition/catalog/Home integration       CLOSED / VERIFIED
W1D DAM-style multi-item expansion              CANCELLED AS DEFAULT DIRECTION

CI-01 affected fast-fail / reliability tiers    CLOSED / VERIFIED

PF0 Platform-flow foundations                   ROUTING FOUNDATION MERGED (#50)
PF1 Camera-first mobile/tablet shell             IMPLEMENTED
PF2 Unified Camera Film/Filter/Adjust UX         IMPLEMENTED
PF3 Capture-process-save-to-Gallery              MERGED (#52)
PF4 Gallery-to-editor source flow                IN PROGRESS (#55)
PF5 External edit request/result contract        PLANNED FOUNDATION ONLY

Plugin-oriented feature architecture            FUTURE / PLANNED / DO NOT ACTIVATE YET
MobileSAM / ONNX segmentation                   FUTURE / NOT ACTIVATED
Real RAW development                            FUTURE / NOT ACTIVATED
O1 Dart 3.13 native tree-shaking / RecordUse    FUTURE / DEFERRED / DO NOT START NOW
```

---

# 6. PF3 implementation details

## Camera look and preview

Camera uses `CameraLookState` for transient Film/Filter/Adjust preview configuration.

Film/Filter thumbnail trays use bounded non-shutter live snapshots:

```text
channel: dev.pixelcraft/gpu_preview_snapshot_v1
Android source: active OpenGL-backed TextureView
Apple source: active Metal camera preview
```

Refresh is bounded/coalesced and stops when the tray is disposed.

Hard invariant:

```text
_enableStillCaptureLookPreviews = false
```

Opening Film/Filter must never call real still capture or produce a shutter sound.

## Authoritative render serialization

The current Rust image engine is process-global. Individual bridge calls are synchronized, but an entire `loadImage -> edits -> exportImage` sequence must be atomic relative to other captures.

`CameraCapturePipeline` therefore serializes complete render transactions before invoking `RustCameraCaptureRenderer`.

Regression coverage starts concurrent pipelines and verifies renderer max concurrency remains 1.

## Android resume/recreation

After pause/external activity, Android recreates the native Camera2/EGL renderer and restores:

```text
enabled state
CameraLook
lens direction
flash mode
torch state
mirror state
output surface / rotation
```

This prevents resume from silently reverting to rear/auto/off/unmirrored defaults.

## Camera Controls

Camera Controls is a modal bottom sheet and now includes an explicit Close button in its header.

## Composition Guide

Implementation:

```text
lib/camera/camera_composition_guide.dart
```

Supported guides:

```text
thirds
goldenRatio
goldenSpiral
```

Golden Spiral is procedurally rendered with Flutter `CustomPainter`/`Path`; do not replace it with PNG/SVG assets by default.

Persistent guide settings:

- selected guide;
- Golden Spiral flip;
- guide color.

Initial color swatches:

```text
White
Black
Red
Yellow
Green
Cyan
```

Guide color updates live. Composition guides are UI overlays only and must never affect captured/saved pixels.

---

# 7. PF3 validation evidence

Physical-device validation completed successfully on Android and iPhone.

Validated behavior includes:

- Android/iPhone live Film/Filter preview;
- first-run Greeting + permissions;
- What's New once-per-ID behavior;
- neutral capture -> process -> save;
- composed-look capture -> process -> save;
- processing/saving feedback remains on Camera;
- Gallery -> Editor regression smoke;
- temporary-source failure/Retry where practical;
- Camera Controls Close interaction;
- Composition Guide color behavior and persistence.

PF3 was merged by PR #52 on 2026-08-22.

```text
main merge: a203cc6202c1a202526294def5b8fe209ca416cd
```

Pre-merge validation evidence retained from PF3:

```text
implementation head: a57b967c62ee0cef2faeaa4ae5db1b8a272e5e9a
Pixel Craft CI #747: PASS
```

Codex review #4999877331 findings were all fixed, replied to, and resolved:

1. serialize background capture render transactions;
2. restore Android camera controls on renderer recreation;
3. keep formatter check mode read-only.

---

# 8. PF4 implementation details

PF4 source contract:

```text
lib/app/editor_source_contract.dart
lib/app/app_routes.dart
lib/ui/screens/camera_film_preview_screen.dart
```

`EditorSource` preserves:

```text
original MediaSourceDescriptor
source provenance
MIME type
external id
format identity
```

`EditorSource.inheritsCameraLook` is false. Gallery/external sources must never inherit transient camera state implicitly.

`EditorRouteData` can carry exactly one of:

```text
legacy image path
image bytes
typed EditorSource
```

For a typed file source, `imagePath` is derived only at the current Product Editor compatibility boundary. A non-file typed source remains preserved but routes to an unsupported-source state until explicit resolution support exists.

The public camera entry is now a narrow PF4 routing wrapper around the existing G1 runtime. `LegacyGalleryEditorRoutingPicker` consumes Gallery selections, opens the canonical typed `/editor` route, then returns `null` to prevent the legacy G1 callback from also opening `CameraFilmEditorHandoff`.

This migration seam deliberately leaves PF3 camera capture/runtime behavior unchanged.

PKG-03 audit is recorded in:

```text
docs/PKG03_CAMERA_EXTRACTION_AUDIT.md
```

Decision: do not extract camera into a package during PF4. Revisit only when a concrete second consumer or stable reusable API exists.

---

# 9. CI architecture and local validation

Affected-validation DAG:

```text
Change Detection
      ↓
Fast CI
      ↓
selected affected/full validation
      ↓
CI Gate
```

Recommended branch-protection contexts:

```text
Fast CI
CI Gate
```

Local commands:

```bash
make format-check
make analyze
make test-fast
make gpu-check
make ci-fast
make preflight
```

`dart-format-check` is read-only. On formatter failure it formats temporary copies and prints a canonical diff without modifying staged/unstaged/untracked developer files.

Hosted CI must never fabricate physical-device PASS evidence.

Device safety invariant:

```text
main app id: dev.cnxdev.pixelcraft
isolated verifier id: dev.cnxdev.pixelcraft.g6verify
```

Do not uninstall or overwrite the main app during verifier/device runs.

---

# 10. State, localization, services

Use Riverpod for Flutter application/UI orchestration and `easy_localization` for user-facing copy.

Initial locales:

```text
en
th
```

Important service boundaries:

```text
AppPreferencesStore
MediaPickerService
MediaSaveService
PermissionService
CapabilityRegistry
ProcessingJob coordinator/state
AppRouter / navigation abstraction
```

Source contracts remain format-aware so future RAW/Nixin integration does not require a source-identity redesign.

---

# 11. Package graph and future plugin boundary

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

Do not add new packages without a stable reuse/ownership boundary.

PKG-03 camera extraction is audited/deferred; do not extract camera merely for organization.

Future feature-plugin architecture is planned but not active. The intended direction is capability/provider based rather than a dynamic arbitrary-code plugin loader: optional features should depend on stable app/domain contracts, register capabilities explicitly, and remain replaceable without becoming image authority. Candidate future features such as MobileSAM should sit behind those boundaries. Do not restructure PF4 solely for future plugins.

---

# 12. Deferred work

Do not activate without a separate decision:

```text
G7B store account/beta upload
feature-plugin runtime/registration expansion
MobileSAM / ONNX segmentation
real RAW development
Dart 3.13 RecordUse/native tree-shaking
DAM-style Workplaces expansion inside PixelCraft
```

Future MobileSAM should sit behind a replaceable mask-provider boundary and must not become image authority.

Future RAW requires a separate explicit milestone covering decode/demosaic, WB/color, highlight recovery, working color space, memory/performance, and authoritative replay/export.

---

# 13. Current next action

## Immediate

1. Require exact-head CI for PR #55 after PF4 typed Gallery routing and documentation sync.
2. Fix any formatter/analyzer/test failures before expanding the slice.
3. Complete PF4 processed export-to-Gallery failure/retry behavior without mutating the original source.
4. Add/adjust regression coverage for Gallery -> typed route -> Product Editor and export failure/retry.
5. Re-run exact-head CI and review threads.
6. Mark PR #55 ready only when PF4 behavior and docs are stable.

## After PF4

Proceed to PF5 foundation only if needed for explicit external edit request/result contracts. Do not activate real RAW, MobileSAM, Dart 3.13 RecordUse, or generic plugin runtime work as part of PF4.
