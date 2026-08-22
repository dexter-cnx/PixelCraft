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

Last refresh: **2026-08-22 — PF3 implementation and physical validation complete in PR #52; final documentation sync is the last pre-merge step.**

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

```text
Gallery
 -> choose source
 -> preserve original source untouched
 -> Product Editor
 -> Film / Filter / Adjust / transforms / masks
 -> Rust full-resolution render
 -> save processed result to Gallery / explicit destination
```

Gallery/external sources do not inherit CameraLook automatically.

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
PKG-03 camera package extraction review         NEXT AFTER PF3 MERGE / BEFORE OR ALONGSIDE PF4 AS APPROPRIATE

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
PF3 Capture-process-save-to-Gallery              VERIFIED IN PR #52 / READY TO MERGE
PF4 Gallery-to-editor source flow                NEXT PRODUCT SLICE
PF5 External edit request/result contract        PLANNED FOUNDATION ONLY

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

Implementation head before final docs-only sync:

```text
head: a57b967c62ee0cef2faeaa4ae5db1b8a272e5e9a
Pixel Craft CI #747: PASS
```

Codex review #4999877331 findings were all fixed, replied to, and resolved:

1. serialize background capture render transactions;
2. restore Android camera controls on renderer recreation;
3. keep formatter check mode read-only.

---

# 8. CI architecture and local validation

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

# 9. State, localization, services

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

# 10. Package graph

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

Camera package extraction should be evaluated after PF3 is merged/stable.

---

# 11. Deferred work

Do not activate without a separate decision:

```text
G7B store account/beta upload
MobileSAM / ONNX segmentation
real RAW development
Dart 3.13 RecordUse/native tree-shaking
DAM-style Workplaces expansion inside PixelCraft
```

Future MobileSAM should sit behind a replaceable mask-provider boundary and must not become image authority.

Future RAW requires a separate explicit milestone covering decode/demosaic, WB/color, highlight recovery, working color space, memory/performance, and authoritative replay/export.

---

# 12. Current next action

## Immediate

1. Final documentation sync (`PROJECT_HANDOFF`, `CODE_WALKTHROUGH`, `README`) — this commit set.
2. Require exact-head PR CI after docs sync.
3. Merge PR #52 when required checks are green.
4. Verify resulting `main` push CI.
5. Delete `feature/pf3-capture-process-save` after successful merge if no longer needed.

## After PF3 merge

Proceed to **PF4 — Gallery source -> Editor -> Gallery export/source-preservation completion**.

Before expanding PF4, evaluate PKG-03 camera package extraction only if PF3 contracts are now stable enough to justify the boundary; do not extract merely for organization.
