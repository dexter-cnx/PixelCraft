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

Last refresh: **2026-08-24 — PF4 merged in PR #55; PF5 external-edit contract merged in PR #56.**

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

External edit integration is now defined by PF5 as an explicit versioned request/result contract. Nixin keeps asset/catalog authority; PixelCraft/Rust keeps edit/pixel authority.

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

Current shell:

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

### Camera capture — PF3

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
3. camera output is JPEG for the implemented PF3 path;
4. Shutter does not force Editor navigation;
5. Camera remains active after save;
6. permission prompts do not interrupt an active shutter -> process -> save transaction.

### Gallery/editor — PF4

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
- RAW/HEIF identities may be represented without activating deferred RAW development;
- processed-export Gallery retry reuses the committed backup and does not rerender or mutate the original.

### External edit — PF5 foundation

```text
Nixin / external catalog
 -> ExternalEditRequestV1
    - requestId
    - caller-owned catalogAssetId
    - MediaSourceDescriptor(externalEdit)
    - optional preferred output MIME
 -> PixelCraft transport boundary (transport not implemented yet)
 -> edit/render under PixelCraft/Rust authority
 -> ExternalEditResultV1
    - completed + ExternalEditOutputV1
    - cancelled
    - failed + stable failureCode
```

PF5 is **transport-neutral foundation only**. It does not add deep links, app-to-app transport, catalog mutation, RAW decode, MobileSAM, or a generic plugin runtime.

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
9. External-edit integration uses explicit versioned request/result contracts.
10. Do not casually replace mobile Metal/OpenGL ES runtime with wgpu.
11. External catalog identity is caller-owned; PixelCraft must not invent or reinterpret it.
12. Optional authoritative recipe payloads returned externally are PixelCraft/Rust-authored and opaque to callers.

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

PF0 Platform-flow foundations                   MERGED (#50)
PF1 Camera-first mobile/tablet shell             IMPLEMENTED
PF2 Unified Camera Film/Filter/Adjust UX         IMPLEMENTED
PF3 Capture-process-save-to-Gallery              MERGED (#52)
PF4 Gallery-to-editor source flow                MERGED (#55)
PF5 External edit request/result contract        MERGED (#56)

Plugin-oriented feature architecture            FUTURE / PLANNED / DO NOT ACTIVATE YET
MobileSAM / ONNX segmentation                   FUTURE / NOT ACTIVATED
Real RAW development                            FUTURE / NOT ACTIVATED
O1 Dart 3.13 native tree-shaking / RecordUse    FUTURE / DEFERRED / DO NOT START NOW
```

---

# 6. PF3 validation evidence

Physical-device validation completed successfully on Android and iPhone.

Validated behavior includes Android/iPhone live Film/Filter preview, first-run Greeting + permissions, neutral/composed capture -> process -> save, Camera status feedback, Gallery -> Editor regression smoke, Camera Controls Close, Composition Guide behavior/persistence, and temporary-source Retry where practical.

PF3 merged by PR #52 on 2026-08-22.

```text
main merge: a203cc6202c1a202526294def5b8fe209ca416cd
implementation head: a57b967c62ee0cef2faeaa4ae5db1b8a272e5e9a
Pixel Craft CI #747: PASS
```

Composition guide implementation:

```text
lib/camera/camera_composition_guide.dart
thirds / goldenRatio / goldenSpiral
persistent White / Black / Red / Yellow / Green / Cyan guide colors
```

Golden Spiral is procedurally rendered with Flutter `CustomPainter`/`Path`; guides are overlay-only and never affect saved pixels.

---

# 7. PF4 closure evidence

PF4 merged by PR #55.

```text
final exact head: fe2e14cad1c8b2b21843f19524b5068837ec4720
merge commit:     29a256665f56b494aa6c7085070699420c48948f
Pixel Craft CI #773: PASS
```

Important files:

```text
lib/app/editor_source_contract.dart
lib/app/app_routes.dart
lib/ui/screens/camera_film_preview_screen.dart
lib/core/export_file_service.dart
```

PF4 establishes typed Gallery/editor source identity and preserves provenance/MIME/external identity/format identity. `EditorSource.inheritsCameraLook` is false.

Production processed-export retry was hardened before merge: a committed backup is created first, automatic Gallery save retries are bounded, and explicit Retry Gallery reads the backup instead of rerendering or touching the original source.

Review blocker around exposing Retry Gallery from production UI was fixed and resolved before merge.

PKG-03 camera extraction remains audited/deferred; do not extract camera merely for organization.

---

# 8. PF5 closure evidence

PF5 merged by PR #56 on 2026-08-24 local project date.

```text
final exact head: 69e317b4cb153f09c3a926d6aab6964ca9fd410d
merge commit:     8df08f090c6d2e001526004ef15c9ae652b6a471
Pixel Craft CI #781: PASS
```

Important files:

```text
lib/app/external_edit_contract.dart
test/app/external_edit_contract_test.dart
docs/PF5_EXTERNAL_EDIT_CONTRACT.md
```

PF5 contract V1 includes:

- `ExternalEditRequestV1` with version, request correlation, caller-owned `catalogAssetId`, explicit `externalEdit` provenance, source URI/MIME/provider identity, and optional output MIME preference;
- `ExternalEditOutputV1` with absolute/schemed URI, non-empty MIME, optional suggested filename, and optional PixelCraft/Rust authoritative recipe JSON;
- `ExternalEditResultV1` with explicit completed/cancelled/failed status and stable `failureCode` for failures;
- fail-closed unsupported version/status/provenance/malformed payload behavior;
- release-safe outbound validation so objects emitted locally also satisfy decoder invariants.

Codex review reported three P2 producer/consumer symmetry gaps. All were fixed, regression-tested, replied to, and resolved before merge:

1. enforce `externalEdit` provenance on constructed requests;
2. reject empty/whitespace output MIME on construction;
3. reject empty/whitespace failure code on failed-result construction.

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

Formatting policy: run canonical Dart formatting before pushes that touch Dart. `dart-format-check` is read-only and should fail with a canonical diff rather than modify developer files.

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

Future feature-plugin architecture is capability/provider based rather than a dynamic arbitrary-code loader. Optional features should depend on stable app/domain contracts, register capabilities explicitly, and remain replaceable without becoming image authority. Candidate future features such as MobileSAM should sit behind those boundaries.

---

# 12. Deferred work

Do not activate without a separate decision:

```text
G7B store account/beta upload
external-edit app-to-app/deep-link transport
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

## Immediate — PF5 closure sync

1. Merge this documentation sync after exact-head docs-only CI.
2. Keep `PROJECT_HANDOFF.md`, `CODE_WALKTHROUGH.md`, and `PF5_EXTERNAL_EDIT_CONTRACT.md` aligned with merged PF4/PF5 behavior.
3. Remove stale PF4/PF5 in-progress wording from canonical docs.
4. Do not activate transport, RAW, MobileSAM, Dart 3.13 RecordUse, or generic plugin runtime as part of this closure slice.

## Next product slice after closure

Run a focused **post-PF5 gap audit** against the current camera/editor UX and service boundaries. Prefer concrete user-visible or reliability gaps over speculative architecture. Candidate work should be selected only after the audit and should preserve the established camera-first mobile/tablet flow, typed source contracts, Rust authority, and Nixin catalog boundary.
