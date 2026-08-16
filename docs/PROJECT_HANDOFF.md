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

Last refresh: **2026-08-16. UX-01 and UX-02 are merged and verified on main through PR #39 and main CI #345. No persistent multi-item workspace/catalog model exists yet. G7B and Dart 3.13 native tree-shaking remain deferred.**

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
UX-02 Home / Workspace modernization            CLOSED / VERIFIED
W1 Real workspace/catalog foundation           NEXT / DESIGN + CONTRACT FIRST
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
PR #39  real persisted recent-edit card with bounded thumbnail decode
```

Verification evidence:

```text
PR #37 merge: eda3a04e44147d5d8e6e2edb7d8760a92a9ec340
main CI after #37: #337 / 31897159986 / success

PR #38 merge: 4c35eeaeaeadb0334394509b03bc194393720691
PR #38 final head CI: #340 / 31898608876 / success
main CI after #38: #341 / 31899235126 / success

PR #39 final head: 9f55fd4b1f21bd8c74283134473e860d19782b68
PR #39 final head CI: #344 / 31919129394 / success
PR #39 merge: 4afb8a38f045abb00c9e6dccf9b75f3b19ad4dd7
main CI after #39: #345 / 31919832339 / success
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

## UX-02 — Home / Workspace modernization — CLOSED / VERIFIED

PR #38:

- removed permanent sample-photo grid;
- removed demo/marketing/implementation explanatory copy;
- retained real empty workspace state;
- retained deterministic recovery/resume behavior;
- retained Import as primary action;
- no fake recent/catalog data.

PR #39:

- promoted the existing persisted `EditorSessionStore` recovery generation into the real `Recent edit` hierarchy;
- thumbnail uses stored `originalBytes`;
- thumbnail decode is bounded by 88 logical pixels × device pixel ratio rather than full-resolution decode;
- timestamp uses stored `savedAt`;
- legacy epoch sentinel is hidden rather than rendered as 1970;
- Resume / Discard semantics remain unchanged;
- no fake recent images, catalog rows, or new persistence model were introduced.

Verified through PR #39 final head CI #344 and resulting main CI #345.

### Workspace data boundary discovered during UX-02

At the end of UX-02, the repository has one real persisted workspace datum suitable for Home: the latest recoverable editor generation from `EditorSessionStore`.

There is **no persistent multi-item workspace/catalog/history model** that can truthfully power a Lightroom-style list/grid of imported or edited images. Do not fabricate such rows from bundled assets, temporary picker results, or recovery generations.

Any multi-item workspace UI must therefore begin with W1 below.

### Design direction

- image first;
- direct manipulation;
- progressive disclosure;
- continuous preview only where architecture safely supports it;
- micro motion ~80-120 ms, fast 140-180 ms, standard 200-260 ms, spatial 280-360 ms;
- perceived direct-control latency target below roughly 100 ms;
- compact precision controls with large invisible hit areas;
- avoid excessive glass, blur, gradients, bounce, and oversized cards.

---

# 6. W1 — Real workspace/catalog foundation — NEXT

Purpose: establish a truthful multi-item workspace data model before adding a multi-image Recent/Library UI.

Do **not** start by drawing a grid. Define and validate the data contract first.

Initial contract questions:

```text
W1.0 ownership
- decide which layer owns workspace/catalog metadata
- Rust remains authoritative for edit semantics; catalog metadata must not become a second image-edit authority

W1.1 item identity
- stable item id independent of display name/path
- source origin: import / camera / film camera
- original source reference/path where platform policy permits
- created/imported/last-edited timestamps

W1.2 edit linkage
- link item to authoritative recipe/checkpoint/session identity without duplicating Rust edit semantics
- recovery session remains crash recovery, not the catalog itself

W1.3 storage policy
- define app-owned copy vs external-reference behavior per platform
- define missing/moved source behavior
- no silent destructive migration of existing recovery data

W1.4 thumbnail policy
- persist or generate bounded thumbnails; never decode full-resolution originals merely to populate Home
- define invalidation when orientation/source changes

W1.5 lifecycle
- import -> catalog item
- open/edit -> recipe/checkpoint linkage
- discard recovery must not accidentally delete catalog identity
- delete/remove semantics must be explicit

W1.6 tests/migration
- deterministic repository tests
- legacy/no-catalog startup remains valid
- recovery store compatibility retained
```

Implementation should remain focused and may be split into contract/storage/UI PRs. Do not add fake data to make the UI look complete.

---

# 7. Package graph and naming

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

# 8. Future O1 — Dart 3.13 RecordUse / native tree-shaking

**FUTURE / DEFERRED / DO NOT START NOW.**

Detailed plan:

```text
docs/FUTURE_DART_3_13_NATIVE_TREE_SHAKING.md
```

Do not change the Dart SDK constraint, Flutter baseline, Flutter Rust Bridge integration, native build pipeline, Rust ABI, or release packaging merely to start O1. Adoption requires measured before/after binary evidence.

---

# 9. G7B

G7B is **deferred indefinitely / not scheduled**. Do not treat it as a blocker and do not resume it without an explicit project decision.

---

# 10. Reliability / device evidence

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

# 11. Release baseline

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

# 12. Verification rules

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

# 13. Current next action

**Start W1 real workspace/catalog foundation. Contract and storage semantics come before multi-item Home UI.**

Required sequence:

```text
1. inspect existing editor/recovery/session persistence and platform source-path assumptions
2. write the W1 catalog item/repository contract and ownership decision
3. define import/camera source lifecycle and missing-source behavior
4. define bounded thumbnail storage/generation policy
5. implement the smallest persistent repository with deterministic tests
6. integrate Import with catalog creation without changing Rust edit authority
7. only then expose real multi-item workspace content on Home
8. keep recovery generation separate from catalog identity
```

Do not start O1, G7B, MobileSAM, restoration, or fake catalog UI during this sequence.
