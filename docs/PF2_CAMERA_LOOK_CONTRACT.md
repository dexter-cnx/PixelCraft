# PF2 Unified Camera Look Contract

## Status

**PF2 IMPLEMENTATION COMPLETE / DEVICE VALIDATION PENDING — real Camera Film/Filter/Adjust controls and native ordered preview stages are implemented on PR #48. The exact implementation head passed CI; physical-device validation is now the remaining close gate.**

Active work:

```text
PR #48
feature/pf2-unified-camera-look
```

Verified implementation baseline:

```text
implementation head: b4451dce62bd877435cdab4ddd69c3f69cc037cd
CI: #420 / run 31946914217
result: SUCCESS
```

Documentation-only commits may move the branch head after this implementation baseline. Device evidence must record the exact commit actually installed on the device. A documentation-only descendant is acceptable when its executable tree is unchanged, but do not claim a different implementation head was validated without checking it.

Physical-device checklist:

```text
docs/PF2_DEVICE_VALIDATION_CHECKLIST.md
```

PF2 remains **OPEN / DRAFT** until the required device gate passes.

## Goal

PF2 exposes Film, Creative Filter and a bounded set of faithful Adjust controls directly in the phone/tablet Camera without creating a second image-processing authority.

```text
Flutter CameraLookState
  -> CameraLookPreviewCoordinator
  -> versioned setCameraLook control payload
  -> native resource preparation on look change
  -> ordered Metal/OpenGL ES shader stages
  -> clean camera capture remains untouched
```

Until PF3, camera capture still opens the editor. The temporary handoff replays the complete `CameraLookState` through Rust-backed editor operations so Film/Filter/Adjust are not lost.

## Authority

- Rust remains authoritative for edit semantics and final pixels.
- Metal/OpenGL ES are preview-only mirrors.
- Flutter owns interaction/transient look state only.
- Live camera framebuffers never become capture/render authority.
- Camera frame data never crosses MethodChannel.
- Native preview failure fails closed and must not mutate authoritative edit state.
- PF2 does not save the preview framebuffer.
- Native preview must not silently approximate Rust operation order.

## Canonical composition order

```text
clean camera sample
  -> Adjust
  -> Film
  -> Creative Filter
  -> display
```

The three UI surfaces are independent state layers. Changing one must not clear the other two.

## Why PF2 does not pre-compose the whole look into one 33³ LUT

A pre-composed 33³ LUT would add another sampling/interpolation/8-bit quantization boundary on top of the canonical Film/Creative LUT operations. That makes strict sequential parity with Rust unproven, especially for exact grayscale/invert semantics.

Therefore PF2 uses **direct ordered shader stages**. Film and LUT-backed Creative remain separate LUT resources, while brightness/contrast/saturation and grayscale/invert execute explicitly in the shader.

The temporary `CameraLookLutComposer` implementations were removed from both Android and iOS to prevent reintroducing this shortcut.

## Flutter camera state

`lib/camera/camera_look_state.dart`

`CameraLookState` contains:

- Film profile id + strength;
- Creative Filter id + strength;
- brightness;
- contrast;
- saturation.

Film/Creative strengths are clamped to `0.0 ... 1.0`. Adjustment ranges/defaults come from `dxtr_pixs_editing`.

## Preview coordinator

`lib/camera/camera_look_preview_coordinator.dart`

The coordinator provides:

- complete-state dispatch;
- latest-value-wins coalescing for rapid slider updates;
- generation invalidation on detach;
- stale-request protection;
- fail-closed error callback;
- `flush()` before native shutter capture.

Native renderers add their own generation guard around asynchronous LUT resource loading so an older Film/Creative load cannot overwrite a newer look.

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

Film uses canonical profile ids and Rust-generated 33³ LUT assets.

- strength: `0.0 ... 1.0`;
- disabled: empty id / zero strength;
- Film remains independent when Creative or Adjust changes.

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

The `creative_` prefix is GPU asset plumbing only and never replaces the canonical Rust operation id.

### Exact grayscale / invert semantics

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

Creative intensity blends in 8-bit space with rounding matching the existing editor GPU path.

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

Other adjustments remain excluded until their live-camera parity and performance are proven.

## Android OpenGL ES implementation

```text
setCameraLook
 -> GpuPreviewRendererSessionRegistry
 -> AndroidGpuCameraOesRenderer
 -> dedicated look thread loads required Film / Creative LUT atlas bytes
 -> native generation check
 -> GL thread uploads Film and Creative to independent texture slots
 -> OES fragment shader executes Adjust -> Film -> Creative every frame
```

Texture layout:

```text
texture0 = Camera external OES
texture1 = Film LUT atlas
texture2 = Creative LUT atlas
```

The shader executes brightness/contrast/saturation directly, then Film LUT blending, then exact grayscale/invert or the separate Creative LUT.

## iOS Metal implementation

```text
setCameraLook
 -> GpuPreviewChannel
 -> MetalCameraPreviewRenderer
 -> dedicated look queue loads required Film / Creative 3D LUT textures
 -> native generation check
 -> render queue swaps current resources/state atomically
 -> Metal fragment shader executes Adjust -> Film -> Creative every frame
```

Texture layout:

```text
texture0 = Camera BGRA frame
texture1 = Film 3D LUT
texture2 = Creative 3D LUT
```

The Metal shader uses the same adjustment formulas and rounded-u8 grayscale/invert semantics as the verified editor GPU path.

## Performance policy

Resource loading stays off the per-frame path and happens only when the selected Film/Creative resource changes. The shader now performs the semantic stages directly, so PF2 must validate frame pacing on physical devices rather than carrying forward the previous single-LUT performance assumption.

Required physical-device validation is defined in:

```text
docs/PF2_DEVICE_VALIDATION_CHECKLIST.md
```

The required gate includes at minimum:

- launch/basic camera behavior;
- neutral bypass;
- Film selection/strength;
- every exposed Creative Filter class;
- continuous brightness/contrast/saturation sliders;
- Film + Creative + Adjust simultaneously;
- rapid-switch/stale-state stress;
- sustained preview/frame pacing and thermal observation;
- front/back lens switching where supported;
- lifecycle pause/resume;
- shutter + temporary capture/editor handoff;
- Gallery source neutrality;
- runtime failure/fallback where safely inducible;
- EN/TH control integrity;
- regression smoke.

## Runtime failure / fallback behavior

If native look preview fails:

1. native emits the existing `runtimeFailure` signal;
2. Camera detaches the look coordinator and destroys that renderer;
3. Camera falls back to the Flutter camera path;
4. the visible/active look is reduced to Film-only because fallback preview supports only Film;
5. Filter/Adjust controls are no longer exposed.

This prevents hidden Filter/Adjust state from being applied at capture when the user cannot see it.

## Camera UI

`lib/ui/screens/camera_film_preview_screen_g1.dart`

PF2 real controls:

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
- controls submit complete state through `CameraLookPreviewCoordinator`;
- Filter/Adjust are available only on the native GPU path;
- fallback Camera does not expose fake Filter/Adjust controls;
- PF2 labels are localized in `en` and `th`.

## Temporary PF2 capture -> editor handoff

Before native capture, Camera calls `CameraLookPreviewCoordinator.flush()` and snapshots `CameraLookState`.

The clean JPEG capture is passed to `CameraFilmEditorHandoff`, which replays through the Rust-backed editor in deterministic order:

```text
brightness
contrast
saturation
Film
Creative
```

It waits for the editor preview queue to become idle between operations so latest-value-wins behavior cannot coalesce an intermediate adjustment away.

Gallery-picked sources still open with a neutral Camera look.

## PF2 implementation sequence

1. Freeze `CameraLookState` and canonical mappings. **DONE**
2. Add versioned `setCameraLook` bridge. **DONE**
3. Add latest-value-wins coordinator and stale-state guards. **DONE**
4. Add Android/iOS native parsing/contracts. **DONE**
5. Reject whole-look pre-composed-LUT shortcut and remove composers. **DONE**
6. Implement ordered Android GLES Adjust -> Film -> Creative stages. **DONE**
7. Implement ordered iOS Metal Adjust -> Film -> Creative stages. **DONE**
8. Wire native channel/session activation. **DONE**
9. Replace PF1 Filter/Adjust placeholders with real controls. **DONE**
10. Preserve full CameraLook through temporary capture -> editor handoff. **DONE**
11. Targeted state/coordinator/parity/regression coverage. **DONE — exact implementation head CI #420 GREEN**
12. Physical-device frame-pacing, interaction, lifecycle, and handoff validation. **CURRENT GATE / PENDING**
13. Record device/performance evidence. **PENDING**
14. Refresh final status in PROJECT_HANDOFF / CODE_WALKTHROUGH / README after device result. **PENDING FINAL RESULT**
15. Mark PR #48 ready only after physical-device gate passes. **PENDING**

## PF2 close criteria

PF2 is not closed merely because CI is green.

Required before Ready for Review:

```text
exact implementation CI green
+ physical-device checklist pass
+ sustained-preview/frame-pacing acceptable
+ device/performance evidence recorded
+ final documentation refresh
```

Only then should PR #48 leave Draft state.

## PF3 boundary

PF3 replaces the temporary editor handoff with:

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
