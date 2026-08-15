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

Last refresh: **2026-08-15, after PR #30 package-namespace migration and PR #32 post-namespace branding-test repair; PR #33 refreshes this handoff, defines UX-01, and records Dart 3.13 native tree-shaking as a future/deferred optimization. G7B remains deferred indefinitely.**

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

Relevant merged work:

```text
PR #27  product identity
PR #30  dxtr_pixs_* reusable package namespace
PR #32  post-namespace branding tests/golden repair
```

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
11. AI segmentation/restoration stays an optional capability layer and does not become committed-image authority.
12. Do not casually replace the mobile runtime with wgpu. Cross-platform wgpu CI may exist, but product runtime remains Metal/OpenGL ES unless deliberately redesigned.

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
PKG-01 dxtr_pixs_* namespace consolidation     COMPLETE / PR #30

G7A Release Engineering / Store Preparation    MERGED
G7B Store Account Integration / Beta Upload    DEFERRED INDEFINITELY / NOT SCHEDULED

Post-G7A Product / Editor UX                   ACTIVE
UX-01 Modern import/add-photo entry flow        NEXT UX GATE
O1 Dart 3.13 native tree-shaking / RecordUse   FUTURE / DEFERRED / DO NOT START NOW
```

Historical G7 PR #10 is closed/superseded. Do not reopen it.

---

# 4. Post-G7A product/editor work

Merged slices:

```text
PR #20  discoverable Before/After Compare
PR #21  Film library search/origin filters
PR #22  Compare session/wide-layout fix
PR #23  discoverable Zoom / Fit controls
PR #24  precise numeric adjustment entry
PR #25  histogram channel inspector
PR #26  precise straighten angle entry
PR #27  Dextryx Pixels / Dxtr Pixs identity
PR #30  dxtr_pixs_* package namespace
PR #32  branding test/golden repair
```

These are product/presentation changes only and do not move semantic authority away from Rust.

## 4.1 UX-01 — Modern import/add-photo entry flow

Problem being replaced:

```text
primary Add Photo
 -> implementation-oriented three-choice source menu
 -> user chooses a source/mode
 -> actual image task begins
```

Target normal path:

```text
primary Add / Import
 -> directly enter the preferred platform picker/import path
```

The normal primary action **must bypass the current three-choice source menu**. Secondary acquisition modes may remain available through progressive disclosure, contextual actions, overflow/secondary affordances, or appropriate platform-native picker capabilities.

Scope:

- one obvious primary add/import action;
- normal primary action bypasses the current three-choice menu;
- preserve all currently supported acquisition/import capabilities through secondary paths;
- keep transitions image-first and spatially coherent;
- compact dark digital-darkroom UI, restrained motion, no generic oversized cards;
- no Rust image-semantic change;
- no package/ABI/channel/applicationId/bundle-id migration.

UX-01 stabilization criteria:

```text
[ ] tapping the normal primary Add / Import action does NOT open the existing three-choice source menu
[ ] the normal primary action enters the preferred picker/import path directly
[ ] alternate supported acquisition/import routes remain reachable through secondary disclosure
[ ] tests explicitly fail if the old three-choice menu returns to the normal primary path
[ ] no regression to editor/camera semantic commit paths
[ ] no expensive synchronous work is introduced on the tap/gesture path
[ ] focused widget/state tests cover primary and secondary paths
[ ] affected goldens are intentionally refreshed and reviewed
[ ] full CI is green on the final UX-01 head
[ ] no unresolved review thread remains
[ ] UX-01 is merged to main
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

---

# 5. Package graph and naming

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

# 6. Future O1 — Dart 3.13 RecordUse / native tree-shaking

**Status: FUTURE / DEFERRED / DO NOT START NOW.**

O1 is a future evidence-driven binary-size/build-architecture optimization. It is **not** part of the current next action and must not interrupt Product / Editor UX work.

Do not change the Dart SDK constraint, Flutter baseline, Flutter Rust Bridge integration, native build pipeline, Rust ABI, or release packaging merely to start O1.

Detailed rationale, start conditions, phased implementation plan, acceptance criteria, and rollback conditions are maintained in:

```text
docs/FUTURE_DART_3_13_NATIVE_TREE_SHAKING.md
```

Why it is retained on the roadmap:

- Dart 3.13 adds link hooks and recorded native usage through `LinkInput.recordedUses` for `@Native` references;
- a supported link path can retain only native symbols actually needed by the application;
- an empty retain set can allow an unused native code asset to be omitted where the build/link pipeline supports it;
- this may reduce future Rust/native binary growth as Dextryx Pixels adds modular native capabilities.

Official references:

```text
https://dart.dev/tools/hooks
https://dart.dev/blog/announcing-dart-3-13#tree-shaking-native-libraries-with-recorduse-and-package-record_use
```

Current binding reality:

```text
mobile dxtr_pixs_gpu runtime:
  Kotlin/Swift plugin registration + MethodChannel/PlatformView paths

pixelcraft_gpu_native / wgpu surface:
  desktop-oriented native library
  Dart currently uses DynamicLibrary.lookupFunction rather than recorded @Native references

dxtr_pixs_engine:
  Flutter Rust Bridge / Rust native path contributes to mobile release artifacts
```

Future activation order, only after an explicit project decision:

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

Important guards:

1. Preserve all native symbols if recorded usage is unavailable or ambiguous.
2. Do not remove `flutter_rust_bridge` merely to enable RecordUse.
3. A desktop GPU PoC must not block or substitute for Android/iOS engine evaluation.
4. Rust authority, deterministic export, and GPU fail-closed behavior remain unchanged.
5. No adoption without measured before/after binary evidence.
6. Re-verify the official Dart/Flutter hook documentation when the track is eventually activated.

---

# 7. Advanced Develop / AI roadmap

This remains a future workstream unless priority is explicitly changed.

```text
Advanced Develop
├── conventional / future RAW development
└── AI Restoration
    ├── Face Enhance
    ├── AI Denoise
    └── Super-Resolution
```

Planned boundaries:

- `dxtr_pixs_segment`: local segmentation, first backend candidate MobileSAM/ONNX Runtime;
- `dxtr_pixs_restore`: explicit async restoration operations such as SR/denoise/face enhance;
- `dxtr_pixs_raw`: only when a real RAW pipeline proves a clean package boundary.

These packages must not silently become committed-image authority.

---

# 8. G7A / G7B

G7A is complete and merged.

G7B is **deferred indefinitely / not scheduled**. Do not treat it as an active blocker and do not resume it without an explicit project decision.

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

Identifier migration is separate from UX-01 and future O1.

---

# 11. Verification rules

1. Never claim CI/test/device/build/store validation passed unless actually run or explicitly reported.
2. Never commit signing secrets, certificates, provisioning profiles, passwords, or store credentials.
3. Never ship Android production artifacts with debug signing.
4. Do not weaken Rust authority, GPU fail-closed behavior, or package boundaries.
5. G7B remains deferred until explicitly resumed.
6. Bundle/application identifier migration is a separate release task.
7. Native Rust/ABI names remain stable unless separately justified and validated.
8. O1 / RecordUse is **future/deferred** and must not be started without an explicit activation decision.
9. If O1 is eventually activated, preserve symbols when usage information is unavailable or ambiguous.
10. Do not claim a remote branch is deleted unless GitHub confirms the ref no longer exists.

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

**Get the refreshed roadmap PR green, merge it, then implement UX-01. Dart 3.13 native tree-shaking is explicitly future/deferred and must not be started now.**

Recommended sequence:

```text
1. repair test/golden/goldens/home_phone.png from a valid macOS actual test image
2. require PR #33 full CI green and no unresolved review threads
3. merge PR #33
4. implement UX-01 from current main
5. primary Add / Import must bypass the old three-choice source menu
6. preserve alternate supported acquisition/import routes through secondary disclosure
7. merge UX-01 only after focused tests + intentional goldens + full CI green
8. continue subsequent Product / Editor UX work according to project priority
9. DO NOT start FNT/O1 Dart 3.13 native tree-shaking until an explicit future activation decision
10. do not change dev.cnxdev.pixelcraft identifiers unless explicitly approved
11. do not resume G7B unless explicitly brought back into scope
```

Future O1 planning reference only:

```text
docs/FUTURE_DART_3_13_NATIVE_TREE_SHAKING.md
```

PR hygiene:

```text
PR #29  closed, superseded by #30/#32
PR #30  merged
PR #31  closed, superseded by #33
PR #32  merged
PR #33  active refreshed roadmap / CI repair
```

After #33 merges, remove obsolete merged/superseded remote branches where tooling permits and verify the remaining branch list before starting UX-01.
