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

Last refresh: **2026-08-16. Product direction is now platform-adaptive: phone/tablet are camera-first; desktop is editor/drop-first. PixelCraft remains the photo-editing/image-processing product. Nixin/Dextryx Images remains the image-management product and may invoke PixelCraft through a future external-edit contract.**

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

## Future external-edit contract

Future direction:

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
5. Prefer a narrow request/result contract that can later be carried by deep link, Android intent, iOS share/open-in, desktop launch arguments, or another explicit transport.

---

# 3. Canonical platform product flow

## Phone and tablet — camera-first

Phone and tablet use the same core interaction model. Tablet layout may be adaptive, but the mental model remains camera-first.

Launch target:

```text
App launch
   ↓
Camera
```

Primary camera shell:

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
- bottom left = **Gallery** / source picker;
- bottom right = camera controls/settings surface;
- Film, Filter, and Adjust are available without leaving the camera;
- camera preview should update through the verified low-latency GPU path when faithful;
- unsupported GPU operations fall back safely rather than diverging from Rust semantics.

### Camera capture output

Capture flow target:

```text
clean camera capture
+ selected Film / Filter / Adjust recipe
        ↓
Rust authoritative full-resolution render
        ↓
JPEG output
        ↓
save to system Gallery
        ↓
remain in Camera
```

Hard rules:

1. camera capture remains clean internally; live preview pixels are never final-render authority;
2. camera result saved to Gallery is JPEG;
3. user should not be forced into the editor after every shutter press;
4. after save, the camera remains active and a recent thumbnail/confirmation may update;
5. tapping the recent thumbnail may enter the editor for further processing.

### Gallery/editor input

```text
Gallery
 -> choose source
 -> keep original source untouched
 -> Product Editor
 -> Film / Filter / Adjust / transforms / future masks
 -> Rust full-resolution render
 -> save processed result to Gallery
```

Source-format rule:

- original source is never rewritten merely because PixelCraft edits it;
- JPEG stays JPEG source, PNG stays PNG source, WebP stays WebP source, and a future RAW source remains RAW source;
- export format is a separate output decision from source preservation.

## Desktop — editor/drop-first

Desktop must **not** open into the mobile camera-first shell.

Launch target:

```text
App launch
   ↓
Editor launcher / drop surface
```

Primary desktop entry:

```text
Open Image / Drag & Drop
```

Secondary/future inputs may include:

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

Desktop panels should be collapsible; the application must remain an editor, not a DAM/library clone.

---

# 4. Architecture invariants

```text
Flutter   = UI / control / presentation plane
Rust      = authoritative image semantics / recipe / history / checkpoint / recovery / export
Metal     = iOS realtime GPU preview
OpenGL ES = Android realtime camera preview
```

Hard contracts:

1. Rust owns committed edits, recipe/history/checkpoint/recovery, and full-resolution render/export.
2. GPU rendering is preview-only and never final-render authority.
3. Camera Film/Filter/Adjust preview must not bake the live preview framebuffer into the authoritative source.
4. Live camera buffers never cross MethodChannel or Flutter Rust Bridge.
5. Canonical Film/Creative LUT data is Rust-owned.
6. Native/GPU failure fails closed to valid Rust/product state.
7. Unsupported Rust operation order falls back; never silently reorder for GPU.
8. Film Profiles are reusable configuration, not per-image pixels/sessions.
9. Imported recipe fields report exact / approximated / unsupported mappings.
10. New effects are Rust-first; GPU support is enabled only when faithful.
11. AI segmentation/restoration is optional capability and never committed-image authority.
12. Do not casually replace mobile Metal/OpenGL ES runtime with wgpu.
13. Editor-local workspace/catalog state is metadata/navigation state only and never authoritative edit/pixel state.
14. Recovery generations remain crash/session recovery and are not catalog identity.
15. Long-lived image-management ownership belongs to Nixin.
16. External-edit integration must use explicit request/result contracts rather than app-internal UI coupling.

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

PF1 Camera-first mobile/tablet shell             NEXT / NOT IMPLEMENTED
PF2 Unified Camera Film/Filter/Adjust UX         PLANNED
PF3 Capture-process-save-to-Gallery              PLANNED
PF4 Gallery-to-editor source flow                PLANNED
PF5 External edit request/result contract        PLANNED FOUNDATION ONLY

MobileSAM / ONNX segmentation                   FUTURE / NOT ACTIVATED
Real RAW development                            FUTURE / NOT ACTIVATED
O1 Dart 3.13 native tree-shaking / RecordUse    FUTURE / DEFERRED / DO NOT START NOW
```

Historical G7 PR #10 is closed/superseded. Do not reopen it.

---

# 6. Verified recent baseline

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

Verified W1 baseline before the product-flow pivot:

```text
PR #42 final head: 1218ec44d0d9938a89b7f7ab294b0a55a2f435b5
PR #42 PR CI: #362 / 31930004255 / success
PR #42 merge: a5d015587a9eab0125d8605f91fff9307e8d0c11
main CI after #42: #363 / 31930570158 / success
```

PR #43 is merged; do not infer resulting-main CI status unless exact evidence is available.

---

# 7. Existing implementation relevant to PF1-PF4

Current mobile runtime still boots Rust and then returns `HomeScreen`; PF1 will change this platform routing.

Existing camera foundation already provides:

- native GPU camera preview on supported iOS/Android paths;
- fallback Flutter `camera` flow;
- camera switch;
- Film preview and strength control;
- clean capture path;
- capture → editor handoff.

PF work should reuse this foundation rather than build a second camera stack.

Current capture behavior opens the editor after taking a picture. PF3 changes this product behavior to process/save JPEG to system Gallery and remain in camera.

Existing `WorkspaceCatalogStore` remains useful only for bounded continuity/reopen behavior. It must not become the primary launch experience or a DAM.

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

Current Film pack includes inspired looks such as Provia, Velvia, Astia, E100, Ektar, and Chrome 64.

Creative filters include grayscale/invert plus Rust-generated canonical LUT presets such as vintage, oceanic, lofi, dramatic, golden, and pastel pink.

PF2 is primarily a **camera product UX integration milestone**, not a reinvention of Film/Filter semantics.

---

# 9. Future segmentation and RAW

## MobileSAM / ONNX

Future package direction:

```text
dxtr_pixs_segment
```

Not activated yet. When activated it must be an optional local segmentation capability feeding masks into PixelCraft edit semantics. It must not become image authority.

## Real RAW development

Future package direction:

```text
dxtr_pixs_raw
```

Not activated yet. A real RAW milestone must separately define decoding/demosaic, camera color/WB, highlight recovery, working color space, full-resolution replay, memory/performance, and export behavior. Do not mix this into PF1-PF5.

---

# 10. Package graph and naming

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
dxtr_pixs_raw      future real RAW pipeline
```

Native/runtime identifiers intentionally remain stable unless separately justified.

---

# 11. Deferred work

## O1 — Dart 3.13 RecordUse / native tree-shaking

**FUTURE / DEFERRED / DO NOT START NOW.**

Detailed plan:

```text
docs/FUTURE_DART_3_13_NATIVE_TREE_SHAKING.md
```

## G7B

**DEFERRED INDEFINITELY / NOT SCHEDULED.**

Neither O1 nor G7B blocks PF1-PF5.

---

# 12. Reliability / device evidence

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

# 13. Release baseline

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

# 14. Verification rules

1. Never claim CI/test/device/build/store validation passed unless actually run or explicitly reported.
2. Never commit signing secrets, certificates, provisioning profiles, passwords, or store credentials.
3. Never ship Android production artifacts with debug signing.
4. Do not weaken Rust authority, GPU fail-closed behavior, or package boundaries.
5. A PR being green is not enough to declare a slice complete; verify resulting `main` push CI after merge.
6. Do not import Nixin roadmap items into PixelCraft; implement only the external-edit boundary explicitly approved here.
7. Do not bind Nixin to PixelCraft app-internal UI classes.
8. Mobile/tablet camera-first and desktop editor-first are product policies; do not collapse them into one generic Home UI.
9. Camera live preview pixels are never final-render authority.
10. Camera captures saved by the new PF flow are JPEG outputs generated through the authoritative processing path.
11. Gallery/external source inputs remain untouched; output is separate.
12. Do not start MobileSAM, real RAW, O1, or G7B as part of PF1-PF5 unless explicitly activated.

Standard verification:

```text
bash tool/check_package_boundaries.sh
make gpu-lut-verify
make verify-native
flutter analyze
flutter test
```

---

# 15. Current next action

Implement **PF1 — Camera-first mobile/tablet shell** first.

Required first slice:

1. introduce platform-adaptive root routing after Rust bootstrap;
2. phone/tablet launch directly into the existing camera foundation;
3. desktop launches an editor/open/drop-oriented surface rather than the mobile camera shell;
4. mobile/tablet camera bottom hierarchy becomes Gallery / Shutter / Controls;
5. expose Film / Filter / Adjust as camera-context controls without creating a second processing authority;
6. preserve current verified GPU/Rust contracts and camera permission/lifecycle hardening;
7. do not yet start MobileSAM, real RAW, O1, G7B, or Nixin DAM work;
8. update `docs/CODE_WALKTHROUGH.md`, `README.md`, tests, and this handoff as PF implementation lands.

Then proceed in order:

```text
PF1 camera-first platform shell
 -> PF2 unified camera Film/Filter/Adjust UX
 -> PF3 capture + authoritative render + JPEG Gallery save + remain in camera
 -> PF4 Gallery source -> editor -> Gallery export
 -> PF5 versioned external edit request/result foundation for future Nixin integration
```
