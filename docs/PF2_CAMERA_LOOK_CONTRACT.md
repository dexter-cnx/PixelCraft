# PF2 Unified Camera Look Contract

## Status

**PF2 IN PROGRESS.** This document freezes the camera-side state contract before native composition and final camera UI wiring.

## Goal

PF2 exposes Film, Creative Filter and a bounded set of faithful Adjust controls directly in the phone/tablet Camera without creating a second image-processing authority.

The camera state is intentionally transient:

```text
Flutter CameraLookState
  -> native GPU preview mirror
  -> clean camera capture remains untouched
  -> PF3 translates the same configuration to Rust operations
  -> Rust full-resolution JPEG render/save
```

## Authority

- Rust remains authoritative for edit semantics and final pixels.
- Metal/OpenGL ES are preview-only mirrors.
- Flutter owns interaction state only.
- Live camera framebuffers must never become capture/render authority.

## Composition model

PF2 treats the three camera surfaces as independent layers:

```text
Film
+ Creative Filter
+ Adjust
```

Changing one surface must not silently clear the other two. Native preview must preserve this composition order only after parity is proven. Unsupported native composition must fail closed rather than approximating Rust.

## Film

Film Profile ids and strengths keep the existing G1 contract:

- profile id is the canonical Film Profile id;
- strength is normalized `0.0 ... 1.0`;
- Original/disabled Film is represented by an empty id / zero strength in camera state.

## Creative Filter

Canonical operation ids remain the existing Rust/photon-rs ids:

- `grayscale`
- `invert`
- `vintage`
- `oceanic`
- `lofi`
- `dramatic`
- `golden`
- `pastel_pink`

The six preset filters already covered by G2.4 use Rust-generated canonical LUT assets:

- `creative_vintage`
- `creative_oceanic`
- `creative_lofi`
- `creative_dramatic`
- `creative_golden`
- `creative_pastel_pink`

The `creative_` prefix is GPU-asset plumbing only. It must never replace the canonical Rust operation id in a recipe.

`grayscale` and `invert` remain direct exact operations and must not be approximated with invented LUTs.

## Adjust — initial PF2 realtime set

PF2 initially enables only the low-cost adjustment semantics already covered by the editor GPU parity path:

- `brightness`
- `contrast`
- `saturation`

Their bounds and neutral values come from `dxtr_pixs_editing`; the camera does not maintain duplicate numeric semantics.

Other editor adjustments remain excluded from the Camera until their live-camera implementation and parity are proven. A visible Camera control must never be a fake placeholder.

## UI rules

- Film / Filter / Adjust stay in the Camera shell.
- Controls use compact horizontal selectors and precision sliders.
- Switching tools changes the control surface, not the underlying accumulated look state.
- Continuous slider movement may update preview state immediately.
- No confirmation dialog is required when selecting a Film or Creative Filter.
- The photograph remains visually dominant.

## PF2 implementation sequence

1. Freeze `CameraLookState` and canonical filter/adjust mappings. **DONE**
2. Extend native camera preview protocol to mirror the composed look state. **NEXT**
3. Add Metal parity-preserving composition. **NEXT**
4. Add OpenGL ES parity-preserving composition. **NEXT**
5. Replace PF1 Filter/Adjust placeholder behavior with real compact controls. **NEXT**
6. Add widget/contract tests and native regression coverage. **PARTIAL**
7. Device validation for rapid Film/Filter/Adjust switching and continuous sliders. **PENDING**

PF3 remains responsible for clean-capture -> Rust full-resolution render -> JPEG -> system Gallery and for keeping Camera active after shutter.
