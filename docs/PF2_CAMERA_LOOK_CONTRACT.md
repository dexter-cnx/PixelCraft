# PF2 Unified Camera Look Contract

## Status

**PF2 IN PROGRESS — native composed-look foundation implemented, renderer activation/UI wiring still pending.**

Active work is on PR #48 / `feature/pf2-unified-camera-look`.

Verified gates before this refresh:

- CI #387: success
- CI #390: success
- CI #392: success
- CI #394: success

The latest composer commit at the time of this refresh is `3ac954558f8ed7a70f4f9caea10c440050789390`. CI #396 was started for that head and must not be treated as green until GitHub reports success.

## Goal

PF2 exposes Film, Creative Filter and a bounded set of faithful Adjust controls directly in the phone/tablet Camera without creating a second image-processing authority.

The camera state is intentionally transient:

```text
Flutter CameraLookState
  -> CameraLookPreviewCoordinator
  -> versioned setCameraLook control payload
  -> native GPU preview mirror
  -> clean camera capture remains untouched
  -> PF3 translates the same configuration to Rust operations
  -> Rust full-resolution JPEG render/save
```

## Authority

- Rust remains authoritative for edit semantics and final pixels.
- Metal/OpenGL ES are preview-only mirrors.
- Flutter owns interaction/transient look state only.
- Live camera framebuffers never become capture/render authority.
- Camera frame data never crosses MethodChannel.
- Native preview failure fails closed and must not mutate canonical camera state.

## Composition order

PF2 now freezes the preview composition order as:

```text
clean camera sample
  -> Adjust
  -> Film
  -> Creative Filter
  -> display
```

The three look surfaces remain independent state layers:

```text
Film
+ Creative Filter
+ Adjust
```

Changing one layer must not clear the other two.

To protect the camera 60fps hot path, PF2 does **not** plan to execute the full composition pipeline independently for every camera pixel from Flutter. Native code pre-composes the selected look into a 33³ LUT when look state changes, then the existing camera renderer keeps a single LUT sample in the per-frame shader path.

This preserves the existing verified LUT sampling architecture while allowing Film + Creative + Adjust to coexist.

## Flutter camera state

`lib/camera/camera_look_state.dart`

`CameraLookState` stores:

- Film profile id + strength;
- Creative Filter id + strength;
- brightness;
- contrast;
- saturation.

Film/Creative strengths are clamped to `0.0 ... 1.0`.

Adjustment bounds/defaults come from `dxtr_pixs_editing`; Camera does not duplicate canonical numeric ranges.

## Preview coordinator

The camera preview coordinator provides:

- latest-value-wins coalescing for rapid slider updates;
- generation invalidation on detach;
- stale-request protection;
- fail-closed native error handling;
- full composed-state dispatch rather than partial Film/Filter replacement messages.

This prevents rapid tool/slider changes from allowing an older native update to overwrite a newer state.

## Native protocol

`packages/dxtr_pixs_gpu/lib/camera_look_preview_bridge.dart`

MethodChannel:

```text
dev.pixelcraft/gpu_preview_v1
```

Method:

```text
setCameraLook
```

Control payload includes:

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

No pixel buffers are transported by this call.

Native contracts exist on both platforms:

```text
Android: NativeGpuCameraLook.kt
iOS:     NativeGpuCameraLook.swift
```

They clamp numeric values and reject unsupported Creative Filter ids deterministically.

## Film

Film Profile ids and strengths keep the existing G1/Rust contract:

- profile id is the canonical Film Profile id;
- strength is normalized `0.0 ... 1.0`;
- disabled Film is represented by empty id / zero strength in camera state.

Film LUTs remain canonical Rust-generated assets.

## Creative Filter

Canonical operation ids remain:

- `grayscale`
- `invert`
- `vintage`
- `oceanic`
- `lofi`
- `dramatic`
- `golden`
- `pastel_pink`

Canonical preset LUT assets:

- `creative_vintage`
- `creative_oceanic`
- `creative_lofi`
- `creative_dramatic`
- `creative_golden`
- `creative_pastel_pink`

The `creative_` prefix is GPU-asset plumbing only and must not replace the canonical Rust operation id in recipes/state.

### Exact operations

`grayscale` and `invert` retain the editor GPU exact arithmetic semantics.

Grayscale uses rounded 8-bit RGB values and integer average, not luminance:

```text
source8 = round(source * 255)
average = (r + g + b) / 3
effected8 = [average, average, average]
```

Invert uses:

```text
effected8 = 255 - source8
```

Creative intensity blends in 8-bit space with rounding consistent with the existing verified editor path.

## Adjust — initial PF2 realtime set

PF2 enables only:

- `brightness`
- `contrast`
- `saturation`

The exact existing editor GPU formulas are retained.

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

Other editor adjustments remain excluded until camera-preview parity and performance are proven. A visible Camera control must never be a fake placeholder.

## Native LUT composers

PF2 now contains platform composers for the same semantic order:

```text
Android camera-look composer
iOS camera-look composer
```

They build a composed 33³ look from:

```text
identity color
 -> Adjust
 -> optional Film LUT + Film strength
 -> optional Creative exact op or Creative LUT + strength
 -> composed LUT texel
```

The composer runs when look state changes, not once per camera frame.

## Current activation state

Android `setCameraLook` is routed into the native channel/session layer.

Until the renderer consumes the composed LUT, non-neutral camera-look requests intentionally fail closed rather than returning success while showing an unchanged or partially composed preview.

Neutral state may safely disable the active look.

The same principle applies to iOS activation: do not report a successful non-neutral composed preview until the Metal camera renderer actually uses the composed LUT.

## UI rules

- Film / Filter / Adjust stay in the Camera shell.
- Switching tabs changes controls, not accumulated look state.
- Film and Filter selection is direct; no confirmation dialog.
- Sliders may update continuously through the coalescing coordinator.
- The photograph remains visually dominant.
- Filter/Adjust controls must not be enabled until the native/runtime path is real on the active capability path.
- Unsupported GPU paths fail closed rather than approximate Rust semantics.

## PF2 implementation sequence

1. Freeze `CameraLookState` and canonical filter/adjust mappings. **DONE**
2. Add versioned `setCameraLook` Flutter bridge. **DONE**
3. Add latest-value-wins preview coordinator and stale-state guards. **DONE**
4. Add Android/iOS native camera-look parsing/contracts. **DONE**
5. Add parity-preserving 33³ composed-look builders for Android/iOS. **DONE — compile/CI gate in progress at latest refresh**
6. Connect composed LUT output to Android OpenGL ES camera renderer. **NEXT**
7. Connect composed LUT output to iOS Metal camera renderer. **NEXT**
8. Remove temporary non-neutral fail-closed activation gate after real renderer support exists. **NEXT**
9. Replace PF1 Filter/Adjust placeholders with real compact controls. **PENDING**
10. Add rapid-switch / continuous-slider / neutral-state regression coverage. **PARTIAL**
11. Validate on physical device, including iPhone 11 reference device. **PENDING**
12. Sync `PROJECT_HANDOFF.md`, `CODE_WALKTHROUGH.md`, README as the slice closes. **IN PROGRESS**

## PF3 boundary

PF2 does not change final capture authority.

PF3 remains responsible for:

```text
clean capture
+ selected CameraLookState
 -> Rust authoritative full-resolution processing
 -> JPEG
 -> MediaSaveService
 -> system Gallery
 -> remain in Camera
```

Until PF3 lands, the existing temporary capture -> editor flow remains acceptable only if the selected look is preserved accurately in the authoritative handoff. Preview pixels themselves must never be used as the saved result.
