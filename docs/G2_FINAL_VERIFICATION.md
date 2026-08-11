# G2 Final Verification / Closure Record

## Status

**G2 CLOSED / MERGE-READY.**

Final consolidated host gate: **PASS on 2026-08-11.**

Final physical-device smoke: **PASS on 2026-08-11.**

G2 keeps the project architecture invariant established in G1:

```text
interactive preview   = GPU/compositor fast path
committed edit         = Rust authoritative edit graph
Undo / Redo            = Rust authoritative history
full-resolution export = Rust authoritative renderer
```

Live image buffers are not routed through Dart MethodChannel as an image-processing data path. Dart remains the control plane.

## Scope delivered

### G2.0 — Editor GPU lab

- Static editor source rendered through iOS Metal.
- Brightness / contrast / saturation controls established the editor Metal path.
- Canonical Film LUT loading reused the G1 33^3 LUT contract.

### G2.1 — Production Editor integration

- Metal draft integrated into the real Editor.
- Slider drag is GPU-only for supported controls.
- Slider release hands the semantic edit back to Rust.
- Apply / Cancel / Undo / Redo / export remain Rust-controlled.
- Stale GPU activation is guarded so older async work cannot become visible after a newer interaction.

Recorded iOS reference-device adjustment/LUT verification:

- adjustment numeric parity: PASS, overall max delta `0.00192630` (within `1/255` gate used by the harness);
- 1024^2 adjustment + Film workload latency: PASS;
- average `1.228 ms`;
- p50 `1.121 ms`;
- p95 `1.930 ms`;
- p99/max `2.560 ms`;
- target p95 `<= 16.67 ms`.

### G2.2 — Sharpen

Rust remains the semantic source of truth for the 3x3 sharpen kernel.

Physical-device deterministic parity was recorded for strengths `0.5`, `1.0`, and `1.5` with maximum deltas below the configured tolerance. G2.2 is closed.

### G2.3 — Gaussian Blur

Rust semantics:

- sigma derived from editor value;
- separable horizontal + vertical blur;
- radius `(2 * sigma).ceil()`;
- imageproc 0.23-compatible weight semantics;
- clamp edge behavior;
- RGBA8 intermediate quantization behavior mirrored by the Metal path.

Recorded deterministic parity:

- values `0.25`, `0.5`, `1.0`, `1.5`, `2.0`;
- overall max delta `0.00000000` on the deterministic fixture;
- PASS.

Recorded 1024^2 realtime blur benchmark on the iOS reference device at editor value `2` / sigma `5`:

- average `7.778 ms`;
- p50 `7.856 ms`;
- p95 `9.007 ms`;
- p99/max `9.776 ms`;
- target p95 `<= 16.67 ms`;
- PASS.

### G2.4 — Creative Filters

`grayscale` and `invert` use the verified Metal compute path. Recorded parity for intensities `0.25`, `0.50`, `1.00` was exact on the deterministic fixture (`overall max delta 0`).

`vintage`, `oceanic`, `lofi`, `dramatic`, `golden`, and `pastel_pink` use Rust-generated canonical 33^3 LUTs. Closure is compositional through the already-verified LUT asset and Metal sampler path; no unmeasured direct Photon-vs-interpolated-LUT delta is claimed.

See `docs/G2_4_CREATIVE_LUT_CONTRACT.md`.

### G2.5 — Transform Preview

- realtime straighten uses Flutter compositor presentation while dragging;
- Rust `RotateDegrees` is authoritative on release;
- interactive crop uses an on-canvas normalized crop rectangle;
- crop drag/resize does not invoke Rust per pointer tick;
- Apply Crop creates the authoritative Rust Crop operation;
- aspect presets are evaluated in source-pixel space;
- duplicate crop controls were removed;
- crop geometry regression tests were added;
- rotate-90 and flips intentionally remain Rust operations because they are discrete and inexpensive.

Physical-device straighten and interactive crop behavior were functionally validated, including corrected non-square-source aspect handling.

See `docs/G2_5_TRANSFORM_PREVIEW_CONTRACT.md`.

### G2.6 — GPU/session hardening

The live GPU draft path now protects against:

- rapid tool switching;
- stale slider updates;
- stale renderer creation;
- checkpoint changes;
- Original-view transitions;
- busy/error transitions;
- native MethodChannel / Metal update failure.

The implementation uses separate GPU activation and renderer generations. Native realtime errors fail closed to the Rust preview and the next eligible interaction may recreate a fresh renderer.

The physical-device stress gate was performed for rapid switching / repeated slider gestures and passed without stale Metal overlays or reported unhandled async errors.

See `docs/G2_6_EDITOR_GPU_HARDENING.md`.

## Draft composition behavior

Before editor-level Apply, the active draft may contain independent core adjustment slots plus Creative and Film slots.

Expected behavior includes:

```text
Brightness 1.20
Contrast   1.30
Saturation 0.80
```

Switching between those controls restores remembered draft values instead of resetting the slider to neutral. Revisiting an existing adjustment replaces that adjustment slot rather than stacking a duplicate operation.

Creative presets share one mutually exclusive Creative slot. Film profiles share one mutually exclusive Film slot. Tool switching is neither Apply nor Cancel.

The slider-memory behavior was validated on device after the draft-composition changes.

See `docs/EDITOR_DRAFT_COMPOSITION.md`.

## Camera -> Editor invariant

Camera Film preview is presentation-only. Capture remains clean and the captured source enters the Editor without the camera preview Film being baked into the pixels.

Editor GPU effects remain draft presentation until Rust commits the corresponding semantic operation.

## Host merge gate — PASS

Command run on 2026-08-11 from the G2 branch:

```bash
bash tool/verify_g2.sh
```

Result:

```text
[Pixel Craft] G2 HOST GATE: PASS
```

Verified stages:

1. `flutter analyze` — PASS, no issues found
2. Dart unit/state tests — PASS (`42` tests reported in `test/state`)
3. Dart UI/widget tests excluding goldens — PASS (`20` tests reported)
4. golden tests — PASS (`8` tests reported)
5. `cargo fmt --check` — PASS
6. strict Rust clippy — PASS
7. Rust unit tests — PASS (`18` tests, `0` failures)
8. canonical Film + Creative LUT verification — PASS

Recorded LUT verification from this final host run:

```text
Film atlas max error:
  provia_inspired   0.001778
  velvia_inspired   0.001892
  astia_inspired    0.001906
  e100_inspired     0.001796
  ektar_inspired    0.001732
  chrome64_inspired 0.001921

Creative LUT atlas max error:
  vintage      0.000000
  oceanic      0.000000
  lofi         0.000000
  dramatic     0.000000
  golden       0.000000
  pastel_pink  0.000000
```

The Cargo warning that package-level profiles are ignored because the workspace root owns profiles was non-fatal and did not prevent clippy/tests/checks from passing.

## Final manual smoke gate — PASS

The final physical-device smoke was reported PASS on 2026-08-11 using the merge-candidate flow:

```text
Camera Film preview
  -> capture clean photo
  -> Adjust multiple controls without Apply
  -> revisit controls and confirm values are retained
  -> Creative filter + intensity
  -> Film profile + strength
  -> Sharpen
  -> Gaussian Blur
  -> Crop (including non-square aspect checks)
  -> Straighten
  -> Rotate / Flip
  -> Undo / Redo
  -> Cancel draft
  -> create draft again
  -> Apply
  -> full-resolution export
```

Acceptance criteria covered by the smoke:

- no stale GPU overlay observed;
- no crash or reported unhandled native/Future error;
- slider memories match the active draft;
- Apply/Cancel behave as checkpoint operations;
- Undo/Redo preserve Rust-authoritative history behavior;
- full-resolution export completes through the Rust path;
- Camera Film remains preview-only and capture source stays clean.

## Closure decision

Final closure matrix:

```text
recorded device parity/latency gates  PASS
G2.5 transform device validation      PASS
G2.6 stress validation                PASS
draft-control memory validation       PASS
bash tool/verify_g2.sh                 PASS on 2026-08-11
final manual smoke                     PASS on 2026-08-11
```

**Decision: G2 CLOSED / MERGE-READY.**

No new G3 scope should be added to `feature/camera-film-preview`. Merge the verified branch, then move production GPU composition/lifecycle work to G3 on a new branch.