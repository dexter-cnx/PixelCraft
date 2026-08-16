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

Last refresh: **2026-08-16. UX-01 and the first UX-02 workspace modernization slice are merged and verified on main. PR #39 is the active UX-02 real-recent-edit slice. G7B and Dart 3.13 native tree-shaking remain deferred.**

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
- historical evidence may retain the name that existed when it was produced;
- native ABI/runtime identifiers and persisted schema names are not branding concerns.

---

# 2. Architecture invariants

```text
Flutter   = UI / control / presentation plane
Rust      = authoritative image semantics / recipe / history / checkpoint / recovery / export
Metal     = iOS realtime GPU preview
OpenGL ES = Android realtime camera preview
```

Hard contracts:

1. Rust owns committed edits, recipe/history/checkpoint/recovery, and full-resolution export.
2. GPU rendering is preview-only and never final-render authority.
3. Camera Film is preview-only; capture remains clean.
4. Live camera buffers never cross MethodChannel or Flutter Rust Bridge.
5. Canonical Film/Creative LUT data is Rust-owned.
6. Native/GPU failure fails closed to valid Rust/product state.
7. Unsupported Rust operation order falls back; never silently reorder for GPU.
8. Film Profiles are reusable configuration, not per-image pixels/sessions.
9. Imported recipe fields report exact / approximated / unsupported mappings.
10. New effects are Rust-first; GPU support is enabled only when faithful.
11. AI segmentation/restoration is optional capability and never committed-image authority.
12. Do not casually replace mobile Metal/OpenGL ES runtime with wgpu.

---

# 3. Milestone status

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

Post-G7A Product / Editor UX                    ACTIVE
UX-01 Modern import/add-photo entry flow        CLOSED / VERIFIED
UX-02 Home / Workspace modernization            ACTIVE
O1 Dart 3.13 native tree-shaking / RecordUse   FUTURE / DEFERRED / DO NOT START NOW
```

Historical G7 PR #10 is closed/superseded. Do not reopen it.

---

# 4. Recent merged product work

```text
PR #20  discoverable Before/After Compare
PR #21  Film library search/origin filters
PR #22  Compare session/wide-layout fix
PR #23  discoverable Zoom / Fit controls
PR #24  precise numeric adjustment entry
PR #25  histogram channel inspector
PR #26  precise straighten angle entry
PR #27  Dextryx Pixels / Dxtr Pixs identity
PR #30  dxtr_pixs_* reusable package namespace
PR #32  post-namespace branding tests/golden repair
PR #33  roadmap refresh + deferred Dart 3.13 native tree-shaking plan
PR #36  replace broken Home PNG golden with structural regression gate
PR #37  direct primary Import acquisition path
PR #38  Home workspace modernization; remove demo/sample hierarchy
```

Verification evidence:

```text
PR #37 merge: eda3a04e44147d5d8e6e2edb7d8760a92a9ec340
main CI after #37: #337 / 31897159986 / success

PR #38 merge: 4c35eeaeaeadb0334394509b03bc194393720691
PR #38 final head CI: #340 / 31898608876 / success
main CI after #38: #341 / 31899235126 / success
```

PR hygiene/history:

```text
PR #29 closed, superseded by #30/#32
PR #31 closed, superseded by #33
PR #34 merged but did not repair corrupt Home PNG golden
PR #35 closed without merge; bootstrap approach abandoned
PR #36 merged; structural Home regression replaced broken binary gate
```

Home regression policy:

- Home uses structural/behavior regression rather than the old corrupt PNG baseline.
- editor goldens continue pixel comparison.
- do not reintroduce binary/base64 bootstrap workarounds for the old Home golden.

---

# 5. Product / Editor UX

## UX-01 — Modern acquisition — CLOSED / VERIFIED

Normal path:

```text
Import -> gallery/platform image picker directly
```

Secondary progressive disclosure:

```text
More ways to add
 ├── Film Camera
 └── Take Photo

Films remains separate.
```

Verified through PR #37 and resulting main CI #337.

## UX-02 — Home / Workspace modernization — ACTIVE

Completed slice via PR #38:

- removed permanent sample-photo grid;
- removed demo/marketing/implementation explanatory copy;
- retained real empty workspace state;
- retained deterministic recovery/resume behavior;
- retained Import as primary action;
- no fake recent/catalog data.

Active slice via PR #39:

```text
branch: feature/ux02-workspace-recents
PR: #39
base: main @ 4c35eeaeaeadb0334394509b03bc194393720691
```

Goal:

- promote the existing persisted `EditorSessionStore` recovery generation into a real `Recent edit` workspace item;
- thumbnail comes from stored `originalBytes`;
- timestamp comes from stored `savedAt`;
- Resume / Discard behavior remains unchanged;
- do not invent recent images or a catalog persistence model in this slice.

Design direction:

- image first;
- direct manipulation;
- progressive disclosure;
- continuous preview only where architecture safely supports it;
- micro motion ~80-120 ms, fast 140-180 ms, standard 200-260 ms, spatial 280-360 ms;
- perceived direct-control latency target below roughly 100 ms;
- compact precision controls with large invisible hit areas;
- avoid excessive glass, blur, gradients, bounce, and oversized cards.

---

# 6. Package graph and naming

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

Boundary guard:

```text
tool/check_package_boundaries.sh
```

Legacy Dart package URIs must not return:

```text
package:pixelcraft_editing/
package:pixelcraft_engine/
package:pixelcraft_film/
package:pixelcraft_gpu/
```

Native/runtime identifiers intentionally remain stable:

```text
Rust crate: pixelcraft_engine
native library: libpixelcraft_engine.*
GPU native library: libpixelcraft_gpu_native.*
MethodChannel/native protocol identifiers
persisted storage/schema identifiers
applicationId / bundle id
```

Future package family:

```text
dxtr_pixs_segment  MobileSAM/local segmentation
dxtr_pixs_restore  restoration capabilities
dxtr_pixs_raw      future real RAW pipeline only if a clean boundary is proven
```

---

# 7. Future O1 — Dart 3.13 RecordUse / native tree-shaking

**FUTURE / DEFERRED / DO NOT START NOW.**

Detailed plan:

```text
docs/FUTURE_DART_3_13_NATIVE_TREE_SHAKING.md
```

Do not change the Dart SDK constraint, Flutter baseline, Flutter Rust Bridge integration, native build pipeline, Rust ABI, or release packaging merely to start O1. Adoption requires measured before/after binary evidence.

---

# 8. G7B

G7B is **deferred indefinitely / not scheduled**. Do not treat it as a blocker and do not resume it without an explicit project decision.

---

# 9. Reliability / device evidence

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

# 10. Release baseline

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

# 11. Verification rules

1. Never claim CI/test/device/build/store validation passed unless actually run or explicitly reported.
2. Never commit signing secrets, certificates, provisioning profiles, passwords, or store credentials.
3. Never ship Android production artifacts with debug signing.
4. Do not weaken Rust authority, GPU fail-closed behavior, or package boundaries.
5. G7B remains deferred until explicitly resumed.
6. Bundle/application identifier migration is separate from UX work.
7. Native Rust/ABI names remain stable unless separately justified and validated.
8. O1 / RecordUse is future/deferred and must not start without explicit activation.
9. Do not claim a remote branch is deleted unless GitHub confirms the ref no longer exists.
10. A PR being green is not enough to declare a slice complete; verify resulting `main` push CI after merge.

Standard verification:

```text
bash tool/check_package_boundaries.sh
make gpu-lut-verify
make verify-native
flutter analyze
flutter test
```

---

# 12. Current next action

**Finish UX-02 real recent-edit hierarchy on PR #39 / `feature/ux02-workspace-recents`.**

Required sequence:

```text
1. validate thumbnail/timestamp rendering from the real persisted recovery generation
2. preserve Resume / Discard semantics
3. keep empty workspace behavior unchanged when no session exists
4. run full PR CI
5. address all review threads
6. merge only when final head is green
7. verify resulting main push CI is fully green
8. then choose the next UX-02 slice based on real persisted user data; do not fake a catalog
```

Do not start O1, G7B, MobileSAM, or restoration during this sequence.
