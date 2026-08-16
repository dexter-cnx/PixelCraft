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

Last refresh: **2026-08-16. UX-01 and UX-02 are merged and verified. W1 catalog contract/storage foundation from PR #41 is merged and verified on main CI #352. PR #42 integrates real gallery/system-camera acquisitions with the catalog and renders real persisted workspace items on Home; final PR head CI #361 is green, with merge/main verification still pending. G7B and Dart 3.13 native tree-shaking remain deferred.**

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
13. Workspace/catalog state is metadata/navigation state only and must never become authoritative edit/recipe/pixel state.
14. Recovery generations remain crash/session recovery and are not catalog identity.

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
W1A/W1B catalog contract + storage foundation  CLOSED / VERIFIED
W1C acquisition/catalog/Home integration       ACTIVE / PR #42 GREEN, MERGE PENDING
W1D multi-item workspace refinement            NEXT AFTER #42 MAIN CI
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
PR #40  UX-02 closeout / W1 handoff definition
PR #41  real workspace catalog storage foundation
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

PR #40 merge: 29af1b17fa3f0066aa9428190b79fe4e26d8a1b3
main CI after #40: #347 / 31921037298 / success

PR #41 final head: 677f104ab1601f9f8c913818a334e8d18110f15f
PR #41 final head CI: #351 / 31922407181 / success
PR #41 merge: 7f3ae0eaaa6fe40711eca251ac746b3a24e1b69a
main CI after #41: #352 / 31922895364 / success

PR #42 head before handoff sync: 61a36e9e9c8068b5f7c47db4420688c2b9ac1576
PR #42 head CI: #361 / 31929407911 / success
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

### Workspace data boundary

`EditorSessionStore` and `WorkspaceCatalogStore` intentionally solve different problems:

```text
EditorSessionStore
= recover latest coherent editing session after interruption/crash
= bytes + authoritative Rust recipe envelope linkage
= generation-based recovery

WorkspaceCatalogStore
= stable multi-item navigation/metadata identity
= source provenance / path retention / availability / timestamps
= no recipe/history/pixels authority
```

Never repurpose recovery generations as catalog rows.

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

# 6. W1 — Real workspace/catalog foundation — ACTIVE

Purpose: establish a truthful multi-item workspace data model and real Home navigation without introducing a second edit authority.

## W1A/W1B — contract + storage — CLOSED / VERIFIED

Implemented in PR #41 and verified on resulting main CI #352.

Catalog item contract:

```text
stable id
sourceKind: gallery / systemCamera / filmCamera
retention: externalReference / managedCopy
sourcePath
availability: unknown / available / missing
importedAt
updatedAt
lastOpenedAt?
```

No recipe/history/checkpoint/pixels/edit settings are stored in catalog items.

Storage properties:

- app-local `pixelcraft-workspace/catalog.json` manifest;
- versioned schema;
- strict mutation semantics: malformed/newer manifests are not silently overwritten;
- crash-safe publish with `.tmp` and `.bak`;
- backup recovery for interrupted replacement;
- shared per-directory serialization across store instances in the Dart isolate;
- stable unique id allocation under the same write lock;
- deterministic newest-`updatedAt` ordering;
- focused persistence/concurrency/corruption/new-schema tests.

## W1C — acquisition/catalog/Home integration — ACTIVE

Implemented in PR #42; final merge/main verification still required.

Current behavior:

```text
Import (gallery)
 -> picker result
 -> catalog item sourceKind=gallery
 -> externalReference path
 -> open ProductEditorScreen

Take Photo (system camera)
 -> picker result
 -> catalog item sourceKind=systemCamera
 -> externalReference path
 -> open ProductEditorScreen

Home
 -> WorkspaceCatalogStore.load()
 -> render persisted real items only
 -> open existing source in ProductEditorScreen
 -> missing source => mark availability=missing, preserve stable identity
```

Additional hardening:

- lost picker recovery does **not** guess gallery-vs-camera provenance because `image_picker.retrieveLostData()` does not provide enough provenance; recovered files open without fabricated catalog metadata;
- workspace item opening uses an in-flight guard before filesystem/catalog awaits, preventing double-tap duplicate editor routes;
- Home thumbnails use bounded decode dimensions;
- catalog mutation failure does not prevent the editor from opening, while catalog storage itself remains fail-closed;
- Home widget tests use an in-memory catalog test double, while real disk/atomic/corruption semantics remain covered by `workspace_catalog_store_test.dart`;
- `docs/CODE_WALKTHROUGH.md` is updated for acquisition → catalog → Home behavior.

Not yet done in W1C:

- Film Camera capture catalog handoff;
- durable managed-copy policy for picker/camera sources;
- durable pending-acquisition provenance for Android lost-data recovery;
- duplicate asset reconciliation beyond stable catalog identity rules.

## W1D — next UI/data refinement

Start only after PR #42 merge and resulting main CI succeed.

Targets:

- refine real multi-item Home list/grid hierarchy using catalog data only;
- deterministic sorting and item actions;
- clearer Resume/Edit/missing-source affordances;
- preserve Import as primary action;
- no fake/demo/sample rows;
- do not move recipe/pixel authority into Flutter catalog state.

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

**Finish PR #42 cleanly, then continue W1D from verified main.**

Required sequence:

```text
1. verify CI for the final PR #42 head after this handoff sync
2. verify no actionable review threads remain
3. merge PR #42 only when exact-head CI is green
4. verify resulting main push CI for the exact merge SHA
5. after main is green, begin W1D in a fresh branch
6. keep Film Camera catalog handoff and managed-copy policy explicit follow-up decisions; do not guess platform durability
7. continue updating docs/CODE_WALKTHROUGH.md and this handoff as implementation changes
```

Do not start O1, G7B, MobileSAM, restoration, or fake catalog UI during this sequence.
