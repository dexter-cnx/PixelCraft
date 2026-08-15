# PixelCraft Project Handoff

## Purpose

This is the canonical continuation document for the PixelCraft repository and the **Dextryx Pixels** product.

When starting a new work session:

1. read this file first;
2. inspect `main`, active PRs, and their latest CI runs;
3. continue from **Current next action**;
4. treat repository state and recorded CI/device evidence as authoritative over older chat history.

Recommended continuation prompt:

```text
อ่าน docs/PROJECT_HANDOFF.md ใน repo PixelCraft แล้วทำต่อจาก Current next action
```

Last refresh: **2026-08-15, after PR #30 (`dxtr_pixs_*` namespace) and PR #32 (post-namespace branding test repair) merged; G7B remains deferred indefinitely; O1 Dart 3.13 native tree-shaking is planned behind one explicitly defined UX modernization slice.**

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
8. Flutter/Dart reusable packages use the `dxtr_pixs_*` family.

Relevant merged PRs:

```text
PR #27  Product identity -> Dextryx Pixels / Dxtr Pixs
PR #30  Flutter/Dart reusable package namespace -> dxtr_pixs_*
PR #32  Post-namespace branding tests / golden repair
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
12. Do not replace the current product runtime GPU architecture with wgpu casually. Cross-platform wgpu verification may exist in CI, but the product runtime remains Metal on iOS and OpenGL ES on Android unless deliberately redesigned.

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

PKG-01 dxtr_pixs_* namespace consolidation      COMPLETE / PR #30

G7A Release Engineering / Store Preparation     MERGED
G7B Store Account Integration / Beta Upload     DEFERRED INDEFINITELY / NOT SCHEDULED

Post-G7A Product / Editor UX                    ACTIVE
Dextryx Pixels identity                         COMPLETE

UX-01 Modern import/add-photo entry flow         NEXT UX GATE
O1  Dart 3.13 native tree-shaking / RecordUse    PLANNED AFTER UX-01
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
PR #30  dxtr_pixs_* reusable package namespace
PR #32  Post-namespace branding test/golden repair
```

These slices are presentation/product workflow improvements. They do not transfer committed image authority away from Rust and do not make GPU preview authoritative.

## 4.1 UX-01 — Modern import/add-photo entry flow

This is the **concrete UX slice that gates O1**. It replaces the current test-app-style add-photo flow where the user is exposed to three implementation-oriented choices before getting to the image selection task.

Goal:

```text
make adding/importing a photo feel like one obvious user action, with secondary source/mode choices progressively disclosed only when they are actually needed.
```

Scope:

- one primary add/import action from the main image workflow;
- eliminate the up-front three-choice modal/menu as the normal path;
- preserve all currently supported acquisition/import capabilities;
- expose advanced/secondary choices through progressive disclosure, contextual actions, or platform-native picker capabilities;
- keep the transition spatially continuous and image-first;
- use the existing design direction: dark digital-darkroom surface, compact controls, restrained motion, no generic giant Material cards;
- no Rust image-semantic changes;
- no package, ABI, channel, applicationId, or bundle-id migration.

UX-01 stabilization criteria:

```text
[ ] normal add/import path requires one obvious primary action before the platform picker/source flow
[ ] existing supported acquisition/import routes remain reachable
[ ] no regression to editor/camera semantic commit paths
[ ] interaction remains responsive; avoid synchronous expensive work on tap/gesture path
[ ] widget/state tests cover the primary and secondary entry paths
[ ] affected goldens are intentionally refreshed and reviewed
[ ] full CI is green on the final UX-01 head
[ ] no unresolved review thread remains on the UX-01 PR
[ ] UX-01 is merged to main
```

**Only the completion of UX-01 above satisfies the UX gate for O1.** Future UX work does not need to be completed before O1 unless it introduces a direct native API/build dependency that would invalidate O1 measurements.

Design direction for later UX slices:

- image-first and direct-manipulation interaction;
- progressive disclosure instead of implementation-choice dialogs;
- micro motion about 80-120 ms, fast 140-180 ms, standard 200-260 ms, spatial 280-360 ms where appropriate;
- perceived interaction latency target under roughly 100 ms for direct controls;
- precision sliders with large invisible hit targets, thin visual tracks, ticks/zero, numeric entry/reset where relevant;
- discoverable press-hold or divider Before/After;
- avoid excessive glass, blur, gradients, bounce, and oversized cards.

---

# 5. Package graph and naming policy

PKG-01 is complete. Current reusable Flutter/Dart package graph:

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

The guard rejects reintroduction of legacy Dart package URIs:

```text
package:pixelcraft_editing/
package:pixelcraft_film/
package:pixelcraft_gpu/
package:pixelcraft_engine/
```

Native ABI/runtime identity deliberately remains stable:

```text
Rust crate: pixelcraft_engine
native library: libpixelcraft_engine.*
GPU native library: libpixelcraft_gpu_native.*
MethodChannel/native protocol identifiers
persistent storage/schema names
applicationId / bundle id
```

Future package names:

```text
dxtr_pixs_segment  MobileSAM ONNX / local segmentation
dxtr_pixs_restore  Face Enhance / AI Denoise / Super-Resolution
dxtr_pixs_raw      future real RAW pipeline only if a clean package boundary is proven
dxtr_pixs_core     shared types only when concrete reuse justifies extraction
```

Avoid creating empty packages merely to satisfy an architectural diagram.

---

# 6. O1 — Dart 3.13 native tree-shaking / RecordUse

O1 is a measured optimization track. It must not interrupt UX-01 and must not destabilize the existing Flutter Rust Bridge/native build path.

Primary goal:

```text
reduce shipped native binary footprint by allowing the Dart AOT/link pipeline to retain only native symbols actually used by the application, and where possible omit an unused native library entirely.
```

Dart mechanism to evaluate:

- Dart 3.13 introduces link hooks and recorded-usage tree-shaking for native code assets.
- Packages producing native assets with `hook/build.dart` can add `hook/link.dart`.
- The compiler records referenced `@Native` usage and provides it to link hooks through `LinkInput.recordedUses`.
- Dart binding identifiers may require mapping to real native symbols before passing a retain set to the native linker.
- `symbolsToKeep == null` is the fail-safe path: preserve all symbols when recorded usage is unavailable.
- an empty retain set can allow supported linking tooling to omit an otherwise-unused dynamic library.

Official references:

```text
https://dart.dev/tools/hooks
https://dart.dev/blog/announcing-dart-3-13#tree-shaking-native-libraries-with-recorduse-and-package-record_use
```

Current repository baseline relevant to O1:

```text
Flutter/Rust integration: flutter_rust_bridge based
native-heavy packages: dxtr_pixs_engine and dxtr_pixs_gpu
native ABI names intentionally remain pixelcraft_engine / pixelcraft_gpu_native
```

O1 ordering and gates:

```text
O1.0  Entry gate
      UX-01 must satisfy every stabilization criterion in section 4.1 and be merged to main.
      PKG-01 is already complete.

O1.1  Toolchain gate
      Confirm the selected stable Flutter SDK actually ships the Dart 3.13 APIs needed by hooks/link hooks/record_use.
      Do not raise the SDK floor only from roadmap assumptions.

O1.2  Native size baseline
      Measure release binary/native contribution before migration:
      - Android APK/AAB per ABI where practical
      - iOS app/framework or archive contribution
      - macOS/Linux/Windows release artifacts when available
      Record reproducible commands and artifact sizes.

O1.3  API/build audit
      Inventory native entry points in dxtr_pixs_gpu and dxtr_pixs_engine.
      Identify which bindings are generated/owned by flutter_rust_bridge and which can participate safely in Code Assets/build hooks.
      Do not rewrite image semantics or GPU ownership.

O1.4  dxtr_pixs_gpu PoC first
      Use dxtr_pixs_gpu as the first RecordUse/native-link-tree-shaking experiment because it is isolated and its native footprint can be measured independently.
      Add only the minimum build/link-hook surface needed for the experiment.
      Establish deterministic Dart-method -> native-symbol mapping.

O1.5  Linker/LTO verification
      Verify the Rust/native artifact is produced in a form where unused symbols can actually be eliminated by the final linker.
      Check section GC/LTO/export visibility rather than assuming RecordUse alone reduces size.

O1.6  Before/after evidence
      Compare:
      - shipped binary size
      - native library size
      - release build time
      - startup/load behavior
      - runtime correctness
      - CI reproducibility

O1.7  Decision gate
      Expand to dxtr_pixs_engine only if the GPU PoC produces a material, measurable benefit without disproportionate build/release complexity.
      Otherwise retain the current flutter_rust_bridge/native integration and document the result.

O1.8  Engine expansion if approved
      Apply the proven pattern to dxtr_pixs_engine incrementally.
      Never combine this work with image-processing semantic changes, UX changes, or bundle/application identifier migration.
```

O1 acceptance criteria:

1. Existing Rust authority and GPU fail-closed contracts remain unchanged.
2. Release builds pass existing package/native verification.
3. No native symbol required at runtime is accidentally removed.
4. Size improvements are recorded with before/after artifacts, not estimated.
5. CI can reproduce the link process on supported platforms.
6. A rollback to the existing native integration remains straightforward during the PoC.
7. `flutter_rust_bridge` is not removed merely to adopt RecordUse; any binding migration requires independent technical justification.

Scheduling policy:

**Start O1 only after UX-01 is merged and stable.** Do not wait for an open-ended set of future UX work. G7B is unrelated and remains deferred indefinitely.

---

# 7. Advanced Develop / AI roadmap

Advanced Develop is a future workstream after the currently prioritized UX work and O1 decision point unless project priority is explicitly changed.

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

First backend candidate: MobileSAM through ONNX Runtime.

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

Restoration operations consume rendered RGB image data and should not depend directly on a future RAW engine. They are explicit asynchronous operations with progress/cancel and Before/After, not per-frame slider effects.

CodeFormer is not the default production candidate while upstream commercial-use licensing remains unsuitable without explicit permission.

---

# 8. G7A / G7B split

G7A is complete and merged. It covered account-independent release work: signing architecture, unsigned/no-codesign packaging, native Rust/LUT verification, version/build identity audit, privacy/permission audit, store metadata/privacy drafts, release notes/RC QA preparation, and CI release artifact generation.

G7B remains **deferred indefinitely and not scheduled**. Do not treat it as an active blocker for product/editor development and do not pause current work waiting for store accounts.

Resume G7B only after an explicit project decision.

---

# 9. Reliability / device evidence

G6 is closed/verified.

Physical-device policy remains important:

```text
main app id: dev.cnxdev.pixelcraft
DO NOT uninstall or overwrite the user's installed main app during verifier runs
temporary verifier id: dev.cnxdev.pixelcraft.g6verify
```

Known physical-device evidence:

```text
iPhone 11 UDID: 00008030-0004694C3E68C02E
10 reliability cycles: PASS
user physical observation: no notable heat / lag during that session
manual physical checklist: completed
```

Historical evidence remains under `build/g6/device` and `build/g6/final` when present in the working environment; do not rewrite historical evidence to new branding.

---

# 10. Release engineering baseline

Android:

```text
applicationId: dev.cnxdev.pixelcraft
marketing version: 0.1.0 while pre-1.0 beta/RC work continues
build: 1
minSdk: 24
targetSdk: 36
compileSdk: 36
Rust ABIs: arm64-v8a, armeabi-v7a, x86_64
release must not use debug signing
RECORD_AUDIO must remain absent
```

iOS:

```text
bundle id: dev.cnxdev.pixelcraft
deployment target: 13.0
pixelcraft_engine.framework/native integration remains required
Film/Creative GPU LUT assets remain required
release --no-codesign path is part of CI validation
```

A later bundle/application identifier migration must be handled as a deliberate release migration and must not be mixed into UX-01 or O1.

---

# 11. Verification rules

1. Never claim CI/test/device/build/store validation passed unless actually run or explicitly reported.
2. Never commit keystores, passwords, private certificates, provisioning profiles, or store credentials.
3. Never ship Android production artifacts with debug signing.
4. Release engineering must not weaken Rust authority, GPU fail-closed behavior, or package boundaries.
5. G7B is deferred indefinitely and must not be resumed without an explicit project decision.
6. Product renaming must not rewrite historical evidence as if old builds used the new identity.
7. Bundle/application identifier changes require an explicit migration decision separate from package naming.
8. Native Rust/ABI names remain unchanged unless a separate migration is justified and validated.
9. Future `dxtr_pixs_segment` / `dxtr_pixs_restore` work must land in separate reviewable PRs.
10. RecordUse/native tree-shaking work must be evidence-driven: preserve all symbols when recorded usage is unavailable, measure before/after release artifacts, and never trade runtime correctness for binary-size reduction.
11. Do not claim a branch is deleted unless GitHub confirms the ref no longer exists.

Standard verification entry points include:

```text
bash tool/check_package_boundaries.sh
make gpu-lut-verify
make verify-native
flutter analyze
flutter test
```

---

# 12. Current next action

**The package namespace migration is complete. The next product task is UX-01, the modern import/add-photo entry flow. O1 begins only after UX-01 satisfies the explicit stabilization criteria in section 4.1 and is merged.**

Recommended sequence:

```text
1. implement UX-01 as one small reviewable PR from current main
2. preserve all Rust/GPU semantic boundaries and supported acquisition/import capabilities
3. run focused widget/state tests and intentional golden updates
4. require full CI green + no unresolved review threads, then merge UX-01
5. start O1.1 toolchain confirmation and O1.2 native-size baseline
6. perform O1.3 API/build audit
7. implement the dxtr_pixs_gpu RecordUse/link-hook PoC first
8. verify linker/LTO behavior and capture before/after size/build/runtime evidence
9. expand to dxtr_pixs_engine only if the PoC shows material benefit at acceptable complexity
10. continue later product UX / segmentation / restoration work as separately prioritized slices
11. do not change dev.cnxdev.pixelcraft identifiers unless an explicit identifier-migration task is approved
12. do not resume G7B unless an explicit project decision brings it back into scope
```

Current PR hygiene:

```text
PR #29  closed without merge; superseded by #30/#32
PR #30  merged
PR #31  old RecordUse handoff PR; superseded by the refreshed post-namespace roadmap PR
PR #32  merged
```

After the refreshed roadmap PR is green and merged, delete obsolete merged/superseded branches where tooling permits and verify the remaining branch list against `main` before starting UX-01.
