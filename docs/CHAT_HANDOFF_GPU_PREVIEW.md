# Pixel Craft — GPU Preview Chat Handoff

Last updated: 2026-08-08
Branch: `feature/camera-film-preview`

## Current status

Pixel Craft now has the G0 GPU foundation plus the first G1 Android Camera GPU Preview implementation.

The architecture remains non-destructive:

```text
Camera / Editor input
        |
        v
   Edit Graph / Film state
        |
        +-------------------------+-------------------------+
        |                                                   |
        v                                                   v
Native GPU Preview                                  Rust Final Renderer
interactive / low latency                           authoritative / full-res
Android Camera + future iOS Camera                  Export + Editor final render
```

Rust remains the source of truth for Film Profile semantics and final/full-resolution rendering.

Live camera/image frame buffers must never be sent through Dart MethodChannel or Flutter Rust Bridge. Dart is control-plane only.

Capture must remain clean. Preview effects must never be baked into the captured source merely to support fallback.

---

## Confirmed foundation before G1

The Android LUT parity pipeline has already passed on the physical reference device.

Confirmed command:

```bash
make gpu-native-test DEVICE=RF8Y909V0LV
```

Observed result:

```text
+2: All tests passed!
```

This confirmed:

- Rust Film Profile Pack v2 materializes all six canonical 33^3 LUTs.
- GPU atlas generation completes for all six profiles.
- Atlas/reference parity max error is about 0.0017–0.0019 per channel.
- This is below the agreed `2/255` tolerance.
- `native_parity.json` is generated.
- Generated LUT assets are packaged into the Android app.
- Android OpenGL ES shader harness executes on the physical device.
- Native Film LUT parity integration tests pass.

---

# G0 status — foundation complete for Android G1 bring-up

## Versioned Edit Graph

File:

```text
lib/core/edit_graph.dart
```

Schema version:

```text
3
```

The Edit Graph is the long-term semantic contract for:

- GPU preview
- Film Profiles
- basic adjustments
- Masks
- Selective adjustments
- Text/Stickers
- Presets
- Batch processing
- Rust final rendering

Do not create a separate GPU-only effect model with different semantics.

## GPU renderer abstraction

File:

```text
lib/gpu/gpu_preview_renderer.dart
```

Backend kinds:

- `fallback`
- `androidOpenGl`
- `iosMetal`

The matrix-based Camera preview remains a fallback approximation only.

It must not be treated as the Film Profile reference renderer.

## Native GPU protocol

File:

```text
lib/gpu/native_gpu_preview_bridge.dart
```

Channel:

```text
dev.pixelcraft/gpu_preview_v1
```

Protocol version:

```text
1
```

Lifecycle/control operations include:

```text
probe
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

Android also exposes Camera-specific control operations for the G1 native Camera2 path.

## GPU capability / fallback policy

File:

```text
lib/gpu/gpu_preview_capability.dart
```

The production policy distinguishes:

- protocol mismatch
- backend unavailable
- LUT33 unsupported
- shader self-test failed
- generated native assets unavailable
- renderer initialization failed
- runtime render failure
- explicitly blacklisted device/GPU

Decision model:

```text
probe native backend
   |
   +-- protocol mismatch ----------> fallback
   +-- blacklisted ----------------> fallback
   +-- unavailable ----------------> fallback
   +-- LUT33 unsupported ----------> fallback
   +-- assets unavailable ---------> fallback
   +-- self-test failed -----------> fallback
   |
   v
native GPU eligible
```

Fallback remains preview-only and never mutates the captured source.

## Background capability probing

Android no longer performs EGL/shader probing synchronously from the MethodChannel UI-thread handler.

Heavy probe/harness work is serialized on a background executor.

Normal Camera startup uses a cached capability result instead of recreating EGL repeatedly.

Cache identity includes:

```text
cache schema
+ app version name
+ app version code
+ Android Build.FINGERPRINT
+ SDK level
```

Renderer initialization failure invalidates the cache.

Relevant file:

```text
android/app/src/main/kotlin/dev/pixelcraft/pixelcraft/GpuCapabilityProbe.kt
```

## Android generated Film LUT assets

Canonical path remains:

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
- 33 x 33 texels per tile
- 198 x 198 RGBA8 atlas
- manual bilinear R/G interpolation
- linear interpolation between adjacent B slices
- no mipmaps

Generated Android assets are integrated through the typed Gradle generated-assets task and Android Variant API.

Do not revert to provider-backed `sourceSets.main.assets.srcDir(...)` workarounds.

## Color-space contract

Detailed contract:

```text
docs/G0_3_GPU_PREVIEW_CONTRACTS.md
```

The current device parity harness proves LUT sampling/addressing parity only.

It does NOT by itself prove complete visual parity for:

- camera YUV -> RGB conversion
- transfer/gamma conversion
- camera color primaries
- wide-gamut/HDR input
- preview display color management
- Rust decoder vs native Camera preview conversion

Do not claim full Camera-to-export visual parity until this is measured on real images/devices.

---

# G1 Android Camera GPU Preview — implemented, awaiting device validation

G1 Android implementation is now connected to live camera frames.

The native frame path is:

```text
Camera2
  -> SurfaceTexture
  -> GL_TEXTURE_EXTERNAL_OES
  -> OpenGL ES fragment shader
  -> canonical Film 33^3 LUT atlas
  -> EGL window surface
  -> native TextureView
  -> Flutter AndroidView
```

There is no per-frame JPEG/PNG conversion and no live frame round-trip through Dart or Flutter Rust Bridge.

## Important Android files

```text
android/app/src/main/kotlin/dev/pixelcraft/pixelcraft/
  AndroidGpuCameraOesRenderer.kt
  GpuCameraOesRenderer.kt
  GpuCameraPreviewPlatformView.kt
  GpuPreviewRendererSession.kt
  GpuPreviewChannel.kt
  GpuCapabilityProbe.kt
  MainActivity.kt
```

Dart-side files:

```text
lib/gpu/android_gpu_camera_bridge.dart
lib/gpu/android_gpu_camera_preview.dart
lib/gpu/native_gpu_preview_bridge.dart
lib/ui/screens/camera_film_preview_screen.dart
lib/ui/screens/camera_film_preview_screen_g1.dart
```

Tests added/updated:

```text
test/state/android_gpu_camera_bridge_test.dart
test/state/native_gpu_preview_bridge_test.dart
test/gpu/gpu_preview_capability_test.dart
```

Detailed walkthrough:

```text
docs/walkthrough/14_g1_android_camera_oes.md
```

Canonical project walkthrough was also updated:

```text
docs/CODE_WALKTHROUGH.md
```

## Android native renderer responsibilities

`AndroidGpuCameraOesRenderer` now owns:

- Camera2 camera device/session
- dedicated Camera2 worker thread
- dedicated GL thread
- external OES texture
- input `SurfaceTexture`
- EGL display/context/window surface
- Film LUT atlas texture
- Film Profile state
- Film strength
- front-camera mirror state
- preview rotation/crop state
- JPEG capture through a separate `ImageReader`
- camera switching
- pause/resume/release lifecycle
- runtime failure reporting

## Android output surface

The native preview is hosted by a Flutter PlatformView using a native `TextureView`.

The `TextureView` output `Surface` is attached directly to the native renderer.

Flutter continues to draw Film controls, top bar and shutter UI above the native view.

The frame path stays entirely native.

## Android Film updates

Film Profile changes update native Film state/LUT texture without rebuilding the camera session.

Strength changes are intended to update shader state/uniform only.

Do not parse/re-upload the Film LUT on every strength slider tick.

## Android clean capture path

Capture is separate from the preview shader path:

```text
Camera2
  -> JPEG ImageReader
  -> clean JPEG file
  -> file path returned to Dart
  -> CameraFilmEditorHandoff
  -> Editor
  -> Rust authoritative Film LUT
```

Only a file path crosses the MethodChannel.

The Film effect remains semantic state and is not baked into the JPEG by the GPU preview renderer.

## Android fallback behavior

Normal startup:

```text
probe GPU
   |
   +-- eligible ----> create native renderer -> native Camera2/OES preview
   |
   +-- not eligible -> existing Flutter camera plugin + matrix approximation
```

Runtime native failure:

```text
native renderer failure
   -> report failure to Dart
   -> invalidate GPU capability cache
   -> destroy native renderer/session
   -> switch Camera Film Preview back to matrix fallback
```

The fallback remains the existing camera-plugin path.

## Android camera switching

Front/rear switching is handled natively on the GPU path.

Switching cameras must not require rebuilding the Flutter route and must preserve current Film Profile/strength state.

## Android permission handling

The native Camera2 path requires runtime CAMERA permission.

`MainActivity` now handles the permission request used by the native GPU Camera bridge.

## Android validation still required

G1 Android is not complete until it passes real device validation.

Reference device:

```text
RF8Y909V0LV
```

Run:

```bash
flutter analyze
flutter test test/state
flutter test test/ui --exclude-tags=golden
make gpu-lut-verify
make gpu-native-test DEVICE=RF8Y909V0LV
flutter build apk --debug
flutter run -d RF8Y909V0LV
```

Validate:

1. Film Camera selects native GPU path on an eligible device.
2. UI shows `GPU FILM PREVIEW`.
3. Original preview is correct.
4. All six Film Profiles update live.
5. Strength slider updates smoothly without camera restart.
6. Strength updates do not reload/parse LUT each tick.
7. Rear/front camera switching works.
8. Front camera mirror behavior is correct.
9. Portrait/landscape orientation is correct.
10. Center-crop/aspect behavior is correct.
11. Capture produces a clean JPEG.
12. Selected Film Profile/strength transfers into Editor.
13. Rust final rendering still applies the authoritative Film LUT.
14. Editor -> Back -> Camera recreates resources safely.
15. App background -> foreground recreates resources safely.
16. No stale camera/EGL resources remain after route exit.
17. Renderer failure switches automatically to matrix fallback.
18. Preview reaches at least 30 fps on the reference device.

## Android items likely to need tuning during bring-up

Expect first-device work around:

- Camera2 sensor/display rotation mapping
- front-camera mirror transform
- preview aspect/crop transform
- SurfaceTexture transform matrix
- EGL context/surface recreation
- Camera session restart after app lifecycle changes
- frame pacing / redundant draw scheduling
- output `TextureView` composition behavior
- device-specific camera stream size selection

Do not rewrite the lifecycle/protocol contract unless device evidence shows it is necessary.

---

# G1 iOS Camera GPU Preview — required after Android stabilization

G1 is cross-platform and is not considered complete with Android alone.

Once Android G1 is stable, implement the iOS peer under the same Dart protocol and semantic contract.

Preferred native architecture:

```text
AVFoundation
  -> AVCaptureVideoDataOutput / camera pixel buffer
  -> CVPixelBuffer
  -> CVMetalTextureCache
  -> Metal texture
  -> Metal fragment/compute shader
  -> canonical Film LUT
  -> CAMetalLayer / MTKView / Flutter PlatformView
```

Alternative Core Image use is acceptable only if it preserves the same LUT semantics, predictable color handling and low-latency lifecycle behavior.

Do not send camera frames through Dart or FRB on iOS either.

## iOS implementation goals

Add an `iosMetal` peer that follows the same control-plane semantics:

```text
probe
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

Camera-specific peer functionality should cover:

```text
request camera permission
list/select front/rear camera
start preview
switch camera
capture clean photo
runtime renderer failure
```

Reuse the existing Dart renderer/session APIs rather than creating an unrelated iOS state model.

## Suggested iOS native components

Likely structure:

```text
ios/Runner/
  GpuPreviewChannel.swift
  GpuCapabilityProbe.swift
  MetalCameraPreviewRenderer.swift
  MetalCameraPreviewPlatformView.swift
  MetalFilmLutLoader.swift
```

Exact filenames can vary, but responsibilities should stay separated.

### `GpuPreviewChannel.swift`

Responsibilities:

- protocol v1 negotiation
- production capability probe
- renderer/session lifecycle
- Camera control messages
- runtime failure notification

### `GpuCapabilityProbe.swift`

Probe at least:

- Metal device availability
- required texture/LUT support
- native LUT assets present
- shader/pipeline creation succeeds
- self-test result
- explicit device/GPU blacklist if ever required

Capability probing must not perform expensive repeated startup work on the Flutter/UI thread.

Use a cache policy equivalent in spirit to Android.

### `MetalCameraPreviewRenderer.swift`

Responsibilities:

- `AVCaptureSession`
- selected `AVCaptureDevice`
- video frame delivery
- `CVMetalTextureCache`
- Metal command queue/pipeline state
- Film LUT texture
- Film strength uniform
- orientation/mirror state
- output drawable/surface lifecycle
- pause/resume/release
- runtime error reporting

### `MetalCameraPreviewPlatformView.swift`

Expose a native GPU preview view through Flutter PlatformView while allowing Flutter controls to remain layered above it.

Prefer `MTKView` or a well-contained `CAMetalLayer` host.

## iOS canonical LUT source

Do not author separate iOS Film looks.

The iOS renderer must consume data generated from the same canonical Rust LUT source:

```text
rust/film_profiles/*/look.json
        -> rust/build.rs
        -> canonical 33^3 LUT
             -> Rust final renderer
             -> Android GPU asset
             -> iOS Metal GPU asset
```

If iOS uses a native 3D Metal texture instead of the Android 2D atlas representation, generation may differ physically while the sampled LUT values and interpolation contract must remain equivalent.

The canonical Film definition stays in Rust authoring data.

## Recommended iOS LUT representation

Metal can use a real 3D LUT texture if device/version support is appropriate:

```text
MTLTextureType3D
33 x 33 x 33
RGBA8 or a documented higher precision format
linear sampling
```

This can simplify shader lookup compared with Android's tiled 2D atlas.

However, parity fixtures must prove that sampling matches Rust semantics within the agreed tolerance.

Do not assume Metal 3D texture sampling is equivalent without tests.

## iOS clean capture path

Preview rendering and still capture must remain separate.

Target:

```text
AVCapturePhotoOutput
  -> original camera photo
  -> file/path/data ownership handled natively
  -> clean source handed to Editor
  -> selected Film state handed separately
  -> Rust authoritative final rendering
```

Do not capture the `MTKView`/Metal preview output as the source photo.

## iOS orientation and mirroring

Explicitly validate:

- portrait
- portrait upside-down if supported
- landscape left/right
- front camera mirroring
- rear camera orientation
- preview crop vs captured image orientation

Use native camera/video orientation metadata and renderer transforms rather than rotating pixel buffers through Dart.

## iOS color-space requirements

Before claiming visual parity, document and test:

```text
AVFoundation pixel format / transfer function
-> CoreVideo/Metal texture interpretation
-> shader working space
-> Film LUT domain
-> MTKView/CAMetalLayer output color space
-> captured photo decode in Rust
-> final export color space
```

Avoid accidental HDR/wide-color behavior until explicitly supported.

A safe first implementation may deliberately constrain preview to an SDR/sRGB-like contract if that matches Rust's current assumptions.

## iOS capability/fallback policy

Expected decision flow:

```text
probe Metal backend
   |
   +-- protocol mismatch ----------> fallback
   +-- Metal unavailable ----------> fallback
   +-- LUT format unsupported -----> fallback
   +-- native assets unavailable --> fallback
   +-- shader self-test failed ----> fallback
   +-- blacklisted ----------------> fallback
   |
   v
native iOS GPU eligible
```

Fallback on iOS should remain the existing Flutter camera preview/matrix approximation until Metal G1 is validated.

Runtime Metal failure must tear down the native renderer and return to fallback without losing the clean-capture semantics.

## iOS validation requirements

Test on at least one physical iPhone. An iPad test is strongly recommended because Pixel Craft supports responsive layouts.

Validate:

1. Metal capability probe does not stall UI startup.
2. Native GPU preview appears on supported devices.
3. Original preview path works.
4. All Film Profiles render.
5. Strength changes through uniforms/state only.
6. Film change does not rebuild `AVCaptureSession`.
7. Front/rear switching works.
8. Mirror/orientation is correct.
9. Capture remains clean/original.
10. Film state transfers to Editor/Rust.
11. Background/foreground works.
12. Route exit/re-entry does not leak capture/Metal resources.
13. Surface/view recreation works.
14. Runtime renderer failure returns to fallback.
15. Preview reaches at least 30 fps on reference hardware.
16. LUT parity fixtures match Rust within documented tolerance.

---

# G1 cross-platform exit criteria

Do not mark G1 complete until both Android and iOS satisfy the same functional contract.

Required:

- Android real GPU Camera Film Preview stable.
- iOS real GPU Camera Film Preview stable.
- profile changes do not rebuild camera sessions.
- strength updates are uniform/state-only.
- >= 30 fps on reference Android and iOS devices.
- captured source remains clean on both platforms.
- selected Film Profile/strength transfers into Editor.
- Rust remains authoritative for final rendering.
- front/rear switching works.
- orientation/crop/mirroring are correct.
- pause/resume and route navigation do not leak resources.
- renderer failure returns deterministically to fallback.
- Film LUT sampling parity is covered on both native GPU backends.
- color-space limitations are documented honestly.

---

# After G1 — G2 Editor GPU Preview

G2 goal: move normal Editor interaction away from repeated Rust preview-image round trips toward the same native GPU preview architecture while keeping Rust as the authoritative final renderer.

Target:

```text
Decoded editor source image
        |
        v
native GPU texture
        |
        v
Edit Graph -> GPU-supported nodes
        |
        v
interactive preview surface

same Edit Graph
        |
        v
Rust final renderer -> export/full-res
```

## G2.1 — Editor GPU surface/source texture

- independent Editor GPU renderer session
- upload/decode editor preview source once
- no JPEG/PNG resend per slider tick
- recreate texture/surface after lifecycle/context loss
- Rust preview remains deterministic fallback
- explicit source texture ownership

## G2.2 — First GPU-supported nodes

Start with:

```text
exposure / brightness
contrast
saturation
temperature / tint
Film Profile 33^3 LUT + strength
```

UI values must map to canonical Edit Graph parameters shared with Rust.

## G2.3 — Mixed GPU/Rust fallback

Unsupported Edit Graph nodes must never be silently skipped.

Initial acceptable strategies:

- whole-preview Rust fallback, or
- supported GPU prefix plus a Rust checkpoint when ordering is safe

## G2.4 — Preview/final parity

Test at least:

- each basic adjustment independently
- Film LUT at strengths 0 / 0.5 / 1.0
- adjustment + Film LUT ordering
- boundary/clamp values
- enabled/disabled nodes
- Edit Graph serialization round-trip

## G2.5 — Performance

Target:

- continuous sliders remain responsive
- no encoded preview image allocation per slider tick
- no LUT reload when only strength changes
- no main-thread GPU setup
- latest-wins/coalesced state updates where appropriate

## G2.6 — Extension points

Leave clean extension points for:

```text
mask textures
selective adjustment + maskId
overlay/text/sticker textures + transforms
blend/z-order
```

---

# Larger roadmap

Recommended order:

```text
G0 GPU foundation/contracts
-> G1 Android Camera GPU Preview
-> G1 iOS Camera GPU Preview
-> G2 Android/iOS Editor GPU Preview
-> Masks infrastructure
-> Selective adjustments
-> Text/Stickers overlays
-> Preset import/export
-> Batch processing
```

Masks and overlays must build on the Edit Graph rather than creating parallel UI-only state systems.

---

# Current technical debt / warnings

These are separate cleanup items and should not be mixed into Camera GPU bring-up unless they become blockers.

1. `saver_gallery` and `share_plus` may warn about legacy Kotlin Gradle Plugin application behavior.
2. Cargo profiles declared in `rust/Cargo.toml` may be ignored because the workspace root is the top-level `Cargo.toml`.
3. AGP warns about legacy `android {}` DSL/newDsl migration.
4. Full Camera preview vs Rust final color-space parity is still not proven end-to-end.
5. Android G1 currently requires real-device validation before it can be called stable.

---

# Useful commands

Host checks:

```bash
flutter analyze
flutter test test/state
flutter test test/ui --exclude-tags=golden
```

GPU LUT checks:

```bash
make gpu-lut-verify
make gpu-luts
```

Physical Android GPU parity:

```bash
make gpu-native-test DEVICE=RF8Y909V0LV
```

Android G1 bring-up:

```bash
flutter build apk --debug
flutter run -d RF8Y909V0LV
```

---

# Instruction for the next chat

Start by reading:

```text
docs/CHAT_HANDOFF_GPU_PREVIEW.md
docs/G0_GPU_PREVIEW_FOUNDATION.md
docs/G0_3_GPU_PREVIEW_CONTRACTS.md
docs/walkthrough/14_g1_android_camera_oes.md
docs/CODE_WALKTHROUGH.md
```

Then inspect the current `feature/camera-film-preview` branch before modifying files.

Immediate priority:

> Finish G1 Android device bring-up. Fix compile/runtime issues, validate orientation/crop/mirroring, camera switching, lifecycle, clean capture, runtime fallback and >=30 fps on the reference Android device. Preserve the existing protocol and non-destructive capture model unless device evidence requires a contract change.

After Android G1 is stable:

> Implement the G1 iOS peer with AVFoundation + Metal under the same protocol semantics. Keep frames native, use the canonical Film LUT source, preserve clean still capture, add Metal capability/self-test/fallback behavior, validate orientation/front-camera mirroring/lifecycle/performance on physical iOS hardware, and do not mark G1 complete until both Android and iOS are stable.

Only after cross-platform G1 is stable should work proceed to G2 Editor GPU Preview.
