# G0 — GPU Preview Foundation

Status: In progress
Branch: `feature/camera-film-preview`

G0 prepares Pixel Craft for real-time GPU preview without changing Rust's role as the authoritative final renderer.

## Delivered foundation

### Versioned Edit Graph

`lib/core/edit_graph.dart`

Schema version: `3`

The graph is the cross-renderer contract for future Camera GPU preview, Editor GPU preview, Masks, Selective Adjustments, Text/Stickers, Presets, Batch and Rust final rendering.

Current node categories:

- adjustment
- filmProfile
- crop
- rotate
- flip
- resize
- overlay

Nodes have stable IDs, enabled state, opacity, parameters and an optional mask reference. Masks and overlays have independent stable IDs. Decode validates schema version, duplicate IDs, opacity ranges and dangling mask references.

This schema is not wired into the existing Rust session recipe yet. That migration is a later G0 step and must preserve legacy session recovery.

### GPU preview backend contract

`lib/gpu/gpu_preview_renderer.dart`

The Dart side defines capabilities and state messages only. Pixel buffers must not cross Dart for live rendering.

Backend kinds:

- fallback
- androidOpenGl
- iosMetal

The fallback backend explicitly reports `supportsLut33 == false`; current Camera `ColorFilter.matrix` preview remains an approximation until G1 replaces it.

### Canonical GPU LUT atlas generator

`tool/generate_gpu_lut_atlas.py`

The generator consumes the exact 33³ `.cube` output produced by Rust `build.rs`. Film authoring therefore remains single-source:

```text
rust/film_profiles/*/look.json
      -> rust/build.rs
      -> canonical lut.cube
          -> Rust final renderer
          -> GPU atlas generator
```

Atlas v1:

- LUT: 33³
- format: RGBA8
- tile grid: 6 x 6
- tile: 33 x 33
- atlas: 198 x 198
- R changes across tile X
- G changes across tile Y
- B chooses adjacent slices
- interpolation contract: bilinear R/G + linear B
- mipmaps: disabled

Generated output defaults to `build/gpu_luts` and includes `manifest.json` with dimensions, interpolation contract and SHA-256 per profile.

### Preview parity fixtures

`tool/gpu_lut_parity_fixtures.json`

These fixed RGB vectors are shared test input for the Python reference sampler and future Android/iOS native backend tests.

The generator additionally checks 1024 deterministic pseudo-random colors per Film Profile. RGBA8 atlas parity tolerance against the floating-point canonical cube is currently `2 / 255` per channel.

## Commands

Generate inspectable canonical cubes and GPU atlases:

```bash
make gpu-luts
```

Verify cube -> atlas sampling parity without writing atlases:

```bash
make gpu-lut-verify
```

G0 parity is also included in `make test-full` and the Ubuntu CI validation job.

## Remaining G0 work

1. Add native renderer message/channel contract with explicit protocol version.
2. Package generated LUT atlas data for Android and iOS builds without committing hand-maintained binary copies.
3. Implement a tiny native reference shader harness before attaching it to Camera frames.
4. Add native parity tests using `gpu_lut_parity_fixtures.json`.
5. Add GPU capability negotiation and fallback rules for unsupported/unstable devices.
6. Define Edit Graph <-> current Rust recipe migration and backwards-compatible session versioning.
7. Define color-space contract (camera input, LUT domain, preview output, final export) before visual parity is considered complete.

## G0 exit criteria

G0 is complete when:

- Edit Graph schema has stable serialization tests.
- GPU backend protocol is versioned.
- all six Film Profile Pack v2 LUT atlases are generated from canonical Rust LUT output.
- atlas reference parity passes deterministically in CI.
- Android and iOS shader harnesses can sample the same parity fixtures within the agreed tolerance.
- current matrix preview remains a safe fallback and is no longer treated as the reference Film rendering path.
- no camera frame pixel buffers are routed through Dart or Flutter Rust Bridge.
