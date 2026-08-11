# Pixel Craft — GPU Preview Chat Handoff

Last updated: 2026-08-08
Branch: `feature/camera-film-preview`

## Current status

Pixel Craft now has:

- G0 GPU preview contracts/foundation
- Android G1 Camera2 + OpenGL ES/OES Camera Film Preview
- iOS G1 AVFoundation + Metal Camera Film Preview implementation
- shared Dart control plane for native camera backends
- clean/non-destructive capture path on both native designs
- Rust-authoritative Film Profile/final render semantics

Android physical-device bring-up was run after the latest Android fixes and the user reported no problem. Treat that as **initial Android bring-up passed**, but do not silently convert it into proof that every stress/performance/color-space exit criterion has been measured.

iOS G1 is now **implemented in code, awaiting Xcode and physical-iPhone validation**.

The architecture remains:

```text
Camera / Editor input
        |
        v
   Edit Graph / Film state
        |
        +-----------------------------+-----------------------------+
        |                                                           |
        v                                                           v
Native GPU Preview                                          Rust Final Renderer
interactive / low latency                                   authoritative / full-res
Android OpenGL ES / iOS Metal                               Editor final + export
```

Core invariants:

1. Rust remains the source of truth for Film Profile semantics and final/full-resolution rendering.
2. Live camera/image frame buffers must never be sent through Dart MethodChannel or Flutter Rust Bridge.
3. Dart is control-plane only.
4. Capture must remain clean; preview effects must not be baked into the captured source.
5. GPU unsupported/runtime failure must fall back to the existing Flutter camera + matrix approximation without changing source semantics.

---

# Confirmed G0 / Android foundation

The Android LUT parity pipeline has passed on physical reference device:

```bash
make gpu-native-test DEVICE=RF8Y909V0LV
```

Observed previously:

```text
+2: All tests passed!
```

That established:

- six canonical 33^3 Film LUTs materialize from Rust Film Profile Pack v2
- GPU atlas generation completes
- atlas/reference parity max error is about 0.0017–0.0019/channel
- result is below `2/255` tolerance
- Android generated LUT assets package correctly
- Android OpenGL ES shader harness runs on real hardware

This proves LUT sampling/addressing parity for the fixture pipeline. It does **not** prove complete camera-to-export visual parity across camera conversion, transfer functions, primaries, HDR/wide gamut or display color management.

Detailed color contract:

```text
docs/G0_3_GPU_PREVIEW_CONTRACTS.md
```

---

# Shared GPU semantic/control layer

## Versioned Edit Graph

File:

```text
lib/core/edit_graph.dart
```

Current schema:

```text
3
```

Do not create backend-specific effect semantics. GPU preview, Rust render, future masks/selective adjustments/overlays/presets/batch should converge on the same Edit Graph meaning.

## Renderer abstraction

```text
lib/gpu/gpu_preview_renderer.dart
```

Backends:

```text
fallback
androidOpenGl
iosMetal
```

The matrix Camera preview is a fallback approximation only, not the Film reference renderer.

## Native GPU renderer protocol

```text
lib/gpu/native_gpu_preview_bridge.dart
```

Channel:

```text
dev.pixelcraft/gpu_preview_v1
```

Protocol:

```text
1
```

Shared renderer controls:

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
invalidateCapabilityCache
```

## Shared native Camera control bridge

New shared Dart file:

```text
lib/gpu/native_gpu_camera_bridge.dart
```

It exposes Camera-specific messages used by both Android and iOS:

```text
requestCameraPermission
availableCameraLenses
capturePhoto
switchCamera
runtimeFailure       // native -> Dart
```

Only small control values/path strings cross the channel.

`lib/gpu/android_gpu_camera_bridge.dart` still exists for compatibility/tests but the G1 Camera screen now uses `NativeGpuCameraBridge` so Android and iOS share one control state model.

Tests:

```text
test/state/native_gpu_camera_bridge_test.dart
```

---

# G1 Android Camera GPU Preview

## Status

Implementation is connected to live Camera2/OES frames.

The user ran the current Android path after the latest fixes and reported no problem. Record this as **initial physical-device bring-up passed**.

Still distinguish that from explicit proof of:

- sustained >=30 fps measurement
- long lifecycle/context-loss stress
- every orientation/front-camera combination
- full camera-preview vs Rust color-space parity

## Android native frame path

```text
Camera2
  -> SurfaceTexture
  -> GL_TEXTURE_EXTERNAL_OES
  -> OpenGL ES shader
  -> canonical Film 33^3 LUT atlas
  -> EGL window surface
  -> native TextureView
  -> Flutter AndroidView
```

Important files:

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

Flutter host:

```text
lib/gpu/android_gpu_camera_preview.dart
```

Detailed walkthrough:

```text
docs/walkthrough/14_g1_android_camera_oes.md
```

## Latest Android bring-up fix

`AndroidGpuCameraOesRenderer` now preserves a pending Film LUT upload if `setFilm()` arrives before an EGL window surface is available.

Without this, a Film selection during PlatformView/EGL startup could be accepted by Dart state but fail to upload until another Film change.

The renderer now retries the pending LUT after EGL surface attach while strength-only ticks still remain state/uniform-only.

## Android clean capture

```text
Camera2
  -> JPEG ImageReader
  -> clean JPEG
  -> path to Dart
  -> CameraFilmEditorHandoff(profileId, strength)
  -> Rust authoritative Film rendering
```

No preview shader pixels become the captured source.

---

# G1 iOS Camera GPU Preview

## Status

**Implemented in code; Xcode build and physical-device validation still required.**

Detailed code walkthrough:

```text
docs/walkthrough/15_g1_ios_camera_metal.md
```

Canonical project walkthrough:

```text
docs/CODE_WALKTHROUGH.md
```

## iOS native architecture

```text
AVCaptureSession
  -> AVCaptureVideoDataOutput
  -> CVPixelBuffer (32BGRA)
  -> CVMetalTextureCache
  -> MTLTexture2D
  -> Metal fragment shader
  -> canonical Film MTLTexture3D 33^3
  -> MTKView
  -> Flutter UiKitView
```

No per-frame Dart/FRB traffic.

## iOS files

```text
ios/Runner/
  AppDelegate.swift
  GpuPreviewChannel.swift
  GpuCapabilityProbe.swift
  MetalCameraPreviewRenderer.swift
  MetalCameraPreviewPlatformView.swift
  MetalFilmLutLoader.swift
```

Dart files involved:

```text
lib/gpu/native_gpu_preview_bridge.dart
lib/gpu/native_gpu_camera_bridge.dart
lib/gpu/ios_gpu_camera_preview.dart
lib/ui/screens/camera_film_preview_screen_g1.dart
```

Xcode integration:

```text
ios/Runner.xcodeproj/project.pbxproj
```

The new Swift files are added to Runner Sources and a generated-LUT build phase is added.

---

## iOS `GpuPreviewChannel.swift`

`GpuPreviewPlugin` registers:

```text
dev.pixelcraft/gpu_preview_v1
dev.pixelcraft/gpu_camera_preview_v1
```

Responsibilities:

- protocol v1 negotiation
- Metal capability probe
- renderer registry/session creation
- Film/strength/enabled updates
- camera permission
- front/rear lens query/switch
- clean photo capture
- pause/resume/destroy
- runtime failure callback to Dart
- Flutter PlatformView factory registration

`MetalRendererRegistry` owns one `MetalCameraPreviewRenderer` per renderer ID.

---

## iOS capability probe

```text
ios/Runner/GpuCapabilityProbe.swift
```

Probe runs on a utility queue and verifies:

```text
Metal device available
canonical generated Film assets present
Metal shader source compiles
identity 33^3 texture can be created
canonical Film 3D texture can be loaded
```

Successful backend payload reports:

```text
backend = iosMetal
available = true
supportsLut33 = true
maxLutSize = 33
selfTestPassed = true
assetsLoaded = true
```

Capability cache identity includes:

```text
cache schema
app version
app build
iOS version
device model
```

Renderer initialization/runtime failure invalidates the capability cache through the shared Dart/native policy.

Important limitation: this startup self-test is **not yet a numeric Metal-vs-Rust parity harness**. Numeric device parity remains an iOS G1 exit item.

---

## iOS generated Film LUT assets

Canonical source remains:

```text
rust/film_profiles/*/look.json
        -> rust/build.rs
        -> canonical 33^3 lut.cube
        -> tool/generate_gpu_lut_atlas.py
        -> <profileId>.rgba8
```

Xcode Runner includes build phase:

```text
Generate Film LUT Assets
```

It runs the existing project generator:

```bash
make -C "$PROJECT_ROOT" gpu-luts \
  GPU_LUT_DIR="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/gpu_luts"
```

This keeps iOS from authoring or committing a second Film definition.

The six generated `.rgba8` atlases are placed in the built app bundle under:

```text
gpu_luts/
```

---

## iOS `MetalFilmLutLoader.swift`

Android uses the 198x198 tiled atlas directly.

iOS reads the exact same generated atlas bytes and unpacks them to:

```text
MTLTextureType3D
33 x 33 x 33
RGBA8Unorm
```

Index mapping preserves canonical dimensions:

```text
R = x within tile
G = y within tile
B = tile index
```

The Metal shader uses hardware trilinear interpolation.

### Critical texel-center rule

Canonical input `0...1` represents grid points `0...32`.

Metal normalized texture coordinates therefore use:

```text
grid = clamp(color) * 32
lutUv = (grid + 0.5) / 33
```

before 3D texture sampling.

Do not replace this with raw `lut.sample(..., color)`; that shifts sampling by half a texel and changes LUT semantics.

---

## iOS `MetalCameraPreviewRenderer.swift`

Owns:

- `AVCaptureSession`
- current `AVCaptureDeviceInput`
- `AVCaptureVideoDataOutput`
- `AVCapturePhotoOutput`
- session queue
- render queue
- `CVMetalTextureCache`
- Metal device/queue/pipeline
- current 33^3 Film texture
- Film profile/strength/enabled state
- front/rear state
- interface orientation
- output `MTKView`
- runtime failure reporting

Video output:

```text
kCVPixelFormatType_32BGRA
alwaysDiscardsLateVideoFrames = true
```

Per frame:

```text
CMSampleBuffer
  -> CVPixelBuffer
  -> CVMetalTextureCacheCreateTextureFromImage
  -> camera MTLTexture2D
  -> bind Film MTLTexture3D
  -> render to current MTKView drawable
```

Strength changes update a Float only. They do not reload/reparse Film assets.

Film changes load a new canonical generated profile texture without rebuilding `AVCaptureSession`.

---

## iOS PlatformView

Flutter host:

```text
lib/gpu/ios_gpu_camera_preview.dart
```

View type:

```text
dev.pixelcraft/gpu_camera_preview_v1
```

Native host:

```text
ios/Runner/MetalCameraPreviewPlatformView.swift
```

Flutter sends only:

```text
rendererId
```

`PixelCraftMetalView` updates drawable size and forwards current `UIWindowScene.interfaceOrientation` to the renderer.

---

## iOS orientation / mirror contract

AVFoundation output connections receive native video orientation.

AVFoundation mirroring is deliberately disabled for both video/photo connections.

Front preview mirroring happens only in the Metal shader:

```text
mirrorX = front ? 1 : 0
```

This separates preview UX from clean captured-source semantics.

Validate on real hardware:

- portrait
- landscape left/right
- iPad upside-down where supported
- front mirror
- rear non-mirror
- crop vs clean captured photo orientation

---

## iOS clean capture

Capture never snapshots `MTKView`.

```text
AVCapturePhotoOutput
  -> AVCapturePhoto.fileDataRepresentation()
  -> temporary/pixelcraft-camera/capture-<UUID>.jpg
  -> path to Dart
  -> CameraFilmEditorHandoff
```

Film `profileId` and `strength` are sent separately as semantic state.

Rust remains authoritative when the Editor/final render applies Film.

---

## Shared Camera screen after iOS G1

```text
lib/ui/screens/camera_film_preview_screen_g1.dart
```

Native selection is now allowed on both:

```text
TargetPlatform.android
TargetPlatform.iOS
```

Flow:

```text
probe
  |
  +-- androidOpenGl eligible -> AndroidGpuCameraPreview
  |
  +-- iosMetal eligible ------> IosGpuCameraPreview
  |
  +-- anything else ----------> Flutter camera/matrix fallback
```

The same screen owns:

- Film preset state
- Film strength
- native/fallback selection
- shutter
- camera switching
- lifecycle
- Editor handoff
- runtime failure fallback

No independent iOS Film state model was introduced.

---

# G1 iOS validation

Run on the project Mac:

```bash
flutter analyze
flutter test test/state
flutter test test/ui --exclude-tags=golden
make gpu-lut-verify
flutter build ios --debug
```

Then physical iPhone:

```bash
flutter devices
flutter run -d <IPHONE_DEVICE_ID>
```

Confirm Xcode phase:

```text
Generate Film LUT Assets
```

Validate:

1. `probe` selects `iosMetal` on supported physical iPhone.
2. UI shows `GPU FILM PREVIEW`.
3. Original preview is correct.
4. All six Film Profiles update live.
5. Strength changes smoothly without rebuilding `AVCaptureSession`.
6. Strength-only ticks do not reload Film LUT.
7. Rear/front switching works and preserves Film state.
8. Front preview mirror is correct.
9. Rear preview is not mirrored.
10. Portrait orientation is correct.
11. Landscape left/right are correct.
12. Center crop does not stretch frames.
13. Capture produces clean JPEG bytes from `AVCapturePhotoOutput`.
14. Captured orientation/metadata is correct.
15. Film Profile/strength transfer into Editor.
16. Rust final rendering remains authoritative.
17. Editor -> Back -> Camera resumes safely.
18. App background -> foreground resumes safely.
19. Route exit/re-entry releases/recreates resources safely.
20. Runtime Metal failure falls back to matrix preview.
21. Sustained preview reaches >=30 fps.
22. Numeric Metal 3D LUT parity matches Rust within documented tolerance.
23. Camera-preview vs Rust-final color-space limitations are measured/documented before visual-parity claims.

---

# G1 cross-platform exit criteria

Do **not** mark G1 complete merely because both implementations build.

Required:

- Android native Camera GPU Preview stable on reference device
- iOS native Camera GPU Preview stable on physical iPhone
- six Film Profiles functional on both backends
- profile changes do not rebuild camera sessions
- strength updates are state/uniform-only
- >=30 fps on reference Android and iOS hardware
- captured source remains clean
- Film state transfers into Editor unchanged
- Rust remains authoritative for final rendering
- front/rear switching works
- orientation/crop/mirroring correct
- lifecycle/route navigation do not leak resources
- runtime renderer failure returns deterministically to fallback
- native LUT numeric parity covered on Android and iOS
- color-space limitations documented honestly

---

# Known validation/technical debt after this implementation

1. iOS Swift/Xcode compilation has not been run in this assistant environment; first Mac build may expose API/toolchain issues that require bring-up fixes.
2. iOS Metal preview has not yet produced a live physical-iPhone frame in this chat.
3. iOS numeric Metal-vs-Rust LUT parity harness still needs device proof.
4. End-to-end camera conversion/display/Rust color-space parity remains unproven on both platforms.
5. Android initial bring-up passed according to the user's latest run, but sustained performance/stress/color-space measurements should remain explicit checks rather than assumptions.
6. `saver_gallery` / `share_plus` may still emit unrelated legacy Kotlin/Gradle warnings.
7. Cargo profile/workspace and AGP DSL warnings remain separate cleanup work unless they block GPU bring-up.

---

# After G1 — G2 Editor GPU Preview

Only after cross-platform G1 validation should work move to normal Editor GPU preview.

Target:

```text
Decoded editor preview source
  -> native GPU texture
  -> shared Edit Graph GPU-supported nodes
  -> interactive native preview

same Edit Graph
  -> Rust final renderer
  -> full-resolution export
```

First G2 nodes should remain:

```text
exposure / brightness
contrast
saturation
temperature / tint
Film Profile 33^3 LUT + strength
```

Unsupported nodes must fall back deterministically; never silently skip Edit Graph operations.

---

# Useful references

Read:

```text
docs/G0_GPU_PREVIEW_FOUNDATION.md
docs/G0_3_GPU_PREVIEW_CONTRACTS.md
docs/walkthrough/14_g1_android_camera_oes.md
docs/walkthrough/15_g1_ios_camera_metal.md
docs/CODE_WALKTHROUGH.md
```

Useful checks:

```bash
flutter analyze
flutter test test/state
flutter test test/ui --exclude-tags=golden
make gpu-lut-verify
make gpu-luts
make gpu-native-test DEVICE=RF8Y909V0LV
flutter build apk --debug
flutter build ios --debug
```

---

# Instruction for the next chat

Start by reading this file and inspecting the current `feature/camera-film-preview` branch.

Immediate priority:

> Bring up G1 iOS on the project Mac and a physical iPhone. First resolve any Swift/Xcode build errors, then validate generated LUT packaging, first Metal camera frame, all six Film Profiles, strength-only updates, front/rear switching, orientation/crop/mirroring, clean `AVCapturePhotoOutput` capture, Editor handoff, lifecycle/route recreation, fallback behavior and >=30 fps. Add a numeric Metal-vs-Rust LUT parity device harness before marking cross-platform G1 complete.

Do not redesign the existing protocol or non-destructive architecture merely to solve a device-specific bring-up issue unless evidence shows the contract itself is wrong.
