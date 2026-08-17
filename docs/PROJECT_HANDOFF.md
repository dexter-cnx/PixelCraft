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

Last refresh: **2026-08-17. PR #50 merged the `go_router` navigation foundation and platform-aware app entry. Phone/tablet now route camera-first at app launch, desktop remains editor/open/drop-first, and workspace navigation is declarative while Film/Filter/Adjust remain local tool state. PF0 routing is implemented; PF1/PF2 camera-shell integration is the next product slice.**

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
- repository name and runtime app identifiers remain unchanged unless a separate migration is approved;
- historical evidence may retain the name that existed when produced;
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

Do not expand PixelCraft by default into:

```text
Workplaces hierarchy
large library/catalog management
folder ingestion/archive management
ratings/flags/keywords catalog systems
large-scale metadata browsing/search
Lightroom-style DAM behavior
```

## Nixin / Dextryx Images

Primary role: **image manager / catalog / Workplaces product**.

Nixin owns asset identity, long-lived organization, browsing, catalog metadata, import, source management, collections, and future library workflows.

## Future external-edit direction

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
4. Do not make Nixin depend on PixelCraft app-internal widgets/providers.
5. Transport is separate from the request/result data model.

---

# 3. Canonical platform flow

## Phone and tablet — camera-first

Phone and tablet share one mental model. Tablet may adapt layout for larger screens, but launch remains camera-first.

```text
App launch
   ↓
Camera
```

Target shell:

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
- bottom left = **Gallery** / recent-source entry;
- bottom right = camera controls/settings;
- Film, Filter, and Adjust are available in Camera;
- verified GPU paths provide low-latency preview where faithful;
- unsupported GPU operations fail closed/fallback safely.

### Camera capture target

```text
clean camera capture
+ selected Film / Filter / Adjust configuration
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

1. capture remains clean internally;
2. live preview pixels are never final-render authority;
3. PF camera result is JPEG;
4. shutter does not force editor navigation after every capture;
5. Camera remains active after save;
6. recent thumbnail/confirmation may update;
7. tapping recent media may enter the editor.

### Gallery/editor target

```text
Gallery
 -> choose source
 -> preserve original source untouched
 -> Product Editor
 -> Film / Filter / Adjust / transforms / masks
 -> Rust full-resolution render
 -> save processed result to Gallery / explicit destination
```

Source preservation:

```text
JPEG source -> JPEG source remains untouched
PNG source  -> PNG source remains untouched
WebP source -> WebP source remains untouched
future RAW  -> RAW source remains untouched
```

Output format is a separate decision.

## Desktop — editor/open/drop-first

Desktop must not launch into the mobile camera shell.

```text
App launch
   ↓
Open / Drop surface
   ↓
Editor
```

Primary inputs:

```text
Open Image
Drag & Drop
```

Secondary/future inputs may include Open Recent, Paste Image, Capture from Camera, Open With, and Nixin external edit.

Desktop remains an editor, not a DAM/library clone.

---

# 4. Architecture invariants

```text
Flutter   = UI / control / presentation plane
Riverpod  = Flutter application/UI orchestration
Rust      = authoritative image semantics / recipe / history / checkpoint / recovery / export
Metal     = iOS realtime GPU preview
OpenGL ES = Android realtime camera preview
```

Hard contracts:

1. Rust owns committed edits, recipe/history/checkpoint/recovery, and full-resolution render/export.
2. GPU rendering is preview-only and never final-render authority.
3. Camera Film/Filter/Adjust preview never bakes the live preview framebuffer into the authoritative source.
4. Live camera buffers never cross MethodChannel or Flutter Rust Bridge.
5. Canonical Film/Creative LUT data is Rust-owned.
6. Native/GPU failure fails closed to valid Rust/product state.
7. Unsupported Rust operation order falls back; never silently reorder for GPU.
8. Film Profiles are reusable configuration, not per-image pixels/sessions.
9. Imported recipe fields report exact / approximated / unsupported mappings.
10. New effects are Rust-first; GPU support is enabled only when faithful.
11. Riverpod may orchestrate UI/transient preview state but must not become canonical recipe/history authority.
12. AI segmentation/restoration is optional capability and never committed-image authority.
13. Do not casually replace mobile Metal/OpenGL ES runtime with wgpu.
14. Editor-local workspace/catalog state is metadata/navigation state only and never authoritative edit/pixel state.
15. Recovery generations are crash/session recovery, not catalog identity.
16. Long-lived image-management ownership belongs to Nixin.
17. External-edit integration uses explicit request/result contracts rather than app-internal UI coupling.

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
PKG-02 existing-package ownership audit         PLANNED AFTER PF0/PF1
PKG-03 camera package extraction review         DEFER UNTIL AFTER PF3

G7A Release Engineering / Store Preparation    MERGED
G7B Store Account Integration / Beta Upload    DEFERRED INDEFINITELY / NOT SCHEDULED

UX-01 Modern import/add-photo entry flow        CLOSED / VERIFIED
UX-02 Home / Workspace modernization            CLOSED / VERIFIED
W1A/W1B editor-local catalog contract/storage  CLOSED / VERIFIED
W1C acquisition/catalog/Home integration       CLOSED / VERIFIED
W1D DAM-style multi-item expansion              CANCELLED AS DEFAULT DIRECTION

CI-01 affected fast-fail / reliability tiers    PR #49 / FULL VALIDATION GREEN

PF0 Platform-flow foundations                   PARTIAL / ROUTING FOUNDATION MERGED (#50)
PF1 Camera-first mobile/tablet shell             IN PROGRESS / CAMERA-FIRST ENTRY MERGED (#50)
PF2 Unified Camera Film/Filter/Adjust UX         PLANNED
PF3 Capture-process-save-to-Gallery              PLANNED
PF4 Gallery-to-editor source flow                PLANNED
PF5 External edit request/result contract        PLANNED FOUNDATION ONLY

MobileSAM / ONNX segmentation                   FUTURE / NOT ACTIVATED
Real RAW development                            FUTURE / NOT ACTIVATED
O1 Dart 3.13 native tree-shaking / RecordUse    FUTURE / DEFERRED / DO NOT START NOW
```

---

# 6. CI architecture baseline — PR #49

CI optimization is a focused infrastructure slice. It does not reorder PF0/PF1 or change image/runtime semantics.

Canonical CI document:

```text
docs/CI_ARCHITECTURE.md
```

## DAG

```text
Change Detection
      ↓
Fast CI
      ↓
selected affected/full jobs
      ├─ Native/GPU Core
      ├─ Golden Tests
      ├─ Android Build
      ├─ iOS Build
      ├─ macOS Build
      ├─ Windows Build
      ├─ Linux Build
      ├─ Reliability Tier 2
      └─ Reliability Tier 3
      ↓
CI Gate
```

Core policy:

- `Fast CI` is the fast-fail gate before expensive jobs;
- iterative PRs run only materially affected jobs;
- `main`, `merge_group`, explicit full mode, and CI/tooling changes force conservative full validation;
- `CI Gate` is the stable aggregate result for conditional jobs;
- branch protection should require `Fast CI` + `CI Gate`, not every conditional platform job individually;
- superseded PR runs are cancelled; main/merge-group validation is isolated from unrelated PR runs.

Local commands:

```bash
make format-check
make analyze
make test-fast
make gpu-check
make ci-fast
make preflight
```

Generated FRB bridge policy:

- Fast CI generates and verifies the complete bridge;
- the whole `lib/src/rust/**` generated directory plus Rust/C header outputs are uploaded as a run-scoped artifact;
- downstream platform jobs restore the same generated bridge rather than regenerating independently;
- Native/GPU Core still performs pinned FRB regeneration/drift validation when selected.

Reliability tiers:

```text
Tier 1 = fast deterministic correctness
Tier 2 = sensitive native/GPU/reliability automation + 12 MP characterization + safety guard
Tier 3 = full hosted G6 automation up to 48 MP, with physical-device status kept explicit
```

## Proven PR validation

PR #49 run:

```text
run #432
run id: 31951272254
head fix: 7e7bf4d256cca462d5adb69b7f4f651eadb61d18
result: SUCCESS
```

Passed jobs:

```text
Change Detection
Fast CI
Native/GPU Core
Golden Tests
Android Build
iOS Build
macOS Build
Windows Build
Linux Build
Reliability Tier 2
Reliability Tier 3
CI Gate
```

The Windows final fix corrected the `dxtr_pixs_engine` CargoKit manifest relative path. Full run #432 then passed on all supported hosted platforms.

**Important:** PR green is not the final closure condition. After merge, verify the resulting `main` push CI before declaring CI-01 fully closed.

---

# 7. G6 reliability and device safety

G6 is closed/verified.

Canonical identifiers:

```text
main app id: dev.cnxdev.pixelcraft
isolated verifier id: dev.cnxdev.pixelcraft.g6verify
```

Hard invariant:

```text
DO NOT uninstall or overwrite dev.cnxdev.pixelcraft during verifier/device runs.
```

Physical evidence already recorded:

```text
iPhone 11 UDID: 00008030-0004694C3E68C02E
10/50/100-cycle soak evidence: PASS / characterized
thermal sustained workload: PASS / characterized
manual physical checklist: completed
```

Hosted CI must never fabricate a physical-device PASS. Tier 3 may complete hosted G6 validation while explicitly skipping physical-device smoke when no real `DEVICE` is supplied.

`tool/ci_device_safety_guard.sh` statically enforces the main/verifier ID and worktree isolation contract.

See:

```text
docs/G6_RELIABILITY_MATRIX.md
docs/G6_DEVICE_MANUAL_CHECKLIST.md
```

---

# 8. PF0 — platform-flow foundations

PF0 is now partially implemented. PR #50 established the navigation/router foundation and platform-aware app entry; localization, preferences, processing-job state, and remaining service boundaries continue as PF0 follow-up work alongside PF1.

## Localization

Use **easy_localization**.

Initial locales:

```text
en
th
```

Policy:

```text
device th_* -> th
device en_* -> en
unsupported -> en
fallback -> en
```

Initial resources:

```text
assets/translations/en.json
assets/translations/th.json
```

New user-facing Flutter strings should be localized.

## State management

Use **Riverpod** as the Flutter application/UI state standard.

Recommended boundaries:

```text
AppPreferencesState
CameraState
LiveLookState
EditorUiState
ProcessingJobState
ExternalEditState   # future orchestration
```

Riverpod is not image-processing authority.

## Preferences

Introduce `AppPreferencesStore` with a lightweight replaceable backend.

Candidate values:

```text
last camera lens
grid enabled
flash/camera UI preference
last Film id + strength
last Filter id + strength
theme
optional locale override
last editor UI tool
```

Do not add Hive merely as future-proofing.

## Application services

Converge toward explicit boundaries:

```text
MediaPickerService
MediaSaveService
PermissionService
CapabilityRegistry
ProcessingJob coordinator/state
AppRouter / navigation abstraction   # go_router foundation implemented in PR #50
```

## Navigation foundation — merged in PR #50

Canonical document:

```text
docs/NAVIGATION_ARCHITECTURE.md
```

Current route contracts:

```text
/                       platform-aware entry
/camera                 phone/tablet camera workspace
/desktop                desktop open/drop workspace
/editor                 product editor
/films                  Film Profiles workspace
/debug/gpu-editor-lab   debug-only GPU editor lab
```

Navigation rule:

```text
workspace change = route
workspace tool change = state
```

`EditorRouteData` is passed through `GoRouterState.extra`, so arbitrary local file paths are not encoded into public URLs. Camera -> Editor already uses named routing. Film/Filter/Adjust interactions, sheets, dialogs, and local dismissals remain local UI state/local Navigator behavior. The router is created once at app startup and disposed with the app state; Rust bootstrap initialization is shared across routed workspaces.

## Processing job state

Use explicit longer-work state:

```text
idle
processing
saving
completed
failed
```

Prevent duplicate shutter/export while the relevant job is active.

Typed failures should include at least:

```text
cameraUnavailable
permissionDenied
permissionRestricted
decodeFailed
unsupportedSource
renderFailed
saveFailed
```

## Format-aware source descriptor

New input contracts must not assume every file is JPEG/PNG.

A source descriptor should carry:

```text
uri/path
mime type / format
source provenance
optional caller-owned external id
metadata needed for opening/returning
```

This keeps future RAW and Nixin integration from forcing a source-identity redesign.

---

# 9. Existing implementation relevant to PF1-PF4

Current runtime uses `MaterialApp.router` with one persistent `GoRouter`. Phone/tablet initial location is `/camera`; desktop initial location is `/desktop`. Both routes remain behind the shared Rust bootstrap, so navigation does not repeatedly initialize the native engine.

Existing camera foundation already provides:

- native GPU camera preview on supported iOS/Android paths;
- Flutter `camera` fallback;
- camera switch;
- Film preview and strength;
- permission/lifecycle handling;
- clean capture;
- current capture -> editor handoff.

PF work must reuse this foundation rather than build a second camera stack.

PF3 changes current capture behavior to authoritative processing + JPEG save + remain in Camera.

`WorkspaceCatalogStore` remains only bounded continuity/reopen metadata and must not become the primary product library.

`EditorSessionStore` remains edit recovery and is separate from preferences/catalog concerns.

---

# 10. Film and Filter status

Film and Creative Filter are real Rust-backed production foundations.

Film:

```text
EditOperation::FilmProfile { id, strength }
33x33x33 canonical LUTs
Rust-authoritative replay/export
verified realtime GPU LUT preview where supported
```

Current inspired Film pack includes:

```text
Provia
Velvia
Astia
E100
Ektar
Chrome 64
```

Creative filters include:

```text
grayscale
invert
vintage
oceanic
lofi
dramatic
golden
pastel_pink
```

PF2 is primarily a camera UX integration milestone, not a reinvention of Film/Filter semantics.

---

# 11. Package graph and extraction policy

Current graph:

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

Policy:

- prefer consolidation into the existing four packages before creating new packages;
- do not create generic utility packages merely to reduce directory size;
- app services/navigation/preferences remain application-layer boundaries unless reuse proves otherwise;
- audit remaining `lib/core` ownership after PF0/PF1;
- do not extract `dxtr_pixs_camera` before PF3 stabilizes capture and processing-handoff contracts.

Future package family only when milestones activate:

```text
dxtr_pixs_segment
dxtr_pixs_restore
dxtr_pixs_raw
```

Boundary guard:

```text
tool/check_package_boundaries.sh
```

---

# 12. Future MobileSAM / ONNX segmentation

Future package direction:

```text
dxtr_pixs_segment
```

Status: **FUTURE / NOT ACTIVATED**.

Target boundary:

```text
source / reduced analysis image
  ↓
MaskProvider
  ↓
local MobileSAM/ONNX implementation
  ↓
mask result
  ↓
PixelCraft edit semantics
```

Segmentation generates masks. It is not committed-image authority.

Do not mix MobileSAM implementation into PF0-PF5.

---

# 13. Future real RAW development

Future package direction:

```text
dxtr_pixs_raw
```

Status: **FUTURE / NOT ACTIVATED**.

A real RAW milestone must separately define:

- RAW decode/demosaic;
- Bayer/X-Trans support where applicable;
- black/white level normalization;
- camera WB/color matrices;
- highlight recovery;
- working color-space conversion;
- RAW-specific memory/performance policy;
- authoritative full-resolution replay/export.

PF source contracts remain RAW-aware, but PF0-PF5 must not implement real RAW development unless explicitly activated.

---

# 14. Deferred work

## O1 — Dart 3.13 RecordUse / native tree-shaking

**FUTURE / DEFERRED / DO NOT START NOW.**

Detailed plan:

```text
docs/FUTURE_DART_3_13_NATIVE_TREE_SHAKING.md
```

## G7B

**DEFERRED INDEFINITELY / NOT SCHEDULED.**

Neither O1 nor G7B blocks PF0-PF5.

---

# 15. Release baseline

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

# 16. Verification rules

1. Never claim CI/test/device/build/store validation passed unless actually run or explicitly reported.
2. Never commit signing secrets, certificates, provisioning profiles, passwords, or store credentials.
3. Never ship Android production artifacts with debug signing.
4. Do not weaken Rust authority, GPU fail-closed behavior, or package boundaries.
5. A PR being green is not enough to declare a slice complete; verify resulting `main` push CI after merge.
6. Do not import Nixin roadmap items into PixelCraft beyond the explicit external-edit boundary.
7. Do not bind Nixin to PixelCraft app-internal UI classes/providers.
8. Mobile/tablet camera-first and desktop editor-first are product policies.
9. Camera live preview pixels are never final-render authority.
10. PF3 camera output is JPEG generated through the authoritative processing path.
11. Gallery/external source inputs remain untouched; output is separate.
12. Riverpod is UI/application orchestration only; Rust remains edit authority.
13. Localization begins with en/th, device detection, fallback en.
14. Do not introduce Hive without a concrete persistence requirement.
15. Do not start MobileSAM, real RAW, O1, or G7B during PF0-PF5 unless explicitly activated.
16. Prefer consolidation into existing packages before creating new packages.
17. Do not extract `dxtr_pixs_camera` before PF3 stabilizes capture/processing-handoff contracts.
18. Do not create placeholder future packages before their milestones are activated.
19. Keep main/verifier device identifiers isolated and never uninstall/overwrite the main app during verifier runs.
20. Hosted Tier 3 reliability must never be presented as new physical-device evidence.
21. Branch protection should rely on stable `Fast CI` and `CI Gate` contexts rather than conditional platform jobs.

Standard local validation:

```bash
make preflight
```

Focused CI-equivalent commands:

```bash
make format-check
make analyze
make test-fast
make gpu-check
make ci-fast
```

Additional project validation:

```bash
bash tool/check_package_boundaries.sh
make gpu-lut-verify
make verify-native
flutter analyze
flutter test
```

---

# 17. Current next action

## First: finish CI-01 PR #49 closure

PR #49 has a full green validation baseline on run #432. Documentation sync is being finalized on the PR head.

Before calling CI-01 complete:

1. require latest PR head `Fast CI` + `CI Gate` to be green;
2. mark PR #49 Ready for Review;
3. merge only after required checks remain green;
4. verify the resulting `main` push full CI;
5. then delete the merged feature branch when safe.

## Product work after CI-01

Implement **PF0 + PF1 first**.

Required first slice:

1. add `easy_localization` foundation with `en` + `th`, device locale detection, fallback `en`;
2. standardize Riverpod application-state boundaries without moving canonical edit semantics out of Rust;
3. add `AppPreferencesStore` abstraction with a lightweight backend; do not add Hive yet;
4. define `MediaPickerService`, `MediaSaveService`, `PermissionService`, `CapabilityRegistry`, typed `ProcessingJobState`, and a lightweight route/navigation boundary;
5. define a format-aware source descriptor that can later support RAW and external caller identity;
6. introduce platform-adaptive root routing after Rust bootstrap;
7. phone/tablet launch directly into the existing camera foundation;
8. desktop launches an editor/open/drop-oriented surface rather than the mobile camera shell;
9. mobile/tablet camera bottom hierarchy becomes Gallery / Shutter / Controls;
10. preserve current verified GPU/Rust contracts and camera permission/lifecycle hardening;
11. keep Home/Workspace code only as bounded continuity/recovery support while the new root stabilizes;
12. do not start MobileSAM, real RAW, O1, G7B, Hive migration, or Nixin DAM work.

Package follow-up after PF0/PF1 stabilizes:

```text
PKG-02 audit remaining lib/core ownership
 -> consolidate Film-owned code into dxtr_pixs_film where appropriate
 -> consolidate reusable engine-facing code into dxtr_pixs_engine where appropriate
 -> do not create new generic utility packages
 -> defer dxtr_pixs_camera extraction decision until PF3 is stable
```

Then proceed:

```text
PF0 platform-flow foundations
 -> PF1 camera-first mobile/tablet + desktop editor-first shell
 -> PF2 unified camera Film/Filter/Adjust UX
 -> PF3 capture + authoritative render + JPEG Gallery save + remain in Camera
 -> PKG-03 evaluate dxtr_pixs_camera extraction against stable PF3 contracts
 -> PF4 Gallery source -> editor -> Gallery export
 -> PF5 versioned external-edit request/result foundation for future Nixin integration
```

Keep `docs/CODE_WALKTHROUGH.md`, `README.md`, `docs/CI_ARCHITECTURE.md`, tests, and this handoff synchronized as each slice lands.
