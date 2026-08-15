# PixelCraft Project Handoff

## Purpose

This is the canonical continuation document for repository **PixelCraft** and product **Dextryx Pixels**.

For a new session:

1. read this file first;
2. inspect `main`, active PRs, review threads, and latest CI;
3. continue from **Current next action**;
4. treat repository state and recorded CI/device evidence as authoritative over older chat history.

Recommended continuation prompt:

```text
อ่าน docs/PROJECT_HANDOFF.md ใน repo PixelCraft แล้วทำต่อจาก Current next action
```

Last refresh: **2026-08-15, after PR #36 repaired the Home regression gate and main CI run 31895567304 passed. UX-01 direct import is now active on `feature/ux01-direct-import`. G7B and Dart 3.13 native tree-shaking remain deferred.**

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
- historical evidence may retain the product name that existed when the evidence was produced;
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
11. AI segmentation/restoration remains an optional capability layer and does not become committed-image authority.
12. Do not casually replace the mobile runtime with wgpu. Cross-platform wgpu CI may exist, but mobile runtime stays Metal/OpenGL ES unless deliberately redesigned.

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
UX-01 Modern import/add-photo entry flow        IMPLEMENTATION ACTIVE
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
```

PR hygiene/history:

```text
PR #29  closed, superseded by #30/#32
PR #31  closed, superseded by #33
PR #34  merged but did not repair the corrupt Home PNG golden
PR #35  closed without merge; text/base64 bootstrap approach abandoned
PR #36  merged; structural Home regression replaced the broken binary gate
```

## 4.1 Golden incident closure

The persistent macOS `home_phone.png` codec failure is closed.

Authoritative evidence:

```text
PR #36 head CI: success
main merge SHA: fba1f6454c28f0e5d15a92c9a94a68e6df5e64d2
main push CI: 31895567304
main push conclusion: success
Golden tests (macOS): success
```

Policy going forward:

- Home uses a structural/behavior regression test rather than the corrupted PNG baseline.
- The remaining editor goldens continue pixel comparison.
- Do not reintroduce binary/base64 bootstrap workarounds for the old Home golden.
- Any future Home visual golden must be introduced intentionally from a verified local/CI baseline, not as part of UX-01.

---

# 5. UX-01 — Modern import/add-photo entry flow

## Problem being replaced

```text
primary Add Photo
 -> implementation-oriented three-choice source menu
 -> user chooses source/mode
 -> actual image task begins
```

## Target normal path

```text
primary Import
 -> directly invoke the gallery/platform image picker
```

The primary action **must not** open the old three-choice source menu.

Secondary acquisition remains available through progressive disclosure:

```text
More ways to add
 ├── Film Camera
 └── Take Photo

Films remains a separate Film Profiles/library entry.
```

Current implementation branch:

```text
feature/ux01-direct-import
base: main @ fba1f6454c28f0e5d15a92c9a94a68e6df5e64d2
```

Current implementation decisions:

- primary FAB is `Import`;
- primary Import calls `ImageSource.gallery` directly;
- secondary app-bar popup exposes Film Camera and system camera;
- production still uses `ImagePicker`;
- a narrow picker injection seam exists only to make acquisition-flow widget tests deterministic;
- no Rust image semantics, package boundary, ABI, channel, applicationId, or bundle id changes;
- no Home PNG golden is added in UX-01.

UX-01 stabilization criteria:

```text
[ ] primary Import does not open the old source menu
[ ] primary Import calls gallery picker directly
[ ] Film Camera remains reachable through secondary disclosure
[ ] system camera remains reachable through secondary disclosure
[ ] focused widget tests verify gallery/camera source selection
[ ] Home structural regression reflects the new Import affordance
[ ] no regression to editor/camera semantic commit paths
[ ] no expensive synchronous work is introduced on the tap path
[ ] flutter analyze passes
[ ] flutter test passes
[ ] full PR CI passes
[ ] no unresolved review thread remains
[ ] UX-01 merges to main
[ ] resulting main push CI passes before UX-01 is declared complete
```

Design direction for subsequent UX slices:

- image first;
- direct manipulation;
- progressive disclosure;
- continuous preview where architecture safely supports it;
- micro motion ~80-120 ms, fast 140-180 ms, standard 200-260 ms, spatial 280-360 ms;
- perceived direct-control latency target below roughly 100 ms;
- compact precision controls with large invisible hit areas;
- avoid excessive glass, blur, gradients, bounce, and oversized cards.

Likely next UX slice after UX-01:

```text
UX-02 Home / Workspace modernization
- replace demo/test-app feel
- reduce onboarding/explanatory chrome
- make recent edits/images/import the primary workspace hierarchy
- retain deterministic recovery/resume behavior
```

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

**Status: FUTURE / DEFERRED / DO NOT START NOW.**

O1 is an evidence-driven binary-size/build optimization and must not interrupt Product / Editor UX work.

Do not change the Dart SDK constraint, Flutter baseline, Flutter Rust Bridge integration, native build pipeline, Rust ABI, or release packaging merely to start O1.

Detailed future plan:

```text
docs/FUTURE_DART_3_13_NATIVE_TREE_SHAKING.md
```

Future activation order only after an explicit project decision:

```text
FNT-0 Toolchain gate
FNT-1 Native size baseline
FNT-2 Binding/API and linker audit
FNT-3 Optional desktop GPU mechanics PoC
FNT-4 Mobile engine feasibility PoC
FNT-5 Linker/LTO verification
FNT-6 Before/after evidence
FNT-7 Adopt / limited-adopt / defer / reject decision
```

Guards:

1. preserve native symbols if usage information is unavailable or ambiguous;
2. do not remove Flutter Rust Bridge merely to enable RecordUse;
3. desktop GPU work must not replace mobile engine evaluation;
4. Rust authority and deterministic export remain unchanged;
5. no adoption without measured before/after binary evidence.

---

# 8. G7B

G7B is **deferred indefinitely / not scheduled**.

Do not treat it as a blocker and do not resume it without an explicit project decision.

---

# 9. Reliability / device evidence

G6 is closed/verified.

```text
main app id: dev.cnxdev.pixelcraft
DO NOT uninstall or overwrite the installed main app during verifier runs
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
10. A PR being green is not enough to declare a repair complete; verify the resulting `main` push CI after merge.

Standard verification entry points:

```text
bash tool/check_package_boundaries.sh
make gpu-lut-verify
make verify-native
flutter analyze
flutter test
```

---

# 12. Current next action

**Finish UX-01 on `feature/ux01-direct-import`.**

Required sequence:

```text
1. validate the direct Import implementation
2. verify focused Home acquisition tests
3. run full analysis/tests through PR CI
4. address all review threads
5. merge UX-01 only when final head is green
6. verify resulting main push CI is fully green
7. delete/supersede obsolete UX-01/repair branches where tooling permits
8. then begin UX-02 Home / Workspace modernization
```

Do not start O1 or G7B during this sequence.
