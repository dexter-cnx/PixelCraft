# PF2 Unified Camera Look Contract

## Status

**PF2 IN PROGRESS — native composed-look preview and real Camera Film/Filter/Adjust controls are implemented on PR #48. Exact-head CI and physical-device validation remain open.**

Active work:

```text
PR #48
feature/pf2-unified-camera-look
```

Verified baseline before the current activation slice:

- CI #387: success
- CI #390: success
- CI #392: success
- CI #394: success
- CI #400 / run `31944473130`: success; includes the Swift/Xcode 26 composer compatibility fix

Do not infer the current activation head is green from these older runs. Verify the exact current PR head before closing PF2.

## Goal

PF2 exposes Film, Creative Filter and a bounded set of faithful Adjust controls directly in the phone/tablet Camera without creating a second image-processing authority.

```text
Flutter CameraLookState
  -> CameraLookPreviewCoordinator
  -> versioned setCameraLook control payload
  -> native control-rate 33^3 LUT composition
  -> existing single-LUT Metal/OpenGL ES per-frame hot path
  -> clean camera capture remains untouched
```

Until PF3, camera capture still opens the editor. The temporary handoff now replays the complete `CameraLookState` through Rust-backed editor operations so Film/Filter/Adjust are not lost.

## Authority

- Rust remains authoritative for edit semantics and final pixels.
- Metal/OpenGL ES are preview-only mirrors.
- Flutter owns interaction/transient look state only.
- Live camera framebuffers never become capture/render authority.
- Camera frame data never crosses MethodChannel.
- Native preview failure fails closed and must not mutate authoritative edit state.
- PF2 does not save the preview framebuffer.

## Composition order

PF2 freezes the look order as:

```text
clean camera sample
  -> Adjust
  -> Film
  -> Creative Filter
  -> display
```

The three surfaces remain independent state layers:

```text
Film
+ Creative Filter
+ Adjust
```

Changing or opening one tool must not clear the other two.

## Flutter camera state

`lib/camera/camera_look_state.dart`

`CameraLookState` contains:

- Film profile id + strength;
- Creative Filter id + strength;
- brightness;
- contrast;
- saturation.

Film/Creative strengths are clamped to `0.0 ... 1.0`. Adjustment ranges/defaults come from `dxtr_pixs_editing`; Camera does not maintain duplicate numeric semantics.

## Preview coordinator

`lib/camera/camera_look_preview_coordinator.dart`

The coordinator provides:

- complete-state dispatch instead of partial Film/Filter messages;
- latest-value-wins coalescing for rapid slider updates;
- generation invalidation on detach;
- stale-request protection;
- fail-closed error callback;
- `flush()` before native shutter capture so the most recently submitted control state is no longer waiting in Dart.

Native renderers add a second generation guard around composed-LUT work. An older composition result must not overwrite a newer look.

## Native protocol

Flutter bridge:

```text
packages/dxtr_pixs_gpu/lib/camera_look_preview_bridge.dart
```

MethodChannel:

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

No frame or pixel buffers are transported by this method.

Native contracts:

```text
Android: NativeGpuCameraLook.kt
iOS:     NativeGpuCameraLook.swift
```

They clamp numeric values and reject unsupported Creative Filter ids deterministically.

## Film

Film uses existing canonical profile ids and canonical Rust-generated 33³ LUT assets.

- strength: `0.0 ... 1.0`;
- disabled: empty id / zero strength;
- Film remains an independent layer when Creative or Adjust changes.

## Creative Filter

Canonical ids:

- `grayscale`
- `invert`
- `vintage`
- `oceanic`
- `lofi`
- `dramatic`
- `golden`
- `pastel_pink`

Canonical LUT-backed asset ids:

- `creative_vintage`
- `creative_oceanic`
- `creative_lofi`
- `creative_dramatic`
- `creative_golden`
- `creative_pastel_pink`

The `creative_` prefix is GPU asset plumbing only. It never replaces the canonical Rust operation id.

### Exact grayscale / invert semantics

`grayscale` and `invert` mirror the existing rounded-u8 editor semantics.

```text
source8 = round(clamp(source) * 255)
```

Grayscale:

```text
average = (r + g + b) / 3
effected8 = [average, average, average]
```

Invert:

```text
effected8 = [255-r, 255-g, 255-b]
```

Creative intensity blends in 8-bit space with rounding consistent with the existing editor path.

## Adjust — PF2 realtime scope

PF2 exposes only:

- `brightness`
- `contrast`
- `saturation`

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

Other adjustments remain excluded until their live-camera parity and performance are proven. A visible Camera control must never be a fake placeholder.

## Native LUT composition and renderer activation

Composers:

```text
Android: CameraLookLutComposer.kt
iOS:     CameraLookLutComposer.swift
```

They evaluate the complete semantic order only when CameraLook changes:

```text
identity 33^3 color
 -> Adjust
 -> optional Film LUT + strength
 -> optional exact Creative op or Creative LUT + strength
 -> composed 33^3 LUT
```

Renderer activation is now wired:

```text
Android
setCameraLook
 -> GpuPreviewRendererSessionRegistry
 -> AndroidGpuCameraOesRenderer
 -> CameraLookLutComposer on dedicated look thread
 -> generation check
 -> upload composed atlas into existing GLES LUT texture
 -> existing OES shader samples one LUT per frame at strength 1.0

iOS
setCameraLook
 -> GpuPreviewChannel
 -> MetalCameraPreviewRenderer
 -> CameraLookLutComposer on dedicated look queue
 -> generation check
 -> swap current 3D LUT texture
 -> existing Metal fragment path samples one LUT per frame at strength 1.0
```

This intentionally keeps composition out of Dart and out of the per-frame camera hot path.

Legacy `setFilm` remains available for compatibility, but PF2 Camera UI sends complete `CameraLookState` through `setCameraLook`.

## Runtime failure / fallback behavior

If native composed-look preview fails:

1. native emits the existing `runtimeFailure` signal;
2. Camera detaches the look coordinator and destroys that renderer;
3. Camera falls back to the Flutter camera path;
4. the visible/active look is reduced to Film-only, because fallback preview supports only Film;
5. Filter/Adjust controls are no longer exposed on that path.

This prevents a hidden Filter/Adjust state from being applied at capture when the user cannot see it in fallback preview.

## Camera UI

`lib/ui/screens/camera_film_preview_screen_g1.dart`

PF2 now has real camera controls:

```text
Film
  canonical Film selector
  strength slider

Filter
  Original
  grayscale / invert
  vintage / oceanic / lofi / dramatic / golden / pastel_pink
  intensity slider

Adjust
  brightness / contrast / saturation
  canonical-range slider
```

Rules:

- switching tabs preserves accumulated state;
- controls submit the complete look through `CameraLookPreviewCoordinator`;
- Filter/Adjust are available only on the active native GPU camera path;
- fallback Camera does not expose fake Filter/Adjust controls;
- new PF2 labels are localized in `en` and `th`.

## Temporary PF2 capture -> editor handoff

PF2 does not yet implement PF3 save-to-Gallery behavior.

Before native capture, Camera calls `CameraLookPreviewCoordinator.flush()` and snapshots the current `CameraLookState`.

The clean JPEG capture is then passed to `CameraFilmEditorHandoff` with the full look.

The handoff replays through the normal Rust-backed editor path in deterministic order:

```text
brightness
contrast
saturation
Film
Creative
```

It waits for the editor preview queue to become idle between operations so the editor's latest-value-wins queue cannot coalesce an intermediate adjustment away.

Gallery-picked sources still open with a neutral Camera look; they never inherit Camera Film/Filter/Adjust state.

## PF2 implementation sequence

1. Freeze `CameraLookState` and canonical mappings. **DONE**
2. Add versioned `setCameraLook` Flutter bridge. **DONE**
3. Add latest-value-wins coordinator and stale-state guards. **DONE**
4. Add Android/iOS native parsing/contracts. **DONE**
5. Add Android/iOS 33³ composed-look builders. **DONE**
6. Connect composed LUT to Android OpenGL ES renderer. **DONE — exact-head CI pending**
7. Connect composed LUT to iOS Metal renderer/channel. **DONE — exact-head CI pending**
8. Remove Android temporary non-neutral activation gate. **DONE**
9. Replace PF1 Filter/Adjust placeholders with real controls. **DONE — exact-head CI pending**
10. Preserve full CameraLook through temporary capture -> editor handoff. **DONE — exact-head CI pending**
11. Add/extend rapid-switch, continuous-slider, neutral and handoff regression coverage. **NEXT**
12. Physical-device validation, including iPhone 11 reference device. **PENDING**
13. Sync handoff/walkthrough/README and close PF2 only after exact-head CI and required device evidence. **IN PROGRESS**

## PF3 boundary

PF3 remains responsible for replacing the temporary editor handoff with:

```text
clean capture
+ selected CameraLookState
 -> Rust authoritative full-resolution processing
 -> JPEG
 -> MediaSaveService
 -> system Gallery
 -> remain in Camera
```

PF2 preview pixels are never used as saved output.
