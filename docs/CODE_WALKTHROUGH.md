# PixelCraft Code Walkthrough

เอกสารนี้อธิบาย architecture ปัจจุบันของ PixelCraft ตั้งแต่เปิดแอป เลือกรูป ส่งงานผ่าน `flutter_rust_bridge` ไปยัง Rust, reduced-preview editing, operation history, full-resolution export, Film Profiles, Camera Film Preview และ native GPU preview จนถึง **G1 Android Camera2/OpenGL ES + G1 iOS AVFoundation/Metal**

> หลักการสำคัญ: Flutter รับผิดชอบ UI และ state projection ส่วน decode/filter/histogram/transform/operation replay/export อยู่ใน Rust โดยงาน synchronous FRB ที่หนักถูก dispatch ออกจาก UI isolate
>
> สำหรับ real-time native GPU preview นั้น Dart เป็น **control plane เท่านั้น**: ส่ง capability, lifecycle, Film Profile ID, strength และ camera control messages ขนาดเล็ก Native backend ถือครอง frame buffers เองทั้งหมด และ Rust ยังคงเป็น authoritative renderer สำหรับ final/full-resolution output

---

# 1. Current architecture summary

## Editor path

```text
Select image
  -> background isolate
  -> Rust load_image
  -> decode original
  -> build reduced editor preview (max edge 1024)
  -> histogram / thumbnail preparation

Interactive edit
  -> operate on reduced preview
  -> retain semantic EditOperation recipe

Apply
  -> promote reduced preview checkpoint
  -> retain full operation recipe
  -> no full-resolution render

Cancel
  -> restore previous reduced checkpoint
  -> discard current draft branch

Export
  -> decode untouched full-resolution original
  -> replay complete operation recipe once
  -> encode PNG/JPEG/WebP
```

## Camera Film Preview runtime selection

```text
CameraFilmPreviewScreen
  -> NativeGpuPreviewBridge.probe()
  -> GpuPreviewCapabilityPolicy.evaluate()

Android + native eligible
  -> androidOpenGl
  -> Camera2
  -> SurfaceTexture / GL_TEXTURE_EXTERNAL_OES
  -> OpenGL ES Film shader
  -> Android TextureView / AndroidView

iOS + native eligible
  -> iosMetal
  -> AVCaptureVideoDataOutput
  -> CVPixelBuffer
  -> CVMetalTextureCache
  -> Metal Film shader
  -> MTKView / UiKitView

native unavailable / probe fails / runtime failure
  -> Flutter camera plugin
  -> CameraPreview
  -> ColorFilter.matrix approximation
```

Capture is non-destructive in every path:

```text
Android native
  -> Camera2 JPEG ImageReader
  -> clean JPEG

iOS native
  -> AVCapturePhotoOutput
  -> clean JPEG

Fallback
  -> CameraController.takePicture()
  -> clean JPEG

all paths
  -> image path + Film profileId + strength
  -> CameraFilmEditorHandoff
  -> Editor
  -> Rust authoritative Film LUT
```

The matrix preview is a fallback approximation, not the Film Profile reference renderer.

---

# 2. Editor architecture

## Reduced-preview editing

`rust/src/engine.rs` keeps:

- untouched original compressed source
- complete `Vec<EditOperation>` recipe
- reduced `checkpoint_preview`
- active/draft operation cursor state

The editor preview is intentionally separated from export resolution. Interactive filters and transforms work on a reduced image while semantic operations are retained for final replay.

Supported operation classes include:

- Filter
- Crop
- Rotate90
- RotateDegrees / Straighten
- FlipHorizontal
- FlipVertical
- Resize

## Apply checkpoint model

Two important cursors:

```text
cursor
checkpoint_cursor
```

`cursor` points into the complete recipe. `checkpoint_cursor` marks the latest accepted Apply boundary.

Apply:

```text
current reduced preview
  -> cache as checkpoint preview
  -> checkpoint_cursor = cursor
  -> keep operations[0..cursor]
  -> reset draft UI count
```

Undo/Redo for draft edits remains bounded by the checkpoint. A new edit after Undo truncates the current draft redo tail.

## Full-resolution export

`export_image()` is intentionally the authoritative/expensive path:

```text
untouched full-resolution source
  -> decode once
  -> replay complete active EditOperation recipe
  -> encode requested output
```

Reduced checkpoints therefore do not progressively degrade final output.

## Flutter state / background execution

`lib/state/editor_controller.dart` projects Rust state into Flutter and tracks:

- preview bytes
- checkpoint preview
- histogram
- Adjust state
- creative filter selection/intensity
- thumbnail cache
- active tool
- busy state
- draft cursor values

`lib/core/image_engine.dart` isolates heavy synchronous FRB work from the UI isolate using `Isolate.run()`.

## Adjust / filters / transforms

Adjust sliders update UI immediately and commit expensive processing at controlled points rather than creating uncontrolled synchronous work on every UI event.

Creative filters operate against the reduced checkpoint and thumbnail generation is cached/prewarmed.

Crop/rotate/flip/straighten remain semantic operations. Straighten is constrained to the UI-supported range and final quality is preserved by full-resolution replay.

## Before / After

Before/After uses the cached reduced Apply checkpoint rather than repeatedly decoding the original source.

## Responsive editor

`EditorScreen` uses compact phone layout and switches to side-panel behavior on wide layouts. Heavy processing disables conflicting controls while work is in flight.

---

# 3. Shared Film / Edit Graph semantics

## Versioned Edit Graph

File:

```text
lib/core/edit_graph.dart
```

Current schema:

```text
3
```

Long-term model:

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
```

GPU backends must not invent a parallel Film/effect model. Future basic adjustments, masks, selective adjustments, text/stickers, presets and batch processing should share semantic parameters with Rust.

## Film profiles

Canonical Film definitions remain under Rust authoring data:

```text
rust/film_profiles/*/look.json
```

Build flow:

```text
look.json
  -> rust/build.rs
  -> canonical 33^3 lut.cube
       -> Rust renderer
       -> GPU LUT generator
```

Six current canonical Film IDs:

```text
provia_inspired
velvia_inspired
astia_inspired
e100_inspired
ektar_inspired
chrome64_inspired
```

---

# 4. GPU abstraction and policy

## Renderer-neutral types

`lib/gpu/gpu_preview_renderer.dart`

Backend kinds:

```text
fallback
androidOpenGl
iosMetal
```

`FallbackGpuPreviewRenderer` intentionally reports no real LUT33 support so approximation cannot be mistaken for native parity-capable rendering.

## Capability policy

`lib/gpu/gpu_preview_capability.dart`

Decision model:

```text
native probe
   |
   +-- protocol mismatch ----------> fallback
   +-- blacklisted ----------------> fallback
   +-- backend unavailable --------> fallback
   +-- LUT33 unsupported ----------> fallback
   +-- generated assets missing ---> fallback
   +-- self-test failed -----------> fallback
   |
   v
native GPU eligible
```

Runtime renderer failure invalidates capability cache and returns Camera Film Preview to the fallback path.

---

# 5. Native GPU protocol

## Core bridge

`lib/gpu/native_gpu_preview_bridge.dart`

Channel:

```text
dev.pixelcraft/gpu_preview_v1
```

Protocol version:

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

No raw camera/image frames are valid payloads for this channel.

## Shared Camera control bridge

`lib/gpu/native_gpu_camera_bridge.dart`

Shared native-camera messages:

```text
requestCameraPermission
availableCameraLenses
capturePhoto
switchCamera
runtimeFailure
```

Only small state/path/error values cross Dart/native boundary.

The older Android-specific bridge remains present for compatibility/tests, but `CameraFilmPreviewScreen` now uses the shared `NativeGpuCameraBridge` for both native platforms.

---

# 6. Camera Film Preview screen

Canonical implementation:

```text
lib/ui/screens/camera_film_preview_screen_g1.dart
```

Compatibility export:

```text
lib/ui/screens/camera_film_preview_screen.dart
```

## Startup

```text
initState()
  -> install native runtime failure handler
  -> _discoverAndInitialize()
  -> _tryInitializeNativeGpu()
```

Native attempt is allowed on:

```text
TargetPlatform.android
TargetPlatform.iOS
```

Probe success:

```text
request native camera permission
  -> query native lenses
  -> createRenderer()
  -> setEnabled(false) // Original
  -> render platform-specific native view
```

Probe/native failure:

```text
availableCameras()
  -> CameraController.initialize()
  -> CameraPreview + ColorFilter.matrix
```

## Platform view selection

```text
android -> AndroidGpuCameraPreview
     iOS -> IosGpuCameraPreview
```

The screen keeps one shared state model for:

- selected `CameraFilmPreset`
- strength
- native/fallback mode
- renderer ID
- native lens list
- capture state
- lifecycle
- Editor handoff

No separate iOS Film UI state was introduced.

## Film selection

Native Film:

```text
setFilm(rendererId, profileId, strength)
  -> setEnabled(true)
```

Original:

```text
setEnabled(false)
```

Strength slider:

```text
setStrength(rendererId, value)
```

Strength-only changes are intended to update renderer state/uniform only, not reload LUT data.

## Runtime failure

```text
native renderer failure
  -> runtimeFailure(rendererId, message)
  -> CameraFilmPreviewScreen
  -> clear native renderer ID
  -> destroyRenderer
  -> initialize Flutter camera fallback
```

The selected Film semantics remain available for Editor/Rust after fallback capture.

---

# 7. G1 Android Camera2 + OpenGL ES/OES

Detailed walkthrough:

```text
docs/walkthrough/14_g1_android_camera_oes.md
```

## PlatformView boundary

Flutter:

```text
lib/gpu/android_gpu_camera_preview.dart
```

Android:

```text
android/app/src/main/kotlin/dev/pixelcraft/pixelcraft/GpuCameraPreviewPlatformView.kt
```

View type:

```text
dev.pixelcraft/gpu_camera_preview_v1
```

Flutter sends only `rendererId`. Native `TextureView.SurfaceTexture` is wrapped as `Surface` and attached to the renderer registry without crossing MethodChannel.

## Renderer/session registry

```text
android/app/src/main/kotlin/dev/pixelcraft/pixelcraft/GpuPreviewRendererSession.kt
```

Each renderer ID owns one concrete `AndroidGpuCameraOesRenderer` and coordinates:

- output surface
- Film Profile
- strength
- enabled/original state
- pause/resume
- clean JPEG capture
- camera switching
- destruction

## Camera frame path

```text
Camera2 repeating request
  -> renderer-owned SurfaceTexture
  -> GL_TEXTURE_EXTERNAL_OES
  -> updateTexImage()
  -> OES shader
  -> 33^3 Film atlas sampling
  -> EGL window surface
  -> TextureView
```

Dedicated threads:

```text
PixelCraft-GpuCamera-Camera2
PixelCraft-GpuCamera-GL
```

No per-frame Dart callback.

## Android LUT atlas

Physical representation:

- LUT grid: 33^3
- tile grid: 6 x 6
- tile size: 33 x 33
- atlas: 198 x 198 RGBA8
- manual bilinear R/G interpolation
- linear interpolation across B slices
- no mipmaps

The Android device parity harness already validated this addressing/sampling model against Rust fixtures within the documented tolerance.

## Pending-LUT startup protection

`AndroidGpuCameraOesRenderer` keeps pending Film upload state if `setFilm()` arrives before the EGL window surface is attached.

After EGL surface creation the pending Film LUT is uploaded automatically. This prevents a startup race where UI state could select a Film while preview remained Original until another profile change.

Strength-only changes still do not re-upload LUT data.

## Android clean capture

```text
Camera2 TEMPLATE_STILL_CAPTURE
  -> JPEG ImageReader
  -> cache/pixelcraft-camera/capture-*.jpg
  -> path only to Dart
```

The OES/Film render surface is never used as source photo.

## Android lifecycle

Pause/inactive closes Camera2 resources while preserving renderer state. Resume ensures output GL state and reopens camera. Route disposal destroys Camera2/EGL/OES resources.

## Android status

The current path was run on the physical Android reference workflow after the latest fixes and the user reported no problem. Treat this as successful initial bring-up.

Still measure explicitly before cross-platform G1 completion:

- sustained >=30 fps
- orientation/front-camera combinations
- repeated lifecycle/context-loss stress
- end-to-end camera/display/Rust color-space parity

---

# 8. G1 iOS AVFoundation + Metal

Detailed walkthrough:

```text
docs/walkthrough/15_g1_ios_camera_metal.md
```

Current status:

```text
implemented in code
awaiting Xcode build
awaiting physical-iPhone validation
```

## Flutter PlatformView

```text
lib/gpu/ios_gpu_camera_preview.dart
```

uses:

```text
UiKitView
viewType = dev.pixelcraft/gpu_camera_preview_v1
creationParams = { rendererId }
```

Native host:

```text
ios/Runner/MetalCameraPreviewPlatformView.swift
```

`PixelCraftMetalView` subclasses `MTKView`, owns drawable sizing and reports `UIWindowScene.interfaceOrientation` to renderer state.

## App/plugin registration

```text
ios/Runner/AppDelegate.swift
ios/Runner/GpuPreviewChannel.swift
```

`GpuPreviewPlugin` registers the shared MethodChannel and PlatformView factory with Flutter's plugin registry.

`MetalRendererRegistry` maps renderer IDs to `MetalCameraPreviewRenderer` instances.

## iOS capability probe

```text
ios/Runner/GpuCapabilityProbe.swift
```

Probe executes off the Flutter/UI thread and checks:

```text
Metal device
canonical native Film assets
Metal shader compilation
33^3 texture allocation
canonical Film texture loading
```

Cache identity contains app version/build + iOS version + device model.

This is a startup/pipeline self-test. Numeric Metal-vs-Rust device parity remains a separate G1 exit requirement.

---

# 9. iOS canonical LUT path

## Build packaging

`ios/Runner.xcodeproj/project.pbxproj` includes:

```text
Generate Film LUT Assets
```

Build phase invokes:

```bash
make gpu-luts
```

with output under the built Runner bundle:

```text
gpu_luts/<profileId>.rgba8
```

Therefore iOS does not maintain independent Film look values.

## `MetalFilmLutLoader.swift`

The loader reads the same 198x198 RGBA8 atlas generated for canonical GPU use and unpacks it into:

```text
MTLTextureType3D
33 x 33 x 33
rgba8Unorm
```

Volume index semantics:

```text
R -> x
G -> y
B -> z
```

## 3D texture sampling contract

Metal normalized texture sampling must target texel centers.

Shader mapping:

```text
grid = clamp(source, 0..1) * 32
lutUv = (grid + 0.5) / 33
film = lut.sample(linearSampler, lutUv)
```

This preserves the canonical 33-point grid interpretation when using hardware trilinear filtering.

Do not simplify this to raw normalized `source` coordinates without parity evidence.

---

# 10. `MetalCameraPreviewRenderer`

File:

```text
ios/Runner/MetalCameraPreviewRenderer.swift
```

Owns:

- `AVCaptureSession`
- selected front/rear `AVCaptureDeviceInput`
- `AVCaptureVideoDataOutput`
- `AVCapturePhotoOutput`
- session queue
- render queue
- `CVMetalTextureCache`
- Metal device / command queue / pipeline
- current Film 3D texture
- Film strength/enabled state
- orientation/mirror state
- output `MTKView`

## Live frame path

Video output requests:

```text
kCVPixelFormatType_32BGRA
```

and uses:

```text
alwaysDiscardsLateVideoFrames = true
```

Frame processing:

```text
CMSampleBuffer
  -> CVPixelBuffer
  -> CVMetalTextureCacheCreateTextureFromImage
  -> MTLTexture2D(.bgra8Unorm)
  -> Metal render pass
  -> current MTKView drawable
```

No encoded intermediate image is allocated for Dart.

## Metal shader state

Bound resources:

```text
texture(0) = camera frame
texture(1) = 33^3 Film texture
buffer(0)  = cropScale / mirrorX / strength / useLut
```

Film changes load a new canonical 3D texture on the render queue without rebuilding `AVCaptureSession`.

Strength changes update only the Float state consumed by the next render.

## Center crop

Renderer compares source aspect with `MTKView.drawableSize` and passes crop scale to shader. This avoids stretching while preserving center-crop behavior.

Physical-device validation is still required for all orientation/device combinations.

---

# 11. iOS front mirror and orientation

AVFoundation connections receive orientation derived from `UIWindowScene.interfaceOrientation`.

Connection-level automatic mirroring is disabled.

Front-camera preview mirror happens in Metal:

```text
mirrorX = 1
```

Rear:

```text
mirrorX = 0
```

This keeps preview UX independent from clean captured-source pixels.

Must validate:

- portrait
- landscape left/right
- iPad upside-down where enabled
- front mirror
- rear non-mirror
- captured JPEG orientation/metadata

---

# 12. iOS clean capture

Still path deliberately bypasses Metal output:

```text
AVCapturePhotoOutput.capturePhoto()
  -> AVCapturePhoto.fileDataRepresentation()
  -> temporary/pixelcraft-camera/capture-<UUID>.jpg
  -> path only to Dart
```

The Camera screen separately carries `profileId` and `strength` into `CameraFilmEditorHandoff`.

Rust remains authoritative for Film in Editor/final output.

---

# 13. Native lifecycle / fallback

## App lifecycle

Shared Dart screen:

```text
inactive/paused
  -> pause(rendererId)

resumed
  -> resume(rendererId)
```

Android closes/reopens Camera2 while preserving Film state.

iOS stops/restarts `AVCaptureSession` while preserving Film state and native renderer session.

## Route lifecycle

Camera route disposal calls:

```text
destroyRenderer(rendererId)
```

Android releases Camera2/EGL/OES resources.

iOS removes renderer from registry, stops session, detaches video delegate and flushes/releases Metal texture cache state.

## Runtime fallback

Native fatal error:

```text
native renderer
  -> runtimeFailure(rendererId, message)
  -> capability cache invalidation
  -> renderer destruction
  -> Flutter camera plugin fallback
```

Capture remains clean after fallback.

---

# 14. Color-space contract

Reference:

```text
docs/G0_3_GPU_PREVIEW_CONTRACTS.md
```

Native LUT parity does not automatically prove camera-preview vs Rust-export visual parity.

Android boundaries still include:

- camera sensor/YUV conversion
- SurfaceTexture/display transfer assumptions
- display color management

Current iOS boundaries include:

```text
AVFoundation 32BGRA output
  -> CVMetalTexture .bgra8Unorm
  -> shader working values
  -> Film LUT domain
  -> MTKView drawable
  -> display color handling

clean JPEG
  -> Rust decode
  -> authoritative Film LUT
  -> export color space
```

Do not claim full visual parity until real-device images measure these boundaries.

HDR/wide-color behavior should remain constrained/explicit rather than accidentally enabled.

---

# 15. Build integration

## Android

Android generated Film assets use the typed Gradle generated-assets task and Variant API.

Do not revert to provider-backed `sourceSets.main.assets.srcDir(...)` workarounds.

## iOS

New Swift source files are added to Runner's Sources build phase:

```text
GpuPreviewChannel.swift
GpuCapabilityProbe.swift
MetalCameraPreviewRenderer.swift
MetalCameraPreviewPlatformView.swift
MetalFilmLutLoader.swift
```

Xcode also runs canonical LUT generation into the final app resource bundle before packaging/signing completes.

`Info.plist` already includes `NSCameraUsageDescription` for native AVFoundation permission flow.

---

# 16. Tests

Shared/native Dart tests include:

```text
test/state/native_gpu_preview_bridge_test.dart
test/state/android_gpu_camera_bridge_test.dart
test/state/native_gpu_camera_bridge_test.dart
test/gpu/gpu_preview_capability_test.dart
```

`native_gpu_camera_bridge_test.dart` verifies:

- permission request payload
- lens identifiers
- clean capture path-only response
- switch-camera response
- native runtime failure callback

Android native LUT parity remains covered by the existing device harness.

iOS still needs a numeric on-device Metal-vs-Rust parity harness before G1 exit.

---

# 17. Validation commands

## Host/shared

```bash
flutter pub get
make codegen
cargo fmt --manifest-path rust/Cargo.toml --all
cargo clippy --manifest-path rust/Cargo.toml --all-targets -- -D warnings
cargo test --manifest-path rust/Cargo.toml
flutter analyze
flutter test test/state
flutter test test/ui --exclude-tags=golden
make gpu-lut-verify
```

## Android

```bash
make gpu-native-test DEVICE=RF8Y909V0LV
flutter build apk --debug
flutter run -d RF8Y909V0LV
```

Initial Android bring-up has been reported as running without problems after the latest fixes.

## iOS

```bash
flutter build ios --debug
flutter devices
flutter run -d <IPHONE_DEVICE_ID>
```

Verify Xcode build phase:

```text
Generate Film LUT Assets
```

and confirm built app contains:

```text
gpu_luts/
  provia_inspired.rgba8
  velvia_inspired.rgba8
  astia_inspired.rgba8
  e100_inspired.rgba8
  ektar_inspired.rgba8
  chrome64_inspired.rgba8
```

---

# 18. iOS physical-device checklist

1. Probe reports `iosMetal`.
2. Camera UI shows `GPU FILM PREVIEW`.
3. Original preview is correct.
4. Six Film Profiles render live.
5. Film changes do not restart `AVCaptureSession`.
6. Strength slider does not reload LUT per tick.
7. Rear/front switching preserves Film state.
8. Front preview mirror is correct.
9. Rear preview is not mirrored.
10. Portrait orientation is correct.
11. Landscape left/right are correct.
12. Center crop has no stretching.
13. Clean JPEG comes from `AVCapturePhotoOutput`, not MTKView.
14. JPEG orientation/metadata is correct.
15. Film Profile/strength arrive in Editor unchanged.
16. Rust final renderer remains authoritative.
17. Editor -> Back -> Camera resumes safely.
18. Background -> foreground resumes safely.
19. Route exit/re-entry does not leak native resources.
20. Forced/runtime Metal failure returns to matrix fallback.
21. Sustained preview reaches >=30 fps.
22. Numeric Metal LUT fixture parity matches Rust tolerance.
23. Camera-preview vs Rust-final color-space behavior is documented from measurement.

---

# 19. G1 completion rule

G1 is cross-platform and is not complete simply because Android and iOS implementations exist.

Exit requires:

```text
Android native camera GPU stable
+iOS native camera GPU stable
+clean capture both platforms
+same Film semantic state
+camera switching/orientation/mirror/crop verified
+lifecycle/resource recreation verified
+>=30 fps both reference devices
+native LUT numeric parity both backends
+honest color-space contract
```

At the current point:

```text
Android: implementation + initial device bring-up passed
          deeper stress/perf/color proof still explicit work

iOS:     implementation complete in source
          Xcode/physical-device bring-up pending
```

---

# 20. Next stage after G1

Only after cross-platform Camera G1 stabilization should normal Editor interaction move to native GPU preview.

G2 target:

```text
Decoded editor preview source
  -> native GPU texture
  -> shared Edit Graph GPU-supported nodes
  -> interactive preview

same Edit Graph
  -> Rust final renderer
  -> full-resolution export
```

First GPU-supported Editor nodes should be:

```text
brightness / exposure
contrast
saturation
temperature / tint
Film Profile 33^3 LUT + strength
```

Unsupported nodes must fall back deterministically and must never be silently omitted.

Extension points should preserve future:

```text
mask textures
selective adjustment + maskId
text/sticker/overlay textures
transforms
blend/z-order
presets
batch
```

---

# Related walkthroughs

```text
docs/walkthrough/14_g1_android_camera_oes.md
docs/walkthrough/15_g1_ios_camera_metal.md
docs/G0_GPU_PREVIEW_FOUNDATION.md
docs/G0_3_GPU_PREVIEW_CONTRACTS.md
docs/CHAT_HANDOFF_GPU_PREVIEW.md
```
