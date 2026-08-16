# PixelCraft Code Walkthrough

Repository: **PixelCraft**  
Product: **Dextryx Pixels**

Last refresh: **2026-08-16 — PF0/PF1 merged; PF2 active on PR #48.**

---

## 1. Product scope

PixelCraft is the **camera + photo editor + image-processing product**.

It owns:

- phone/tablet camera UX;
- editor UX/session lifecycle;
- Rust-authoritative recipe/history/checkpoint/recovery semantics;
- Film / Creative Filter / Adjust / transforms / masks;
- realtime GPU preview where faithful;
- full-resolution render/export;
- bounded editor recovery/source reopening continuity.

Nixin / Dextryx Images remains the separate image-management/Workplaces product.

---

## 2. Current platform shell

### Phone/tablet

PF1 is merged and the runtime is camera-first after Rust bootstrap.

```text
launch
 -> bootstrap Rust
 -> Camera
    ├── Film / Filter / Adjust
    └── Gallery / Shutter / Controls
```

PF1 currently provides:

- Gallery as the left bottom action;
- Shutter as the primary center action;
- bounded Controls/settings at bottom right;
- Film as a working camera look tool;
- Filter/Adjust tab positions reserved for PF2;
- Gallery -> existing editor handoff;
- clean camera capture path;
- temporary capture -> editor behavior until PF3.

### Desktop

Desktop remains editor/open/drop-first and does not use the mobile camera-first root.

---

## 3. PF0/PF1 foundation

Merged PRs:

```text
#45 PF0/PF1 platform foundation
#46 PF1 camera shell controls/adapters
#47 PF1 runtime camera wiring
```

PF0/PF1 established:

- `easy_localization` EN/TH foundation + English fallback;
- Riverpod as application/UI orchestration;
- format-aware source descriptor;
- typed processing job/failure model;
- `AppPreferencesStore` abstraction;
- media picker/save, permission and capability boundaries;
- route intent boundary;
- camera-first mobile/tablet routing;
- desktop/editor-first routing policy.

Do not move canonical edit semantics into Riverpod or screen state.

---

## 4. Current camera shell files

Primary runtime camera implementation remains based on the existing verified camera stack.

Key application files include:

```text
lib/ui/screens/camera_film_preview_screen.dart
lib/ui/screens/camera_film_preview_screen_g1.dart
lib/ui/camera/camera_primary_controls.dart
lib/camera/camera_film_editor_handoff.dart
```

PF2 adds:

```text
lib/camera/camera_look_state.dart
```

`CameraPrimaryTool` models:

```text
film
filter
adjust
```

PF1 deliberately did not fake Filter/Adjust functionality. PF2 is replacing those placeholders only after native preview support is real.

---

## 5. Camera authority model

```text
Flutter Camera UI
      ↓ transient control state
CameraLookState / coordinator
      ↓ configuration only
native GPU preview
      ↓ preview pixels only
screen

clean capture
      ↓
Rust authoritative processing
      ↓
full-resolution output
```

Rules:

- live camera frames stay native;
- no live pixel buffers cross MethodChannel;
- GPU state is not recipe/history authority;
- camera capture remains clean internally;
- Rust remains authoritative for final saved pixels.

---

## 6. PF2 `CameraLookState`

File:

```text
lib/camera/camera_look_state.dart
```

`CameraLookState` is transient camera interaction state.

It contains independent layers:

```text
filmProfileId
filmStrength
creativeFilterId
creativeFilterStrength
adjustments:
  brightness
  contrast
  saturation
```

Important behavior:

- changing Film preserves Creative + Adjust;
- changing Creative preserves Film + Adjust;
- changing Adjust preserves Film + Creative;
- Film/Creative strength clamps to `0.0 ... 1.0`;
- adjustment ranges/defaults come from `dxtr_pixs_editing`;
- state is not persisted as authoritative edit history.

Canonical Creative ids:

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

---

## 7. Camera preview coordinator

PF2 introduces a coordinator between UI state and native camera preview.

Conceptually:

```text
CameraLookState
  ↓
CameraLookPreviewCoordinator
  ↓ coalesce / latest-value-wins
GpuCameraLookState
  ↓
CameraLookPreviewBridge.setCameraLook
```

Responsibilities:

- coalesce rapid slider events;
- latest-value-wins dispatch;
- generation invalidation on detach;
- reject stale completion/state resurrection;
- fail closed on native preview errors;
- send full composed state rather than independent single-effect messages.

This is especially important for continuous Adjust sliders.

---

## 8. Flutter/native camera-look bridge

Package:

```text
packages/dxtr_pixs_gpu/
```

Dart bridge:

```text
packages/dxtr_pixs_gpu/lib/camera_look_preview_bridge.dart
```

Channel:

```text
dev.pixelcraft/gpu_preview_v1
```

Method:

```text
setCameraLook
```

Payload:

```text
protocolVersion
rendererId
filmProfileId
filmStrength
creativeFilterId
creativeFilterStrength
brightness
contrast
saturation
```

Only control-plane data crosses the channel.

---

## 9. Native camera-look contracts

Android:

```text
packages/dxtr_pixs_gpu/android/src/main/kotlin/dev/pixelcraft/pixelcraft/NativeGpuCameraLook.kt
```

iOS:

```text
packages/dxtr_pixs_gpu/ios/Classes/NativeGpuCameraLook.swift
```

These native value objects:

- parse the same payload shape;
- clamp strengths/adjustments;
- whitelist canonical Creative Filter ids;
- expose neutral/active state;
- map preset Creative Filter ids to `creative_*` LUT assets.

Android `GpuPreviewChannel` and session layer now recognize `setCameraLook`.

Until renderer activation is complete, non-neutral Android look state intentionally fails closed rather than reporting success while displaying only part of the requested look.

---

## 10. PF2 composition order

Preview order is frozen as:

```text
Adjust
 -> Film
 -> Creative Filter
```

This must match the authoritative operation semantics used for the eventual PF3 render path.

Do not reorder merely because a GPU implementation is easier.

---

## 11. Adjustment semantics

PF2 camera Adjust initially supports only:

```text
brightness
contrast
saturation
```

These reuse the editor GPU parity formulas.

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

Other editor adjustments are not enabled in Camera until parity/performance are proven.

---

## 12. Creative Filter semantics

### Exact filters

`grayscale` and `invert` keep exact rounded-u8 semantics from the existing editor GPU path.

Grayscale:

```text
source8 = round(source * 255)
average = (r + g + b) / 3
effected8 = [average, average, average]
```

Invert:

```text
effected8 = 255 - source8
```

Do not substitute luminance grayscale.

### LUT-backed presets

```text
vintage     -> creative_vintage
oceanic     -> creative_oceanic
lofi        -> creative_lofi
dramatic    -> creative_dramatic
golden      -> creative_golden
pastel_pink -> creative_pastel_pink
```

The `creative_` names are GPU assets only. Rust operation ids remain unprefixed.

---

## 13. Camera-look LUT composers

PF2 now includes native composed-look builders on Android and iOS.

They precompute a 33³ LUT when camera look state changes:

```text
identity color
 -> brightness/contrast/saturation
 -> Film LUT + strength
 -> Creative exact op or Creative LUT + strength
 -> composed LUT texel
```

Why pre-compose:

- preserve the verified single-LUT camera shader hot path;
- avoid doing multi-stage Dart/native coordination per frame;
- keep frame data native;
- reduce risk of Film/Filter overwrite bugs;
- keep look updates bounded to state changes rather than every frame.

---

## 14. Existing camera renderers

Android camera renderer:

```text
packages/dxtr_pixs_gpu/android/src/main/kotlin/dev/pixelcraft/pixelcraft/AndroidGpuCameraOesRenderer.kt
```

Current established architecture:

```text
Camera2
 -> external OES texture
 -> OpenGL ES shader
 -> 33³ LUT atlas sampling
 -> PlatformView Surface
```

Still capture uses a separate JPEG `ImageReader` and remains clean.

iOS camera renderer:

```text
packages/dxtr_pixs_gpu/ios/Classes/MetalCameraPreviewRenderer.swift
```

Current established architecture:

```text
AVFoundation video frames
 -> CVMetalTexture
 -> Metal camera fragment shader
 -> 33³ LUT texture sample
 -> MTKView
```

Still capture uses `AVCapturePhotoOutput` and remains clean.

PF2 next connects the new composed LUTs to these existing renderers rather than replacing the camera stacks.

---

## 15. Existing editor GPU semantics as PF2 parity source

The editor GPU path remains the reference for exact adjustment and Creative Filter semantics.

Relevant file:

```text
packages/dxtr_pixs_gpu/ios/Classes/MetalFilmLutLoader.swift
```

The editor path already verifies:

- brightness/contrast/saturation formulas;
- Film LUT sampling;
- grayscale/invert exact operations;
- Creative LUT assets.

PF2 reuses these semantics; it does not invent a separate camera color model.

---

## 16. Current PF2 activation state

Implemented:

```text
CameraLookState
canonical filter mapping
bounded adjustment mapping
CameraLookPreviewBridge
latest-value-wins coordinator
stale/detach guards
Android/iOS native camera-look contracts
Android setCameraLook channel/session routing
Android/iOS composed 33³ LUT builders
unit/contract tests for state/bridge/coordinator
```

Still pending:

```text
AndroidGpuCameraOesRenderer consumes composed LUT
MetalCameraPreviewRenderer consumes composed LUT
temporary fail-closed activation gate removal
real Camera Filter controls
real Camera Adjust controls
rapid-switch/continuous-slider native regression coverage
physical-device validation
```

---

## 17. PF3 capture target

PF3 is intentionally separate from PF2.

Target:

```text
clean capture
+ selected CameraLookState
 -> Rust authoritative full-resolution render
 -> JPEG
 -> MediaSaveService
 -> system Gallery
 -> remain in Camera
```

PF2 must not save the live preview framebuffer as the result.

Until PF3 lands, the temporary capture -> editor path remains, but once PF2 exposes multiple look layers the handoff must preserve the selected configuration accurately.

---

## 18. Gallery/source flow

Gallery source is immutable input.

```text
Gallery
 -> MediaPickerService
 -> format-aware source descriptor
 -> Product Editor
 -> Rust session
 -> export/save as separate result
```

Do not rewrite the selected source.

---

## 19. Persistence boundaries

```text
EditorSessionStore
 = editing-session recovery

WorkspaceCatalogStore
 = bounded editor-local source/reopen metadata

AppPreferencesStore
 = user/UI preferences

Rust recipe/history
 = edit authority
```

Do not turn `WorkspaceCatalogStore` into Nixin-style Workplaces/DAM.

---

## 20. Package graph

```text
PixelCraft App
 ├── dxtr_pixs_film
 ├── dxtr_pixs_gpu
 ├── dxtr_pixs_editing
 └── dxtr_pixs_engine
```

`dxtr_pixs_camera` extraction is deferred until after PF3 stabilizes camera runtime/capture/handoff contracts.

Future-only directions:

```text
dxtr_pixs_segment
dxtr_pixs_restore
dxtr_pixs_raw
```

---

## 21. Verification gates

Standard:

```bash
bash tool/check_package_boundaries.sh
make gpu-lut-verify
make verify-native
flutter analyze
flutter test
```

PF2-specific:

- Film + Creative coexistence;
- Film + Creative + Adjust coexistence;
- neutral look path;
- rapid tab/preset switching;
- continuous sliders;
- latest-value-wins/stale prevention;
- missing LUT/native failure fail-closed behavior;
- camera lifecycle/switch/capture regressions;
- physical-device responsiveness.

Verified PR #48 CI checkpoints before the current composer head:

```text
#387 success
#390 success
#392 success
#394 success
```

At this walkthrough refresh, CI #396 exists for the latest composer head and must not be called green until GitHub confirms it.

---

## 22. Current continuation point

Continue **PF2 on PR #48 / `feature/pf2-unified-camera-look`**.

Immediate sequence:

```text
verify latest PR head CI
 -> connect composed LUT to AndroidGpuCameraOesRenderer
 -> connect composed LUT to MetalCameraPreviewRenderer
 -> remove temporary non-neutral activation gate
 -> wire real Camera Filter/Adjust controls
 -> regression tests
 -> physical-device validation
 -> sync README/handoff/walkthrough
 -> exact-head green
 -> ready/merge
 -> resulting main CI
```

See `docs/PF2_CAMERA_LOOK_CONTRACT.md` for the detailed camera look contract and `docs/PROJECT_HANDOFF.md` for canonical project continuation/status.
