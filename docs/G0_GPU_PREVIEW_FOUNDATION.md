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

### Native GPU protocol v1

`lib/gpu/native_gpu_preview_bridge.dart`

Channel: `dev.pixelcraft/gpu_preview_v1`

Protocol version: `1`

The protocol is control-plane only. It transports capability negotiation and tiny state messages; camera/image pixel buffers are explicitly excluded.

Current methods:

- `probe`
- `runReferenceHarness`
- `runFilmProfileHarness`

Android registers the protocol from `MainActivity` through `GpuPreviewChannel`.

### Android OpenGL ES reference shader harness

`android/app/src/main/kotlin/dev/pixelcraft/pixelcraft/GpuLutShaderHarness.kt`

G0.2 has a real device-side shader harness. It creates a 1x1 offscreen EGL pbuffer, compiles the LUT shader, uploads an RGBA8 33³ atlas and renders deterministic RGB fixtures through OpenGL ES. The result is read back with `glReadPixels` and compared with a `2 / 255` per-channel tolerance.

The harness now has two levels:

1. Identity LUT sanity check for EGL/shader/interpolation mechanics.
2. Canonical Film Profile parity for all six Film Profile Pack v2 atlases.

This validates:

- EGL context creation
- GLSL compilation/linking
- RGBA8 198x198 atlas upload
- 6x6 / 33-slice atlas addressing
- manual bilinear R/G interpolation
- linear interpolation between adjacent B slices
- packaged Android asset loading
- canonical Film LUT parity on a real Android GPU

It is intentionally not connected to Camera frames yet.

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

### Generated Android Film LUT assets

`android/app/build.gradle.kts` registers `generateGpuLutAssets` as a `preBuild` dependency. The task invokes the canonical `make gpu-luts` pipeline and adds the generated directory as an Android assets source set.

No hand-maintained Film LUT binary copy is committed to Android resources. A normal Android build generates:

```text
android/app/build/generated/gpu_lut_assets/gpu_luts/
  manifest.json
  native_parity.json
  provia_inspired.rgba8
  velvia_inspired.rgba8
  astia_inspired.rgba8
  e100_inspired.rgba8
  ektar_inspired.rgba8
  chrome64_inspired.rgba8
```

`tool/generate_gpu_native_parity_fixture.py` derives the native expected values from the same canonical `.cube` LUTs. Native Android tests therefore compare GPU output against Rust-authoritative LUT semantics rather than against hand-authored constants.

### Preview parity fixtures

`tool/gpu_lut_parity_fixtures.json`

These fixed RGB vectors are shared test input for the Python reference sampler and Android native backend tests.

The atlas generator additionally checks 1024 deterministic pseudo-random colors per Film Profile. RGBA8 atlas parity tolerance against the floating-point canonical cube is currently `2 / 255` per channel.

## Commands

Generate inspectable canonical cubes, GPU atlases and native expectations:

```bash
make gpu-luts
```

Verify cube -> atlas sampling parity without writing atlases:

```bash
make gpu-lut-verify
```

Run identity plus all six canonical Film LUTs through the Android OpenGL shader on a physical device:

```bash
make gpu-native-test DEVICE=<device-id>
```

G0 host parity is included in `make test-full` and the Ubuntu CI validation job. The native shader harness remains a device test because GitHub host CI does not provide the same Android GPU path as a physical device.

## Remaining G0 work

1. Add GPU capability/fallback policy for unsupported, unstable or blacklisted devices.
2. Implement the iOS Metal/Core Image protocol peer and reference harness.
3. Define Edit Graph <-> current Rust recipe migration and backwards-compatible session versioning.
4. Define color-space contract (camera input, LUT domain, preview output, final export) before visual parity is considered complete.
5. Move native harness execution off the platform UI thread before it is used by production capability probing.
6. Expose a production native texture/surface renderer lifecycle contract for G1 Camera integration.

## G0 exit criteria

G0 is complete when:

- Edit Graph schema has stable serialization tests.
- GPU backend protocol is versioned.
- all six Film Profile Pack v2 LUT atlases are generated from canonical Rust LUT output.
- atlas reference parity passes deterministically in CI.
- Android and iOS shader harnesses can sample the same parity fixtures within the agreed tolerance.
- current matrix preview remains a safe fallback and is no longer treated as the reference Film rendering path.
- no camera frame pixel buffers are routed through Dart or Flutter Rust Bridge.
