# PixelCraft Project Handoff

## Purpose

Canonical continuation document for repository **PixelCraft** and product **Dextryx Pixels**.

For a new session:

1. read this file first;
2. inspect `main`, active PRs, review threads, and latest CI;
3. continue from **Current next action**;
4. repository state and exact CI/device evidence override older chat history.

Recommended continuation prompt:

```text
อ่าน docs/PROJECT_HANDOFF.md ใน repo PixelCraft แล้วทำต่อจาก Current next action
```

Last refresh: **2026-08-17 — PF0/PF1 are merged. PF2 implementation is complete on draft PR #48; physical-device validation is the remaining close gate.**

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

- user-facing product copy uses **Dextryx Pixels**;
- launcher/home-screen label uses **Dxtr Pixs**;
- repository name and app identifiers remain unchanged unless separately approved;
- native ABI/runtime/persisted schema identifiers are not branding concerns.

---

# 2. Product boundary — PixelCraft vs Nixin

## PixelCraft / Dextryx Pixels

Primary role: **camera + photo editor + image-processing product**.

Owns:

```text
mobile/tablet camera experience
editor UX/session lifecycle
Rust authoritative recipe/history/checkpoint/recovery
Film / Creative Filter / Adjust / transforms / masks
GPU preview
full-resolution render/export
editor continuity/recovery
```

PixelCraft is not the long-lived DAM/catalog product.

Do not grow PixelCraft by default into:

```text
Workplaces hierarchy
folder-ingestion/archive management
large library/catalog management
ratings/flags/keywords systems
large-scale metadata browsing/search
Lightroom-style DAM behavior
```

## Nixin / Dextryx Images

Primary role: **image manager / catalog / Workplaces product**.

Nixin owns asset identity, import/source management, Workplaces, organization, browsing, collections, and long-lived library UX.

Future Nixin -> PixelCraft editing must use an explicit versioned request/result contract. Nixin must not import PixelCraft app-internal widgets/providers.

---

# 3. Platform product policy

## Phone/tablet

Phone and tablet are **camera-first**.

```text
App launch
  -> Rust/bootstrap
  -> Camera
```

Camera shell:

```text
┌─────────────────────────────┐
│       live preview          │
│                             │
│   Film  Filter  Adjust      │
├─────────────────────────────┤
│ Gallery   SHUTTER   Controls│
└─────────────────────────────┘
```

Rules:

- bottom center = Shutter;
- bottom left = Gallery/recent source;
- bottom right = camera Controls/settings;
- Film/Filter/Adjust live in Camera context;
- verified GPU paths provide low-latency faithful preview;
- unsupported preview operations fail/fallback safely rather than diverge from Rust.

## Desktop

Desktop remains **editor/open/drop-first**, not camera-first.

```text
App launch
  -> editor/open/drop launcher
  -> Product Editor
```

Desktop remains an editor, not a DAM clone.

---

# 4. Architecture invariants

```text
Flutter   = UI / control / presentation plane
Riverpod  = UI/application orchestration
Rust      = authoritative image semantics / recipe / history / checkpoint / recovery / export
Metal     = iOS realtime GPU preview
OpenGL ES = Android realtime camera preview
```

Hard contracts:

1. Rust owns committed edits, operation semantics, history/checkpoint/recovery and full-resolution rendering/export.
2. GPU is preview-only and never final-render authority.
3. Camera preview pixels never become the saved source/result.
4. Live camera buffers never cross MethodChannel or Flutter Rust Bridge.
5. Canonical Film/Creative LUT assets are Rust-owned/generated.
6. New effects are Rust-first; GPU support is enabled only with faithful semantics.
7. Native/GPU failure fails closed.
8. Unsupported Rust operation order must not be silently reordered for GPU.
9. Riverpod may own transient interaction state but is not recipe/history authority.
10. Do not casually replace mobile Metal/OpenGL ES runtime with wgpu.
11. Long-lived image-management ownership belongs to Nixin.
12. MobileSAM/RAW remain separate future milestones.

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
PKG-02 existing-package ownership audit         PLANNED AFTER PF FLOW STABILIZES
PKG-03 camera package extraction review         DEFER UNTIL AFTER PF3

G7A Release Engineering / Store Preparation    MERGED
G7B Store Account Integration / Beta Upload    DEFERRED INDEFINITELY

UX-01 Modern Import flow                       CLOSED / VERIFIED
UX-02 Home / Workspace modernization            CLOSED / VERIFIED
W1A/W1B editor-local catalog foundation         CLOSED / VERIFIED
W1C acquisition/catalog/Home integration       CLOSED / VERIFIED
W1D DAM-style multi-item expansion              CANCELLED AS DEFAULT DIRECTION

PF0 Platform-flow foundations                   MERGED / ACTIVE FOUNDATION
PF1 Camera-first mobile/tablet shell             MERGED
PF2 Unified Camera Film/Filter/Adjust UX         IMPLEMENTED / DEVICE VALIDATION PENDING — PR #48
PF3 Capture-process-save-to-Gallery              PLANNED
PF4 Gallery-to-editor source flow                PLANNED
PF5 External edit request/result foundation      PLANNED FOUNDATION ONLY

MobileSAM / ONNX segmentation                   FUTURE / NOT ACTIVATED
Real RAW development                            FUTURE / NOT ACTIVATED
O1 Dart 3.13 native tree-shaking / RecordUse    FUTURE / DEFERRED / DO NOT START NOW
```

---

# 6. PF0/PF1 completed baseline

Recent platform-flow PRs:

```text
PR #44 docs: camera-first platform product flow               MERGED
PR #45 PF0 + PF1 platform/runtime foundation                  MERGED
PR #46 PF1 camera shell controls/adapters                     MERGED
PR #47 PF1 runtime camera wiring                              MERGED
PR #48 PF2 unified camera look                                OPEN / DRAFT
```

PF0/PF1 established the camera-first mobile shell, format-aware sources, service boundaries, EN/TH localization, Gallery handoff, camera controls, and runtime camera wiring.

PF1 runtime documentation:

```text
docs/PF1_CAMERA_RUNTIME_WIRING.md
```

---

# 7. PF2 — unified camera look milestone

Canonical PF2 docs:

```text
docs/PF2_CAMERA_LOOK_CONTRACT.md
docs/PF2_DEVICE_VALIDATION_CHECKLIST.md
```

Active branch / PR:

```text
branch: feature/pf2-unified-camera-look
PR: #48 — PF2 camera look foundation
state: OPEN / DRAFT
```

Verified implementation baseline:

```text
implementation head: b4451dce62bd877435cdab4ddd69c3f69cc037cd
CI: #420 / run 31946914217
result: SUCCESS
```

Documentation-only commits may move the branch head after the implementation baseline. Device evidence must record the actual commit installed on the device.

## PF2 camera state

`CameraLookState` contains independent layers:

```text
Film profile id + strength
Creative Filter id + strength
brightness
contrast
saturation
```

Changing Film must not clear Filter/Adjust. Changing Filter must not replace Film. Changing Adjust must not replace Film/Filter.

Canonical Creative Filter ids:

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

PF2 realtime Adjust scope is deliberately limited to:

```text
brightness
contrast
saturation
```

Ranges/defaults come from `dxtr_pixs_editing`.

## PF2 composition order

Frozen preview order:

```text
clean camera sample
 -> Adjust
 -> Film
 -> Creative Filter
 -> display
```

PF2 uses **direct ordered native shader stages**. Do not reintroduce whole-look 33³ LUT precomposition merely to preserve a one-LUT hot path; that shortcut adds another interpolation/quantization boundary and cannot claim strict sequential parity.

Film and LUT-backed Creative remain separate native resources. Brightness/contrast/saturation and exact grayscale/invert operations execute explicitly in the shader.

## PF2 preview architecture

Flutter control plane:

```text
CameraLookState
 -> CameraLookPreviewCoordinator
 -> GpuCameraLookState
 -> MethodChannel setCameraLook
```

Coordinator properties:

- complete-state dispatch;
- latest-value-wins coalescing for rapid sliders;
- generation invalidation on detach;
- stale native update prevention;
- fail-closed error callback;
- `flush()` before shutter capture.

MethodChannel remains:

```text
dev.pixelcraft/gpu_preview_v1
```

`setCameraLook` carries only configuration. Camera pixel buffers remain native.

Native preview:

```text
Android Camera2/OES
 -> async Film/Creative resource preparation
 -> native generation guard
 -> separate Film + Creative LUT atlas textures
 -> GLES shader Adjust -> Film -> Creative

iOS Metal
 -> async Film/Creative resource preparation
 -> native generation guard
 -> separate Film + Creative 3D LUT textures
 -> Metal shader Adjust -> Film -> Creative
```

## PF2 UI activation

Real Camera controls now exist for:

```text
Film
Filter: Original + grayscale/invert + six LUT-backed presets + intensity
Adjust: brightness / contrast / saturation
```

Rules:

- Film/Filter/Adjust switching preserves accumulated look state;
- Filter/Adjust are exposed only when faithful native preview is available;
- fallback Camera remains Film-only;
- native runtime failure reduces visible/active state to Film-only;
- EN/TH labels are supported.

## Temporary capture -> editor handoff

PF3 is not implemented yet.

PF2 currently does:

```text
flush final preview state
 -> snapshot CameraLookState
 -> clean JPEG capture
 -> CameraFilmEditorHandoff
 -> Rust-backed editor replay
```

Replay order:

```text
brightness
contrast
saturation
Film
Creative
```

Gallery-picked sources remain neutral and never inherit Camera look state automatically.

## PF2 automated verification

The implementation baseline `b4451dce...` passed CI #420 / run `31946914217`, including:

- Flutter analyze/tests;
- Rust fmt/clippy/tests + G6 image characterization;
- GPU LUT parity;
- editing/film/GPU package analyze/tests;
- Golden tests;
- Android release artifact + Rust native packaging;
- iOS Rust plugin packaging smoke;
- iOS release no-codesign;
- wgpu core Windows/Linux/macOS.

## PF2 current gate

Physical-device validation is the remaining gate.

Run:

```text
docs/PF2_DEVICE_VALIDATION_CHECKLIST.md
```

Required areas:

```text
launch/basic camera
neutral bypass
Film selection/strength
Creative Filters
brightness/contrast/saturation sliders
Film + Filter + Adjust coexistence
rapid-switch / stale-state stress
sustained preview / frame pacing / thermal observation
lens switching
lifecycle pause/resume
shutter + temporary capture/editor handoff
Gallery source neutrality
runtime fail-closed fallback where safely inducible
EN/TH controls
regression smoke
```

PF2 must remain Draft until this checklist passes and device/performance evidence is recorded.

---

# 8. PF3 target capture flow

PF3 changes the temporary PF2 capture -> editor behavior.

Target:

```text
clean camera capture
+ selected Film / Filter / Adjust configuration
 -> Rust authoritative full-resolution render
 -> JPEG output
 -> MediaSaveService
 -> system Gallery
 -> remain in Camera
```

Hard rules:

1. source capture remains clean internally;
2. preview framebuffer is never final authority;
3. PF3 camera output is JPEG;
4. shutter does not force editor navigation;
5. camera remains active after save;
6. recent thumbnail/confirmation may update;
7. user may explicitly open captured result in editor.

---

# 9. Gallery/source policy

Gallery/external source remains immutable input.

```text
JPEG source -> stays JPEG source
PNG source  -> stays PNG source
WebP source -> stays WebP source
future RAW  -> stays RAW source
```

Processed output is separate from source preservation.

PixelCraft does not own Nixin-style long-lived source/catalog identity.

---

# 10. Persistence boundaries

```text
EditorSessionStore
 = coherent edit-session recovery

WorkspaceCatalogStore
 = bounded editor-local source/reopen metadata

AppPreferencesStore
 = lightweight user/UI preferences

filesystem/system Gallery
 = image files

Rust recipe/history
 = authoritative editing semantics
```

Do not add Hive/general database without a concrete requirement.

Do not expand `WorkspaceCatalogStore` into Workplaces/DAM behavior.

---

# 11. Package policy

Current packages:

```text
dxtr_pixs_film
dxtr_pixs_gpu
dxtr_pixs_editing
dxtr_pixs_engine
```

Prefer consolidating ownership into these packages before creating more packages.

`dxtr_pixs_camera` extraction is deferred until **after PF3**, when capture/runtime/processing-handoff contracts are stable.

Future-only package directions:

```text
dxtr_pixs_segment
dxtr_pixs_restore
dxtr_pixs_raw
```

Do not create empty placeholders before their milestones activate.

---

# 12. Deferred work

## G7B

**DEFERRED INDEFINITELY / NOT SCHEDULED.**

## Dart 3.13 RecordUse/native tree-shaking

**FUTURE / DEFERRED / DO NOT START NOW.**

Plan:

```text
docs/FUTURE_DART_3_13_NATIVE_TREE_SHAKING.md
```

## MobileSAM / ONNX

**FUTURE / NOT ACTIVATED.**

Segmentation creates masks; it is not committed-image authority.

## Real RAW development

**FUTURE / NOT ACTIVATED.**

PF source contracts should remain RAW-aware, but do not implement real RAW development as part of PF2/PF3.

---

# 13. Reliability/device evidence

G6 remains closed/verified.

```text
main app id: dev.cnxdev.pixelcraft
temporary G6 verifier id: dev.cnxdev.pixelcraft.g6verify
iPhone 11 UDID: 00008030-0004694C3E68C02E
10 reliability cycles: PASS
manual physical checklist: completed
```

Do not rewrite historical evidence to newer branding.

Avoid destructive uninstall/overwrite behavior during verifier-style validation.

PF2 device evidence is separate from historical G6 evidence and must be recorded against the tested PF2 commit.

---

# 14. Verification rules

1. Never claim CI/test/device/build/store validation passed unless actually run or explicitly reported.
2. A PR head being green is not enough to close a slice; verify resulting `main` CI after merge.
3. Never commit signing secrets, certificates, provisioning profiles, passwords, or store credentials.
4. Never weaken Rust authority or GPU fail-closed behavior.
5. Do not silently approximate unsupported preview semantics.
6. Camera pixels never cross MethodChannel.
7. Gallery/external sources remain untouched.
8. Riverpod remains UI/application orchestration only.
9. Do not start MobileSAM, real RAW, G7B or Dart 3.13 O1 work as part of PF2.
10. Do not extract `dxtr_pixs_camera` before PF3 stabilizes the boundary.

Standard verification:

```text
bash tool/check_package_boundaries.sh
make gpu-lut-verify
make verify-native
flutter analyze
flutter test
```

PF2 closure additionally requires the complete physical-device checklist.

---

# 15. Current next action

Continue **PF2 on PR #48 / `feature/pf2-unified-camera-look`**.

Do not create another branch unless a genuinely separate scope requires it.

Current state:

```text
PF2 implementation: DONE
implementation CI baseline: GREEN
physical-device validation: PENDING
PR #48: OPEN / DRAFT
```

Immediate order:

```text
1. Run docs/PF2_DEVICE_VALIDATION_CHECKLIST.md on physical iOS/Android hardware available.
2. Record exact device, OS, build mode, tested commit, frame-pacing and thermal observations.
3. Record Film/Filter/Adjust correctness, stress, lifecycle, lens-switching, capture/editor handoff and Gallery-neutrality results.
4. If a real device regression is found, fix only the observed issue and rerun the affected automated/device gates.
5. After device PASS, update PROJECT_HANDOFF / CODE_WALKTHROUGH / PF2 contract / README with final evidence.
6. Mark PR #48 Ready only after device validation passes.
7. Merge only after the final PR head is green.
8. After merge, verify resulting main CI and clean the merged feature branch.
```

After PF2:

```text
PF3 capture -> Rust authoritative render -> JPEG -> Gallery -> remain Camera
 -> evaluate PKG-03 camera extraction only after PF3 contracts stabilize
 -> PF4 Gallery source -> editor -> export
 -> PF5 versioned external-edit foundation
```
