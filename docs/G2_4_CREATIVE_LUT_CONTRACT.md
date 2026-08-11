# G2.4 Creative Filter GPU Preview Contract

## Status

**G2.4 CLOSED on the iOS G2 reference device.**

- G2.4a (`grayscale`, `invert`) has native Metal realtime preview and exact numeric parity against the Rust/photon-rs semantics.
- G2.4b (`vintage`, `oceanic`, `lofi`, `dramatic`, `golden`, `pastel_pink`) uses Rust-generated canonical 33³ LUTs and the already-verified Metal 3D LUT loader/sampler.
- G2.4c verification is closed by proof composition instead of duplicating the already-verified 33³ Metal sampler in another diagnostics implementation.

## Scope

Creative preset filters:

- `vintage`
- `oceanic`
- `lofi`
- `dramatic`
- `golden`
- `pastel_pink`

## Source of truth

Rust remains authoritative. `rust/src/bin/generate_creative_luts.rs` calls the same `photon_filters::apply` path used by committed edits/export at intensity `1.0`.

Metal contains no independently maintained preset coefficients or HSL conversion code for these filters.

## Canonical LUT

- Grid: 33 × 33 × 33
- Input domain: RGB `[0, 1]`
- Canonical cube source: `rust/creative_luts/<filter>/lut.cube`
- Runtime atlas: RGBA8
- Alpha: 255
- Sampling: same texel-center 3D LUT rule verified by the G1 Film parity harness
- Runtime intensity: blend original color with LUT result using the normalized `0.0 ... 1.0` intensity contract used by the Editor

Conceptually:

```text
source RGB
  -> canonical creative 33³ LUT (Rust-generated)
  -> effected RGB
  -> mix(source, effected, intensity)
  -> preview output
```

## Asset layout

G1 Film asset names remain unchanged. Creative assets share the existing bundle directory but use an explicit prefix so the same native loader can be reused without confusing application-level Film Profile ids with creative ids:

```text
gpu_luts/
  provia_inspired.rgba8
  velvia_inspired.rgba8
  ...
  creative_vintage.rgba8
  creative_oceanic.rgba8
  creative_lofi.rgba8
  creative_dramatic.rgba8
  creative_golden.rgba8
  creative_pastel_pink.rgba8
  manifest.json
  creative_manifest.json
```

The prefix is an internal GPU asset id only. Editor/Rust operation ids remain `vintage`, `oceanic`, etc.

## Build pipeline

`make gpu-luts` performs:

```text
film-luts
creative-luts
  -> cargo run --bin generate_creative_luts
  -> rust/creative_luts/<filter>/lut.cube

generate_gpu_lut_atlas.py
  -> Film RGBA8 assets

generate_gpu_creative_lut_atlas.py
  -> creative_<filter>.rgba8
  -> creative_manifest.json
```

The existing iOS `Generate Film LUT Assets` build phase calls `make gpu-luts`, so Creative LUT assets are generated into the same `gpu_luts` application-resource directory without adding a second Xcode asset phase.

## Runtime rules

1. Dart sends only creative filter id + intensity.
2. Image pixels remain native.
3. `grayscale` and `invert` use the exact u8 Metal compute implementation verified in G2.4a.
4. Photon preset live drafts map `filter` -> internal LUT id `creative_<filter>` and reuse `MetalFilmLutLoader` + the existing 3D LUT render path.
5. Intensity-only slider updates with the same selected preset update only LUT strength state; the LUT texture is not reloaded.
6. Selecting another tool clears the active creative GPU draft.
7. Unsupported/missing creative LUT asset -> live GPU activation fails and the Editor remains on Rust preview fallback.
8. Apply/Cancel/Undo/Redo/export remain Rust-authoritative.

## G2.4 verification evidence

G2.4c deliberately does **not** add another native 33³ LUT diagnostics shader. The runtime creative preset path is the same loader, texel-center sampling rule, and strength blend already exercised by Film. Re-copying that shader into a new harness would test duplicate code instead of adding meaningful coverage.

The proof chain is:

```text
Rust photon-rs preset implementation
        ↓
rust/src/bin/generate_creative_luts.rs
        ↓
canonical 33³ creative cube
        ↓
make gpu-lut-verify
        ↓
deterministic cube -> RGBA8 atlas parity
        ↓
MetalFilmLutLoader
        ↓
G1V.1 verified 33³ Metal texel-center sampler
        ↓
G2.1f verified LUT/strength GPU workload latency
        ↓
physical-device G2.4b live-intensity validation
```

Recorded gates:

- Rust-generated reference LUT exists for all six Photon presets: **PASS**.
- Cube -> RGBA8 atlas deterministic parity (`make gpu-lut-verify`): **PASS**.
- Metal 33³ texel-center sampling rule (G1V.1): **PASS**.
- Creative intensity runtime uses the already-verified LUT strength blend path: **PASS by shared implementation**.
- 1024² LUT editor command-completion target, p95 <= 16.67 ms (G2.1f): **PASS**.
- Physical-device realtime intensity for all six Photon presets: **PASS**.
- Missing/unsupported asset behavior remains Rust fallback: **PRESERVED**.
- Committed edits and full-resolution export remain Rust-authoritative: **PRESERVED**.

## Why LUT generation is preferred

Some Photon presets are simple per-channel operations while others chain contrast, grayscale, channel offsets, color mixing, or HSL operations. Encoding those internals independently in Metal creates a second source of truth and increases drift risk when the Rust dependency changes. Rust-generated LUTs preserve a single authoritative implementation while reusing the already-verified G1 Metal LUT sampler.
