# PixelCraft Project Handoff

## Purpose

This is the canonical continuation document for the PixelCraft repository and the **Dextryx Pixels** product.

When starting a new work session:

1. read this file first;
2. inspect `main`, the active PR, and its latest CI run;
3. continue from **Current next action**;
4. treat repository state and recorded CI/device evidence as authoritative over older chat history.

Recommended continuation prompt:

```text
อ่าน docs/PROJECT_HANDOFF.md ใน repo PixelCraft แล้วทำต่อจาก Current next action
```

Last refresh: **2026-08-15, PKG-01 `dxtr_pixs_*` package namespace migration is the active highest-priority workstream; G7B remains deferred indefinitely**.

---

# 1. Product identity — COMPLETE

Identity decision frozen on 2026-08-15:

```text
master brand: Dextryx
product name: Dextryx Pixels
installed app label: Dxtr Pixs
short visual mark: DXTR PIXS or DXTR + pixel/film symbol
technical package family: dxtr_pixs_*
repository name: PixelCraft (unchanged)
```

Migration rules:

1. Product-facing copy uses **Dextryx Pixels**.
2. Android/iOS launcher or home-screen display labels use **Dxtr Pixs**.
3. Privacy/permission copy uses **Dextryx Pixels**.
4. Historical evidence may retain `PixelCraft` / `Pixel Craft` when that was the literal build/product name at that time.
5. Android applicationId and iOS bundle id remain `dev.cnxdev.pixelcraft` until a deliberate identifier migration is approved and validated.
6. Do not rename the GitHub repository as part of the identity migration.
7. Technical/runtime storage names, native channels, persisted schema names, Rust crate/library names, and ABI names remain unchanged unless a separate migration is justified.
8. **Flutter/Dart reusable packages are the exception:** PKG-01 deliberately migrates the existing `pixelcraft_*` package family to `dxtr_pixs_*` before new packages are added.

Identity PR:

```text
PR #27: Rename product identity to Dextryx Pixels
branch: feature/dextryx-pixels-identity
HEAD: 494649b7bea9c12a9b6141cdb3d810596bd67bff
CI: run #267 / 31853404031 — SUCCESS
merge commit: 5f4ea1e3ba0b2e7e9983eb096109742ead0b1ea9
```

The product identity workstream is complete at the user-facing copy level. A future applicationId/bundle-id migration remains a separate explicit release task.

---

# 2. Architecture invariants

```text
Flutter   = UI / control / presentation plane
Rust      = authoritative image semantics / recipe / history / checkpoint / recovery / export
Metal     = iOS realtime GPU preview
OpenGL ES = Android realtime camera preview
```

Hard contracts:

1. Rust owns committed edit semantics, history, checkpoints, recovery recipe, and full-resolution export.
2. GPU rendering is interactive preview only; never final-render authority.
3. Camera Film is preview-only; capture remains clean.
4. Live camera buffers never cross Dart MethodChannel or Flutter Rust Bridge.
5. Canonical Film/Creative LUT data is Rust-owned.
6. Native/GPU failure fails closed to valid Rust/product state.
7. Unsupported Rust operation order falls back; never silently reorder operations for GPU.
8. Film Profiles are reusable configuration, not pixels or per-image sessions.
9. Imported recipe fields report exact / approximated / unsupported mappings.
10. New effects are defined/tested in Rust first; GPU support is enabled only when faithful.
11. AI segmentation/restoration packages must remain optional capability layers and must not silently become committed-image authority.

---

# 3. Milestone status

```text
G1  Camera GPU Preview                          CLOSED
G2  Editor GPU Preview Foundation               CLOSED / MERGED
G3  Production Rendering Pipeline               CLOSED / MERGED
G4  Product Editor UX / Session Workflow        CLOSED / MERGED
G5  Editing Feature Completeness                CLOSED / VERIFIED
G6  Reliability / Performance / Device Matrix   CLOSED / VERIFIED

P0  pixelcraft_engine extraction                MERGED
P1  pixelcraft_gpu extraction                   MERGED
P2  pixelcraft_editing extraction               MERGED
P3  pixelcraft_film extraction                  MERGED

PKG-01 dxtr_pixs_* namespace consolidation      ACTIVE / PR #30

G7A Release Engineering / Store Preparation     MERGED
G7B Store Account Integration / Beta Upload     DEFERRED INDEFINITELY / NOT SCHEDULED

Post-G7A Product / Editor UX                     ACTIVE AFTER PKG-01
Dextryx Pixels identity                         COMPLETE
```

Historical G7 PR #10 is closed/superseded. Do not reopen or merge it.

---

# 4. Post-G7A product/editor work

Merged slices:

```text
PR #20  Editor: discoverable Before/After Compare UX
PR #21  Film library: search and origin filters
PR #22  Fix Compare session state and wide-layout placement
PR #23  Editor: discoverable Zoom / Fit controls
PR #24  Editor: precise numeric value entry for adjustment sliders
PR #25  Editor: histogram channel inspector
PR #26  Editor: precise straighten angle entry
PR #27  Product identity: Dextryx Pixels / Dxtr Pixs
```

These slices are presentation/product workflow improvements. They do not transfer committed image authority away from Rust and do not make GPU preview authoritative.

---

# 5. Package graph and naming policy

## 5.1 PKG-01 target

The existing reusable package family is being normalized before MobileSAM, restoration, or RAW package work begins:

```text
packages/pixelcraft_editing  -> packages/dxtr_pixs_editing
packages/pixelcraft_engine   -> packages/dxtr_pixs_engine
packages/pixelcraft_film     -> packages/dxtr_pixs_film
packages/pixelcraft_gpu      -> packages/dxtr_pixs_gpu
```

Target graph:

```text
PixelCraft repository app
 ├── dxtr_pixs_film
 ├── dxtr_pixs_gpu
 ├── dxtr_pixs_editing
 └── dxtr_pixs_engine

dxtr_pixs_film    -> dxtr_pixs_editing
dxtr_pixs_gpu     -> dxtr_pixs_editing
dxtr_pixs_editing -> Dart SDK only
dxtr_pixs_engine  -> repository rust/ crate through build integration
```

CI guard:

```text
tool/check_package_boundaries.sh
```

The guard must reject reintroduction of legacy Dart package URIs:

```text
package:pixelcraft_editing/
package:pixelcraft_film/
package:pixelcraft_gpu/
package:pixelcraft_engine/
```

## 5.2 Scope boundary

PKG-01 changes Flutter/Dart package identity and matching Flutter plugin packaging metadata only.

Do **not** casually rename these as part of PKG-01:

```text
Rust crate: pixelcraft_engine
native library: libpixelcraft_engine.*
GPU native library: libpixelcraft_gpu_native.*
MethodChannel/native protocol identifiers
persistent storage/schema names
applicationId / bundle id
```

Those are ABI/runtime/release migrations and require their own justification and validation.

## 5.3 Future package family

New reusable imaging packages must start with the same family prefix from day one:

```text
dxtr_pixs_segment  MobileSAM ONNX / local segmentation
dxtr_pixs_restore  Face Enhance / AI Denoise / Super-Resolution
dxtr_pixs_raw      future real RAW pipeline only if a clean package boundary is proven
dxtr_pixs_core     future shared types only when concrete reuse justifies extraction
```

Avoid creating empty packages merely to satisfy an architectural diagram.

---

# 6. Advanced Develop / AI roadmap

Advanced Develop is a future workstream after package namespace consolidation and the currently prioritized product UX work.

Separate ordinary continuous adjustments from expensive AI reconstruction operations.

```text
Advanced Develop
├── conventional / RAW development
└── AI Restoration
    ├── Face Enhance
    ├── AI Denoise
    └── Super-Resolution
```

Planned package boundaries:

### `dxtr_pixs_segment`

First backend: MobileSAM through ONNX Runtime.

Responsibilities:

- local/offline segmentation inference;
- image encoder + prompt/mask decoder boundary;
- prepared-image / embedding cache;
- point prompts first;
- negative point / box prompt / mask refinement later;
- async inference and stale-result prevention;
- model/backend details remain behind a model-agnostic public API.

This package must not know about PixelCraft UI, editor panels, Film Profiles, or RAW development semantics.

### `dxtr_pixs_restore`

Planned capability families:

```text
Super-Resolution  first candidate: Real-ESRGAN
AI Denoise        benchmark Restormer / SCUNet before freezing backend
Face Enhance      first candidate: GFPGAN
```

Restoration operations consume rendered RGB image data and should not depend directly on the future RAW engine. They are explicit asynchronous operations with progress/cancel and Before/After, not per-frame slider effects.

CodeFormer is not the default production candidate while its upstream commercial-use licensing remains unsuitable without explicit permission.

---

# 7. G7A / G7B split

G7A is complete and merged. It covered account-independent release work: signing architecture, unsigned/no-codesign packaging, native Rust/LUT verification, version/build identity audit, privacy/permission audit, store metadata/privacy drafts, release notes/RC QA preparation, and CI release artifact generation.

G7B remains defined but is **deferred indefinitely and not scheduled**. Do not treat G7B as an active blocker for product/editor development, and do not pause current work waiting for store accounts.

Resume G7B only after an explicit project decision.

---

# 8. Release engineering baseline

Android release rules:

- release must not use debug signing;
- signing secrets remain outside git;
- CAMERA remains;
- WRITE_EXTERNAL_STORAGE is limited through API 28;
- dependency RECORD_AUDIO is explicitly removed;
- fallback Flutter camera is still-photo only with `enableAudio: false`.

CI release jobs build Android release APK and iOS release `--no-codesign`, verify Rust/native artifacts and Film/Creative LUT assets, and upload artifacts.

---

# 9. Verified release evidence

Final G7A PR validation:

```text
GitHub Actions run: #221
run id: 31611799174
HEAD: d5e0aab14a0ae9a5b8124a0b37fef78249cbbeb5
conclusion: SUCCESS
```

Post-G7A known green evidence includes:

```text
PR #26: run #266 / 31853058185 — SUCCESS
PR #27: run #267 / 31853404031 — SUCCESS
```

Do not treat PKG-01 as green until PR #30 CI completes successfully after all namespace/native packaging fixes.

---

# 10. Release identity / RC policy

Current identity:

```text
brand: Dextryx
product: Dextryx Pixels
app display label: Dxtr Pixs
marketing version: 0.1.0 while pre-1.0 beta/RC work continues
current build: 1
Android applicationId: dev.cnxdev.pixelcraft
iOS bundle id: dev.cnxdev.pixelcraft
iOS deployment target: 13.0
Android min/target/compile SDK: 24 / 36 / 36
```

A later bundle/application identifier migration must be handled as a deliberate release migration and must not be mixed into PKG-01.

---

# 11. Verification rules

1. Never claim CI/test/device/build/store validation passed unless actually run or explicitly reported.
2. Never commit keystores, passwords, private certificates, provisioning profiles, or store credentials.
3. Never ship Android production artifacts with debug signing.
4. Release engineering must not weaken Rust authority, GPU fail-closed behavior, or package boundaries.
5. G7B is deferred indefinitely and must not be resumed without an explicit project decision.
6. Product renaming must not rewrite historical evidence as if old builds used the new identity.
7. Bundle/application identifier changes require an explicit migration decision separate from package naming.
8. PKG-01 is complete only when root dependencies, package-to-package imports, tests, CI working directories, package-boundary guards, and Apple plugin podspec discovery all use `dxtr_pixs_*` consistently.
9. Native Rust/ABI names remain unchanged in PKG-01 unless CI proves a technically unavoidable dependency.
10. Future `dxtr_pixs_segment` / `dxtr_pixs_restore` work must land in separate reviewable PRs after PKG-01.

---

# 12. Current next action

**PKG-01 package namespace consolidation is the highest-priority active task and must finish before new AI packages or broader Advanced Develop work.**

Current PR stack:

```text
PR #29  branding cleanup
   ↓
PR #30  PKG-01 dxtr_pixs package namespace migration
```

PR #30 is intentionally stacked on PR #29 while branding cleanup is unmerged. After PR #29 merges, retarget PR #30 to `main` and rerun the complete CI gate.

PKG-01 completion checklist:

```text
[ ] all four package directories use dxtr_pixs_* names
[ ] all four pubspec package names use dxtr_pixs_*
[ ] root path dependencies use dxtr_pixs_*
[ ] package-to-package Dart imports use dxtr_pixs_*
[ ] root app forwarding imports/exports use dxtr_pixs_*
[ ] package tests use dxtr_pixs_*
[ ] CI package paths use dxtr_pixs_*
[ ] package-boundary guard rejects legacy pixelcraft_* Dart package URIs
[ ] iOS/macOS podspec filenames and pod names match dxtr_pixs_* Flutter plugin names
[ ] native Rust/ABI library names remain stable
[ ] full PR #30 CI passes
```

After PKG-01 is merged, continue in this order:

```text
1. modern Product / Editor UX improvements as small reviewable slices
2. dxtr_pixs_segment — MobileSAM ONNX foundation
3. Advanced Develop foundation
4. dxtr_pixs_restore — Super-Resolution, AI Denoise, Face Enhance
5. real RAW development / dxtr_pixs_raw only when its package boundary is justified
6. G7B remains deferred until explicitly resumed
```

Do not begin `dxtr_pixs_segment`, `dxtr_pixs_restore`, or RAW package implementation while PKG-01 remains red/incomplete.
