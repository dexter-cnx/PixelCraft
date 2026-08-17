# PixelCraft Code Walkthrough

Repository: **PixelCraft**  
Product: **Dextryx Pixels**

Last refresh: **2026-08-17 — PF0/PF1 merged; PF2 implementation is complete on PR #48 and physical-device validation is the remaining close gate.**

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

PF2 now provides real Film / Filter / Adjust controls on the verified native GPU path. Filter/Adjust are not exposed on a fallback path that cannot preview them faithfully.

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
lib/camera/camera_look_state.dart
lib/camera/camera_look_preview_coordinator.dart
```

`CameraPrimaryTool` models:

```text
film
filter
adjust
```

PF2 replaces the old PF1 Filter/Adjust placeholders with real controls only when the native GPU path can apply them faithfully.

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
- send full complete state rather than independent single-effect messages;
- `flush()` before shutter capture so handoff observes the final interaction state.

Native renderers also use generation guards around asynchronous Film/Creative LUT preparation.

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

## 9. Native ordered preview architecture

PF2 deliberately does **not** pre-compose the whole look into one 33³ LUT.

The native preview executes semantic stages directly:

```text
clean camera sample
 -> Adjust
 -> Film
 -> Creative Filter
 -> display
```

Reason: whole-look precomposition would introduce an additional interpolation/quantization layer and cannot claim strict sequential parity with Rust, especially for exact grayscale/invert behavior.

### Android / OpenGL ES

```text
setCameraLook
 -> GpuPreviewRendererSessionRegistry
 -> AndroidGpuCameraOesRenderer
 -> async Film/Creative LUT atlas preparation
 -> native generation guard
 -> GL upload to independent Film + Creative texture slots
 -> OES fragment shader: Adjust -> Film -> Creative
```

Texture roles:

```text
texture0 = camera OES frame
texture1 = Film LUT atlas
texture2 = Creative LUT atlas
```

### iOS / Metal

```text
setCameraLook
 -> GpuPreviewChannel
 -> MetalCameraPreviewRenderer
 -> async Film/Creative 3D LUT preparation
 -> native generation guard
 -> atomic render-state/resource swap
 -> Metal fragment shader: Adjust -> Film -> Creative
```

Texture roles:

```text
texture0 = camera BGRA frame
texture1 = Film 3D LUT
texture2 = Creative 3D LUT
```

Resource preparation is off the per-frame path. Per-frame rendering executes the actual semantic stages.

---

## 10. PF2 Adjust formulas

PF2 realtime scope is deliberately bounded to:

```text
brightness
contrast
saturation
```

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

Grayscale and invert retain the existing rounded-u8 editor GPU semantics rather than substituting approximate floating-point variants.

---

## 11. Camera UI behavior

PF2 Camera surfaces:

```text
Film
  canonical Film selector
  strength

Filter
  Original
  grayscale / invert
  vintage / oceanic / lofi / dramatic / golden / pastel_pink
  intensity

Adjust
  brightness / contrast / saturation
```

State behavior:

- Film/Filter/Adjust are independent layers;
- switching tabs preserves accumulated state;
- rapid controls send complete look state through the coordinator;
- fallback Camera remains Film-only;
- a native runtime failure reduces the visible active state to Film-only so hidden Filter/Adjust cannot affect capture.

---

## 12. Temporary PF2 capture -> editor handoff

PF3 is not implemented yet.

PF2 capture currently does:

```text
CameraLookPreviewCoordinator.flush()
 -> snapshot final CameraLookState
 -> clean native JPEG capture
 -> CameraFilmEditorHandoff
 -> Rust-backed editor replay
```

Replay order is deterministic:

```text
brightness
contrast
saturation
Film
Creative
```

The handoff waits for the editor preview queue between operations so latest-value-wins coalescing cannot drop an intermediate adjustment.

Gallery-picked sources remain neutral and do not inherit the current Camera look.

---

## 13. Failure / fallback behavior

Expected native failure path:

```text
runtimeFailure
 -> detach CameraLookPreviewCoordinator
 -> destroy failed renderer
 -> Flutter camera fallback
 -> visible active look reduced to Film-only
 -> Filter/Adjust unavailable
```

This is intentionally fail-closed. Do not keep hidden unsupported look layers active after the UI can no longer preview them faithfully.

---

## 14. PF2 verification state

Verified implementation baseline:

```text
implementation head: b4451dce62bd877435cdab4ddd69c3f69cc037cd
CI: #420 / run 31946914217
result: SUCCESS
```

The exact implementation baseline passed:

- Flutter analyze/tests;
- Rust fmt/clippy/tests + G6 image characterization;
- GPU LUT parity;
- editing/film/GPU package analyze/tests;
- Golden tests;
- Android release artifact + Rust native packaging;
- iOS Rust plugin packaging smoke;
- iOS release no-codesign;
- wgpu core Windows/Linux/macOS.

Documentation-only descendants may move the branch head. Record the actual installed commit in device evidence.

Physical-device validation is the remaining PF2 close gate.

Canonical checklist:

```text
docs/PF2_DEVICE_VALIDATION_CHECKLIST.md
```

Required device areas include:

- neutral bypass;
- Film and strength;
- every Creative Filter class;
- brightness/contrast/saturation continuous drag;
- Film + Filter + Adjust coexistence;
- rapid switching and stale-state stress;
- sustained preview/frame pacing;
- thermal observation;
- lens switching;
- lifecycle pause/resume;
- shutter/capture -> editor handoff;
- Gallery source neutrality;
- runtime fallback where safely inducible;
- EN/TH control integrity;
- regression smoke.

PR #48 must remain Draft until this gate passes and device/performance evidence is recorded.

---

## 15. PF3 boundary

PF3 will replace the temporary editor handoff with:

```text
clean capture
+ selected CameraLookState
 -> Rust authoritative full-resolution processing
 -> JPEG
 -> MediaSaveService
 -> system Gallery
 -> remain in Camera
```

PF2 preview pixels never become saved-output authority.

---

## 16. Current continuation point

Current state:

```text
PF2 implementation: DONE
exact implementation CI: GREEN
physical-device validation: PENDING
PR #48: OPEN / DRAFT
```

Next action:

1. run `docs/PF2_DEVICE_VALIDATION_CHECKLIST.md` on physical hardware;
2. record exact device/build/commit and performance observations;
3. fix only real device findings if any;
4. refresh `PROJECT_HANDOFF.md`, this walkthrough, `PF2_CAMERA_LOOK_CONTRACT.md`, and `README.md` with final device evidence;
5. mark PR #48 Ready only after the physical-device gate passes;
6. after merge, verify resulting `main` CI before starting PF3.
