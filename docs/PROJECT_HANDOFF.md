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

Last refresh: **2026-08-16 — PF0/PF1 are merged. PF2 unified Camera Film/Filter/Adjust is active on draft PR #48.**

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

Current PF1 launch target is active:

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
PF2 Unified Camera Film/Filter/Adjust UX         IN PROGRESS — PR #48
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

PR #45 established:

- easy_localization EN/TH foundation and English fallback;
- format-aware source descriptor;
- typed processing job/failure model;
- preferences abstraction;
- media/permission/capability service boundaries;
- route intent boundary;
- iOS/Android camera-first root after Rust bootstrap;
- desktop/web remain editor/Home/open-oriented.

PR #46 established:

- reusable `CameraPrimaryControls`;
- Film / Filter / Adjust selector shell;
- bottom hierarchy Gallery / Shutter / Controls;
- concrete media picker/save adapters;
- capture-action lockout;
- EN/TH camera-shell localization keys.

PR #47 established:

- PF1 camera-first runtime screen on mobile/tablet;
- Gallery -> existing editor handoff through `MediaPickerService`;
- Gallery source stays untouched and does not inherit camera Film automatically;
- real bounded Controls sheet and camera switch when available;
- Film remains the only fully active PF1 camera look tool;
- PF1 Filter/Adjust placeholders intentionally defer to PF2;
- capture still opens editor until PF3.

PF1 runtime documentation:

```text
docs/PF1_CAMERA_RUNTIME_WIRING.md
```

---

# 7. PF2 — active unified camera look milestone

Canonical PF2 contract:

```text
docs/PF2_CAMERA_LOOK_CONTRACT.md
```

Active branch / PR:

```text
branch: feature/pf2-unified-camera-look
PR: #48 — PF2 camera look foundation
state: OPEN / DRAFT
```

## PF2 camera state

`lib/camera/camera_look_state.dart` defines transient `CameraLookState`.

Independent layers:

```text
Film profile id + strength
Creative Filter id + strength
brightness
contrast
saturation
```

Changing Film must not clear Filter/Adjust. Changing Filter must not replace Film.

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

Canonical GPU LUT assets for preset filters:

```text
creative_vintage
creative_oceanic
creative_lofi
creative_dramatic
creative_golden
creative_pastel_pink
```

The `creative_` prefix is GPU asset plumbing only. Rust recipe ids remain the canonical filter ids.

## PF2 Adjust scope

Initial realtime Camera Adjust support is deliberately limited to:

```text
brightness
contrast
saturation
```

Ranges/defaults come from `dxtr_pixs_editing`; do not duplicate them in camera UI logic.

## PF2 composition order

Frozen preview order:

```text
clean camera sample
 -> Adjust
 -> Film
 -> Creative Filter
 -> display
```

Existing editor-GPU formulas are the reference semantics.

Brightness:

```text
color = clamp(color + (brightness - 1.0), 0.0, 1.0)
```

Contrast:

```text
midpoint = 128.0 / 255.0
color = clamp((color - midpoint) * contrast + midpoint, 0.0, 1.0)
```

Saturation:

```text
luminance = dot(color, [0.2126, 0.7152, 0.0722])
color = clamp(luminance + (color - luminance) * saturation, 0.0, 1.0)
```

`grayscale` and `invert` retain exact rounded-u8 editor semantics. Do not substitute luminance grayscale or approximate LUTs.

## PF2 preview architecture

Flutter control plane:

```text
CameraLookState
 -> CameraLookPreviewCoordinator
 -> GpuCameraLookState
 -> MethodChannel setCameraLook
```

Coordinator properties:

- latest-value-wins coalescing for rapid sliders;
- generation invalidation on detach;
- stale native update prevention;
- fail-closed error callback;
- full state dispatch rather than partial Film/Filter overwrite messages.

MethodChannel remains:

```text
dev.pixelcraft/gpu_preview_v1
```

`setCameraLook` carries only configuration. Camera pixel buffers remain native.

Native contracts:

```text
Android: NativeGpuCameraLook.kt
iOS:     NativeGpuCameraLook.swift
```

Native camera-look composers now exist on Android and iOS. Their role is to pre-compose a 33³ LUT when look state changes:

```text
identity color
 -> Adjust
 -> Film LUT blend
 -> Creative exact op or Creative LUT blend
 -> composed 33³ LUT
```

Reason: retain the existing single-LUT camera shader hot path instead of running a multi-stage Flutter-driven pipeline per frame.

## PF2 current activation state

Android channel/session accepts `setCameraLook`.

Non-neutral look state currently remains intentionally fail-closed until `AndroidGpuCameraOesRenderer` actually consumes the composed LUT. Do not change this to silent success.

The iOS Metal camera renderer also still needs composed-LUT activation.

PF2 Filter/Adjust UI must remain non-fake until the active capability path can actually apply the composed look.

## PF2 verification evidence

Verified PR #48 CI checkpoints before the latest composer head:

```text
CI #387  success
CI #390  success
CI #392  success
CI #394  success
```

Latest composer head at this refresh:

```text
3ac954558f8ed7a70f4f9caea10c440050789390
```

CI #396 was started for that head. **Do not mark #396 green unless GitHub reports success.**

---

# 8. PF3 target capture flow

PF3 changes the temporary PF1 capture -> editor behavior.

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

Until PF3 lands, temporary capture -> editor handoff must preserve the selected look accurately if PF2 exposes it.

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

Do not create generic low-cohesion utility packages merely to reduce directory size.

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

PF2-specific validation must include:

```text
Film + Filter coexistence
Film + Filter + Adjust coexistence
neutral look bypass
rapid Film/Filter switching
continuous adjustment sliders
latest-value-wins / stale-update protection
missing LUT/native failure -> fail closed
native camera lifecycle/switch/capture regression
physical-device preview responsiveness
```

---

# 15. Current next action

Continue **PF2 on PR #48 / `feature/pf2-unified-camera-look`**.

Do not create another branch unless a genuinely separate scope requires it.

Immediate order:

```text
1. Verify latest PR #48 CI head first.
2. If green, connect Android camera-look composer output to AndroidGpuCameraOesRenderer.
3. Connect iOS camera-look composer output to MetalCameraPreviewRenderer.
4. Remove temporary non-neutral fail-closed activation gate only after real renderer consumption exists.
5. Preserve composition order Adjust -> Film -> Creative.
6. Keep the existing single-LUT-per-frame camera shader hot path where possible.
7. Wire Camera Filter and Adjust controls to CameraLookPreviewCoordinator only after native support is real.
8. Ensure Film/Filter/Adjust state survives tool switching independently.
9. Add rapid-switch, continuous-slider, neutral, native-failure and lifecycle regression tests.
10. Validate on physical iPhone 11/reference mobile hardware.
11. Update this handoff, CODE_WALKTHROUGH, PF2 contract and README before closing PF2.
12. When PR #48 is complete and exact-head CI is green, mark ready for review/merge; after merge verify resulting main CI and clean merged branch.
```

After PF2:

```text
PF3 capture -> Rust authoritative render -> JPEG -> Gallery -> remain Camera
 -> evaluate PKG-03 camera extraction only after PF3 contracts stabilize
 -> PF4 Gallery source -> editor -> export
 -> PF5 versioned external-edit foundation
```
