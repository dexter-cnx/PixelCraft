# Pixel Craft — GPU Preview Chat Handoff

Last updated: 2026-08-08
Branch: `feature/camera-film-preview`

## Current confirmed status

The Camera Film Preview feature is implemented as an initial embedded camera flow with the existing matrix approximation still acting as the live fallback preview. Capture keeps the original image clean and hands the selected Film Profile to the normal Editor, where Rust applies the authoritative 33^3 LUT.

A crash caused by disposing `CameraController` while `CameraPreview` was still mounted was fixed by detaching the preview first, waiting for Flutter to rebuild, then disposing the native controller before navigation.

G0 GPU Preview Foundation has been started and the Android device-side parity pipeline is now confirmed working on a physical device.

Confirmed successful command:

```bash
make gpu-native-test DEVICE=RF8Y909V0LV
```

Latest observed result:

```text
+2: All tests passed!
```

The successful run confirmed:

- Rust Film Profile Pack v2 materialized all six 33^3 LUTs.
- GPU atlas generation completed for all six profiles.
- Atlas/reference parity max error was about 0.0017–0.0019 per channel, below the agreed `2/255` tolerance.
- `native_parity.json` was generated.
- Generated LUT assets were packaged into the Android app build.
- Android OpenGL ES shader harness executed on the physical device.
- Native Film LUT parity integration tests passed.

## Architecture decisions already made

Pixel Craft should converge on one non-destructive, versioned Edit Graph with two renderer roles:

```text
Input / Camera
      |
      v
  Edit Graph
      |
      +----------------------+----------------------+
      |                                             |
      v                                             v
GPU Preview Renderer                         Rust Final Renderer
interactive / low latency                    authoritative / full-res
Camera + Editor                              Export + Batch + Resume
```

Rust remains the source of truth for effect semantics and final rendering.

GPU preview must not send live camera/image pixel buffers through Dart or Flutter Rust Bridge. Dart only sends small state/control messages.

## G0 foundation already added

### Versioned Edit Graph

File:

```text
lib/core/edit_graph.dart
```

Schema version: `3`

Designed to become the shared contract for:

- GPU preview
- Film Profiles
- Selective adjustments
- Masks
- Text/Stickers
- Preset import/export
- Batch processing
- Rust final rendering

### GPU renderer abstraction

File:

```text
lib/gpu/gpu_preview_renderer.dart
```

Backend kinds currently include:

- fallback
- androidOpenGl
- iosMetal

The current matrix camera preview is explicitly a fallback approximation, not the reference Film renderer.

### Native GPU control protocol

File:

```text
lib/gpu/native_gpu_preview_bridge.dart
```

Channel:

```text
dev.pixelcraft/gpu_preview_v1
```

Protocol version: `1`

Android implementation:

```text
android/app/src/main/kotlin/dev/pixelcraft/pixelcraft/GpuPreviewChannel.kt
android/app/src/main/kotlin/dev/pixelcraft/pixelcraft/GpuLutShaderHarness.kt
```

### Canonical GPU LUT generation

Files:

```text
tool/generate_gpu_lut_atlas.py
tool/generate_gpu_native_parity_fixture.py
tool/gpu_lut_parity_fixtures.json
```

Canonical path:

```text
rust/film_profiles/*/look.json
        -> rust/build.rs
        -> canonical 33^3 lut.cube
             -> Rust final renderer
             -> GPU atlas generator
```

Atlas v1:

- 33^3 LUT
- 6 x 6 tile grid
- 33 x 33 per tile
- 198 x 198 RGBA8 atlas
- bilinear R/G interpolation
- linear interpolation between adjacent B slices
- no mipmaps

### Android generated asset integration

`android/app/build.gradle.kts` now uses a typed generated-assets Gradle task and Android Variant API. The custom task uses injected `ExecOperations`, compatible with the current Gradle/AGP setup.

Do not revert to:

```text
sourceSets.main.assets.srcDir(Provider<Directory>)
```

and do not use:

```text
android.sourceset.disallowProvider=false
```

as a workaround.

## What to do next — G0.3

Start here in the next chat.

### 1. GPU capability and fallback policy

Implement a production capability model on top of the current protocol.

Need to distinguish at least:

- GPU backend available
- LUT33 supported
- shader self-test passed
- native assets loaded
- renderer initialization failed
- runtime render failure
- explicitly blacklisted device/GPU

Recommended decision flow:

```text
probe native backend
   |
   +-- protocol mismatch ----------> fallback
   +-- unavailable ----------------> fallback
   +-- LUT33 unsupported ----------> fallback
   +-- self-test failed -----------> fallback
   +-- blacklisted ----------------> fallback
   |
   v
native GPU eligible
```

Fallback for Camera remains the current matrix preview until G1 is stable.

Never fall back by baking preview pixels into the captured source image.

### 2. Production renderer lifecycle contract

Define a real renderer/session lifecycle before attaching camera frames.

Suggested control messages:

```text
createRenderer
configureSurface
setFilm
setStrength
setViewport
setEnabled
pause
resume
destroyRenderer
```

Keep protocol versioned and avoid sending frame buffers through the MethodChannel.

The renderer should handle app lifecycle, camera switching, route changes, surface recreation, and GPU context loss without leaving stale native resources.

### 3. Move GPU probing off the Android UI thread

The current reference/capability harness performs EGL/shader work synchronously from the channel handler. Before production use, move this work to an appropriate background executor/coroutine and return the result asynchronously to Flutter.

Do not perform heavyweight EGL setup or parity validation repeatedly during normal camera startup.

Recommended behavior:

- cheap capability cache for normal startup
- full shader self-test once per app/device/version as needed
- invalidate cache if renderer init fails

### 4. Define color-space contract

This must be resolved before claiming Camera GPU preview visually matches Rust final output.

Document at least:

```text
camera source transfer/color space
-> GPU shader input assumptions
-> LUT domain
-> preview output space
-> Rust decode assumptions
-> export color space
```

The current parity harness proves LUT sampling math and atlas addressing, not full camera color-pipeline parity.

### 5. Prepare Android Camera surface/OES renderer interface

G0.3 should end with an interface ready for G1, not yet necessarily replacing the live camera preview.

Target G1 Android pipeline:

```text
Camera frame
-> external OES texture
-> OpenGL ES fragment shader
-> canonical Film LUT atlas
-> output Surface / Flutter texture/native view
```

No per-frame JPEG/PNG conversion.
No image stream through Dart.
No frame-by-frame Flutter Rust Bridge transfer.

## After G0.3 — G1

G1 goal: replace matrix approximation on Android Camera Film Preview with the real native GPU LUT renderer.

Required G1 validation:

- Film profile change updates live preview without rebuilding camera session.
- Strength updates through shader uniform/state only.
- >= 30 fps on the reference Android device.
- capture remains the clean original image.
- selected Film Profile still transfers into Editor/Rust final rendering.
- front/rear camera switching works.
- orientation/crop remains correct.
- app pause/resume and route navigation do not leak camera/GPU resources.
- renderer failure automatically falls back to matrix preview.

Once Android G1 is stable, implement the iOS peer with AVFoundation + Metal/Core Image under the same protocol semantics.

## Larger roadmap after GPU camera work

Do not implement these as isolated state systems. They should build on the Edit Graph and GPU/Rust dual-renderer architecture.

Recommended sequence:

```text
G0/G1 GPU core + camera
-> Editor GPU preview
-> Masks infrastructure
-> Selective adjustments
-> Text/Stickers overlays
-> Preset import/export
-> Batch processing
```

### Masks

Start with:

- Brush
- Erase
- Feather
- Invert
- mask overlay display

Then add:

- Linear gradient
- Radial gradient
- Luminance range
- Color range

Store normalized/vector/stroke instructions as source of truth. GPU rasterizes preview masks; Rust rasterizes the same instructions at final resolution.

### Selective adjustments

Implement adjustment nodes that reference masks, e.g. exposure, contrast, saturation, temperature/tint, highlights/shadows.

### Text/Stickers

Treat as non-destructive overlay nodes with semantic data, transform, opacity, blend mode and z-index. Do not permanently rasterize until final rendering.

### Preset import/export

Use a versioned Pixel Craft preset format based on a subset of Edit Graph, not a raw dump of UI state.

### Batch processing

Rust should replay the same Edit Graph/preset over many images with bounded concurrency. Mobile should start conservatively with low concurrency to control memory.

## Current technical debt / warnings

These are not blockers for G0.3 but should be handled separately:

1. `saver_gallery` and `share_plus` currently trigger Flutter warnings about plugins still applying Kotlin Gradle Plugin instead of Built-in Kotlin. Check for compatible plugin upgrades before a future Flutter version makes this an error.
2. Cargo warns that profiles declared in `rust/Cargo.toml` are ignored because the workspace root is the top-level `Cargo.toml`. Move/merge relevant profile configuration to the workspace root later.
3. AGP warns about the legacy `android {}` DSL under AGP 9/newDsl. Migrate to the public `ApplicationExtension` API in a dedicated cleanup change rather than mixing it into GPU renderer work.

## Useful commands

Host checks:

```bash
flutter analyze
flutter test test/state
flutter test test/ui --exclude-tags=golden
make gpu-lut-verify
```

Generate canonical LUTs and inspectable GPU assets:

```bash
make gpu-luts
```

Physical Android GPU parity test:

```bash
make gpu-native-test DEVICE=RF8Y909V0LV
```

## Instruction for the next chat

Start by reading this file and `docs/G0_GPU_PREVIEW_FOUNDATION.md`, then inspect the current `feature/camera-film-preview` branch before modifying files.

The immediate task is:

> Continue with G0.3: implement GPU capability/fallback policy, production renderer lifecycle contract, background capability probing, color-space contract, and Android Camera OES renderer interface preparation. Do not connect live camera frames until those contracts are stable.
