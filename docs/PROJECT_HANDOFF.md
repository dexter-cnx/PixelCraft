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

Last refresh: **2026-08-16. PR #42 is merged as `a5d015587a9eab0125d8605f91fff9307e8d0c11`; resulting main CI #363 is still running at the time of this edit. Product boundary has been corrected: PixelCraft is the photo-editing/image-processing product; Nixin/Dextryx Images is the image-management product. PixelCraft must not evolve into a Lightroom-style DAM by default.**

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

# 2. Canonical product boundary — PixelCraft vs Nixin

This boundary overrides any earlier planning language that accidentally mixed the two products.

## PixelCraft / Dextryx Pixels

**Primary role: photo editor + image-processing product.**

Owns:

```text
edit session UX
Rust authoritative recipe/history/checkpoint
image-processing semantics
GPU preview
Film Profiles / Creative filters
masks / transforms / adjustments
full-resolution render/export
editor recovery/session continuity
```

PixelCraft may keep a **small editor-local workspace/catalog convenience layer** only when needed to support opening recent sources, recovery continuity, source availability, and navigation back into an edit.

PixelCraft is **not** the primary image-management/DAM product. It must not automatically grow into:

```text
large library/catalog management
Workplaces/collections hierarchy
folder ingestion workflows
bulk asset organization
ratings/flags/keywords as a catalog system
large-scale metadata browsing/search
multi-folder archive management
Lightroom-style DAM behavior
```

Those belong to Nixin/Dextryx Images unless a future explicit product decision says otherwise.

## Nixin / Dextryx Images

**Primary role: image manager / catalog / Workplaces product.**

Nixin owns long-lived asset organization, import, browsing, catalog metadata, source management, and future library-management workflows.

## Future external-edit direction

A future integration may make Nixin invoke PixelCraft as an external editor:

```text
Nixin / Dextryx Images
  owns asset/catalog identity
  ↓ external edit request
PixelCraft / Dextryx Pixels
  owns edit session + processing + render/export
  ↓ edited result / recipe reference / return contract
Nixin resumes asset management
```

Guardrails:

1. Do not create two competing authoritative catalogs for the same integration.
2. Nixin must not become authoritative for PixelCraft edit recipes/pixel semantics.
3. PixelCraft must not become authoritative for Nixin Workplaces/library organization.
4. The external-edit protocol is future work and must be explicitly designed/versioned before implementation.
5. Do not copy Nixin roadmap terminology or Lightroom-style management requirements into PixelCraft by default.

---

# 3. Architecture invariants

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
13. PixelCraft workspace/catalog state is metadata/navigation state only and must never become authoritative edit/recipe/pixel state.
14. Recovery generations remain crash/session recovery and are not catalog identity.
15. Workspace/catalog scope must remain editor-local; long-lived image-management ownership belongs to Nixin.

---

# 4. Milestone status

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
W1A/W1B editor-local catalog contract/storage  CLOSED / VERIFIED
W1C acquisition/catalog/Home integration       MERGED / MAIN CI VERIFICATION PENDING
W1D DAM-style multi-item expansion              CANCELLED AS DEFAULT DIRECTION
O1 Dart 3.13 native tree-shaking / RecordUse   FUTURE / DEFERRED / DO NOT START NOW
```

Historical G7 PR #10 is closed/superseded. Do not reopen it.

---

# 5. Recent merged product work

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
PR #41  editor-local workspace catalog storage foundation
PR #42  acquisition/catalog/Home integration
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

PR #42 final head: 1218ec44d0d9938a89b7f7ab294b0a55a2f435b5
PR #42 final head CI: #362 / 31930004255 / success
PR #42 merge: a5d015587a9eab0125d8605f91fff9307e8d0c11
main CI after #42: #363 / 31930570158 / running at this handoff edit
```

Home regression policy:

- Home uses structural/behavior regression rather than the old corrupt PNG baseline.
- editor goldens continue pixel comparison.
- do not reintroduce binary/base64 bootstrap workarounds for the old Home golden.

---

# 6. Product / Editor UX

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

## UX-02 — Home / Workspace modernization — CLOSED / VERIFIED

The Home surface is an editor entry/recovery surface, not a DAM browser.

Valid responsibilities:

- primary Import entry;
- recent recoverable edit;
- small set of real persisted editor-local source entries when useful;
- source missing status;
- resume/open into editor;
- bounded thumbnails;
- no fake/demo/sample assets.

Do not extrapolate this into a full asset-management product.

### Workspace data boundary

```text
EditorSessionStore
= recover latest coherent editing session after interruption/crash
= bytes + authoritative Rust recipe envelope linkage
= generation-based recovery

WorkspaceCatalogStore
= lightweight editor-local source/navigation metadata
= provenance / path retention / availability / timestamps
= no recipe/history/pixels authority
= not Nixin Workplaces and not a general-purpose DAM catalog
```

Never repurpose recovery generations as catalog rows.

---

# 7. W1 correction — editor-local workspace/catalog only

W1A/W1B and W1C are retained because they provide useful editor-local continuity. Their scope must now remain bounded.

## W1A/W1B — contract + storage — CLOSED / VERIFIED

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

## W1C — acquisition/catalog/Home integration — MERGED

Current behavior:

```text
Import / Take Photo
 -> picker result
 -> lightweight catalog metadata
 -> open ProductEditorScreen

Home
 -> render real editor-local entries
 -> reopen source in ProductEditorScreen
 -> missing source => preserve identity + mark missing
```

Hardening retained:

- lost picker recovery does not invent source provenance;
- in-flight workspace opening prevents duplicate routes;
- thumbnails use bounded decode dimensions;
- catalog mutation failure does not block editing;
- persistence/corruption semantics remain separately tested.

## Explicitly removed from PixelCraft default roadmap

The following previously proposed W1D-style work was an accidental Nixin/DAM direction and is **not** a PixelCraft milestone by default:

```text
large multi-item library/grid as primary product surface
folder import workflows
bulk multi-select asset ingestion
managed archive/folder organization
Workplaces/collections hierarchy
ratings/flags/keywords catalog system
large catalog browser/search
Lightroom-style DAM workflow
```

Do not implement these in PixelCraft unless a future explicit product decision reopens them.

## Allowed follow-up hardening

Only implement catalog-related work when it protects editor continuity, for example:

- Film Camera source registration if needed for reopening the captured clean source;
- source-retention/durability fixes required to prevent broken editor reopen behavior;
- missing-source handling;
- duplicate route/session prevention;
- migration/failure fixes.

Avoid turning those fixes into a broader asset-management program.

---

# 8. PixelCraft next product direction

Once PR #42 main CI is verified, prioritize **photo editing / processing** work rather than DAM expansion.

Candidate categories should be selected from the PixelCraft roadmap and current product needs, such as:

```text
editor UX refinement
processing correctness/performance
Film/Creative workflow
GPU preview fidelity/reliability
export/render workflow
masking/segmentation capability when explicitly activated
restoration capability when explicitly activated
future real RAW pipeline only when separately approved
```

Do not infer Nixin requirements as PixelCraft requirements.

---

# 9. Package graph and naming

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

# 10. Future O1 — Dart 3.13 RecordUse / native tree-shaking

**FUTURE / DEFERRED / DO NOT START NOW.**

Detailed plan:

```text
docs/FUTURE_DART_3_13_NATIVE_TREE_SHAKING.md
```

Do not change the Dart SDK constraint, Flutter baseline, Flutter Rust Bridge integration, native build pipeline, Rust ABI, or release packaging merely to start O1. Adoption requires measured before/after binary evidence.

---

# 11. G7B

G7B is **deferred indefinitely / not scheduled**. Do not treat it as a blocker and do not resume it without an explicit project decision.

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
5. G7B remains deferred until explicitly resumed.
6. Bundle/application identifier migration is separate from UX work.
7. Native Rust/ABI names remain stable unless separately justified and validated.
8. O1 / RecordUse is future/deferred and must not start without explicit activation.
9. Do not claim a remote branch is deleted unless GitHub confirms the ref no longer exists.
10. A PR being green is not enough to declare a slice complete; verify resulting `main` push CI after merge.
11. Do not import Nixin/Dextryx Images roadmap items into PixelCraft unless explicitly approved for PixelCraft.

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

1. Verify resulting main push CI #363 for PR #42 merge `a5d015587a9eab0125d8605f91fff9307e8d0c11`.
2. Mark W1C closed/verified only after that exact main CI succeeds.
3. Merge this product-boundary documentation correction.
4. Do **not** start the previously proposed DAM-style W1D.
5. Select the next PixelCraft milestone from editing/processing/product-editor priorities.
6. Keep Nixin external-edit integration as a future cross-product contract, not an implicit current implementation task.
7. Continue updating `docs/CODE_WALKTHROUGH.md` and this handoff when implementation materially changes.

Do not start O1, G7B, or Nixin-style Workplaces/DAM expansion from this handoff.