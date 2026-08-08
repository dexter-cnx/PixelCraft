# PixelCraft Code Walkthrough

เอกสารนี้อธิบาย architecture ปัจจุบันของ PixelCraft ตั้งแต่เปิดแอป เลือกรูป ส่งงานผ่าน `flutter_rust_bridge` ไปยัง Rust, operation history, full-resolution export, transform tools, responsive editor, Film Profiles, Camera Film Preview, GPU Preview foundation จนถึง **G1 Android Camera2 + OpenGL ES/OES bring-up**

> หลักการสำคัญคือ Flutter รับผิดชอบ UI และ state projection ส่วนงาน decode, filter, histogram, transform, operation replay และ export อยู่ใน Rust โดยงานหนักที่เรียกผ่าน synchronous FRB API ถูก dispatch ผ่าน background Dart isolate เพื่อลดการ block UI isolate
>
> สำหรับ real-time GPU preview นั้น Dart เป็น **control plane เท่านั้น**: ส่ง capability, renderer lifecycle และ effect state ขนาดเล็กไป native backend โดยไม่ส่ง camera/image frame buffers ผ่าน MethodChannel หรือ Flutter Rust Bridge. Rust ยังคงเป็น authoritative renderer สำหรับ final/full-resolution output

## Current flow summary

```text
Select image
  -> background isolate -> Rust load_image
  -> decode and build one reduced editor preview (max edge 1024)
  -> histogram from reduced preview
  -> background prewarm of creative-filter thumbnails

Adjust / Creative Filter / Crop / Rotate / Flip / Straighten
  -> operate only on the reduced editor preview
  -> retain EditOperation recipe for full-resolution replay

Apply
  -> promote the already-rendered reduced preview to the next checkpoint
  -> keep the full EditOperation recipe
  -> reset draft cursor/UI state
  -> no full-resolution processing

Cancel
  -> restore the previous reduced Apply checkpoint
  -> discard the current draft branch

Export
  -> decode untouched original at full resolution
  -> replay the complete EditOperation recipe once
  -> encode requested PNG/JPEG/WebP
```

Android Camera Film Preview now has two runtime paths:

```text
Android + GPU eligible
  -> Camera2
  -> renderer-owned SurfaceTexture / GL_TEXTURE_EXTERNAL_OES
  -> OpenGL ES Film LUT shader
  -> native TextureView inside AndroidView

Android unsupported / GPU failure / iOS
  -> Flutter camera plugin
  -> CameraPreview
  -> ColorFilter.matrix approximation
```

Capture remains non-destructive in both paths:

```text
Native GPU preview path
  -> Camera2 JPEG ImageReader
  -> clean JPEG file

Fallback path
  -> CameraController.takePicture()
  -> clean JPEG file

Both
  -> selected Film Profile state
  -> Editor
  -> Rust authoritative 33^3 Film LUT
```

The matrix camera preview remains a safe fallback and is not the Film Profile reference renderer.

---

# Editor architecture

## Reduced-preview editing architecture

PixelCraft deliberately separates **interactive editing resolution** from **export resolution**.

`rust/src/engine.rs` keeps the untouched full-resolution compressed source bytes plus the complete `Vec<EditOperation>`. The editor also keeps a cached `checkpoint_preview` whose maximum edge is currently 1024 pixels. Interactive filters and transforms replay only operations after the latest Apply checkpoint against this reduced image.

This removes the hot path where every preview operation could decode/replay the original full-resolution image and resize it again for display. Apply also stays inexpensive because it does not render the full-resolution source.

Supported operations include:

- Filter
- Crop
- Rotate90
- RotateDegrees / Straighten
- FlipHorizontal
- FlipVertical
- Resize

## Apply checkpoints and operation recipe

The engine uses two cursor concepts:

- `cursor` — absolute position in the complete operation recipe
- `checkpoint_cursor` — boundary marking operations accepted by the latest Apply

The UI reports only draft operations after `checkpoint_cursor`. After Apply the editor can return to `0/0 edits` while the complete operation recipe is still retained for export.

```text
current reduced preview
  -> encode/cache as checkpoint preview
  -> checkpoint_cursor = cursor
  -> retain operations[0..cursor]
  -> reset UI draft count
```

Undo is bounded by the latest Apply checkpoint. A new edit after Undo truncates only the current draft redo tail.

## Full-resolution export

`export_image()` is intentionally the expensive path:

```text
untouched full-resolution source
  -> decode once
  -> replay complete active operation recipe
  -> encode PNG/JPEG/WebP
```

Applied checkpoints therefore do not degrade output quality by repeatedly baking reduced intermediate images.

## Flutter state and background processing

`lib/state/editor_controller.dart` projects Rust engine state into Flutter. It tracks:

- preview bytes
- checkpoint preview
- histogram
- Adjust selection
- creative filter selection/intensity
- thumbnail cache
- active tool
- busy state
- draft cursor values

`lib/core/image_engine.dart` wraps heavy synchronous FRB calls with `Isolate.run()`. Decode, preview preparation, filters, transforms, Apply, Cancel, Undo/Redo, histogram work and full-resolution export therefore stay away from the UI isolate.

## Adjust controls

`FilterSlider` changes its local thumb/value while dragging and sends processing work on release. Processing occurs against the reduced working preview.

Repeated adjustment of the same draft parameter replaces the active draft operation rather than stacking multiple equivalent operations before Apply.

## Creative filters

Creative filters include grayscale, invert, vintage, oceanic, lofi, dramatic, golden and pastel pink.

`generate_filter_previews()` decodes the already-small checkpoint source once, reduces it for thumbnails, runs variants in parallel with Rayon and caches the result.

Changing creative filter or intensity replaces the same draft Filter operation. After Apply changes the checkpoint, PixelCraft prewarms a new thumbnail set from the new checkpoint.

## Shared Apply / Cancel workflow

`EditorToolPanel` exposes shared Cancel and Apply controls for Adjust, Filters, Crop and Rotate workflows.

Apply promotes the reduced preview checkpoint while retaining the semantic recipe. Cancel restores the previous checkpoint and removes the active draft branch.

## Transform tools

Crop uses normalized centered presets such as 1:1, 4:3, 3:4, 16:9 and 9:16. Rotate supports quarter turns. Flip supports horizontal/vertical. Straighten is constrained to -15°..15°.

Preview processing stays at reduced editor resolution while semantic operations are retained for full-resolution replay.

## Before / After

`original_preview()` returns the cached reduced preview for the latest Apply checkpoint. Long press compares the current draft against that checkpoint rather than decoding the original full-resolution image again.

## Import / export storage

Gallery/camera input enters Editor as a source path or byte buffer. Export writes an app-private backup and publishes to the device photo gallery. Android public exports use `Pictures/PixelCraft`.

## Responsive UI

`EditorScreen` uses a compact vertical layout on phones and a side tool panel from 900 px upward. Editing controls are temporarily disabled while background processing is active.

---

# Camera Film Preview

## Non-destructive Film Camera rule

Camera Film Preview affects what the user sees, not the source capture.

The invariant is:

```text
preview effect != captured source mutation
```

If GPU rendering is available, Android uses the canonical LUT atlas for live preview. If GPU rendering is unavailable or fails, PixelCraft switches to the existing matrix approximation.

Neither path bakes Film preview pixels into the captured source. Film state is handed to Editor and Rust remains responsible for authoritative rendering.

## Flutter Camera screen runtime selection

Canonical implementation:

`lib/ui/screens/camera_film_preview_screen_g1.dart`

Compatibility entrypoint:

`lib/ui/screens/camera_film_preview_screen.dart`

The compatibility file exports the G1 screen so existing imports do not need to change.

Startup flow:

```text
CameraFilmPreviewScreen.initState()
  -> NativeGpuPreviewBridge.probe()
  -> GpuPreviewCapabilityPolicy.evaluate()

eligible Android
  -> request CAMERA permission
  -> query native camera lenses
  -> createRenderer()
  -> render AndroidGpuCameraPreview(rendererId)

not eligible / non-Android
  -> availableCameras()
  -> CameraController.initialize()
  -> ColorFilter.matrix fallback preview
```

The fallback path remains fully usable while G1 is being validated.

## Film selection on native GPU path

Film chips still use the same `CameraFilmPreset` IDs.

For native Android GPU preview:

```text
select Film Profile
  -> setFilm(profileId, strength)
  -> native renderer uploads/selects canonical LUT atlas
  -> setEnabled(true)
```

Selecting Original uses:

```text
setEnabled(false)
```

Strength slider changes use:

```text
setStrength(rendererId, value)
```

The renderer stores strength independently and the shader reads it through `uStrength`. Strength-only changes do **not** intentionally parse or upload the LUT again.

## Clean capture handoff

Native Android capture:

```text
shutter
  -> AndroidGpuCameraBridge.capturePhoto(rendererId)
  -> Camera2 TEMPLATE_STILL_CAPTURE
  -> JPEG ImageReader Surface
  -> cache/pixelcraft-camera/capture-<timestamp>.jpg
  -> Dart receives file path only
  -> CameraFilmEditorHandoff
```

Fallback capture:

```text
shutter
  -> CameraController.takePicture()
  -> XFile.path
  -> CameraFilmEditorHandoff
```

Both paths pass:

- clean source image path
- selected Film Profile ID
- Film strength

The Editor/Rust path remains unchanged.

---

# Shared Edit Graph and GPU architecture

## Versioned Edit Graph

`lib/core/edit_graph.dart` defines the shared versioned edit contract. Current schema version: `3`.

Long-term renderer model:

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

GPU code must not invent a second semantic effect-state model. Film Profiles, adjustments, masks, overlays and future presets should converge on the same Edit Graph semantics.

## GPU preview renderer abstraction

`lib/gpu/gpu_preview_renderer.dart` defines renderer-neutral Dart capability/state types.

Backends:

- `fallback`
- `androidOpenGl`
- `iosMetal`

`FallbackGpuPreviewRenderer` intentionally reports no real LUT33 support so callers can distinguish approximation from parity-capable GPU rendering.

Dart owns state/control messages only, never live preview pixels.

---

# G0.3 capability and lifecycle foundation

## Capability and fallback policy

`lib/gpu/gpu_preview_capability.dart`

Decision flow:

```text
Native probe
   |
   +-- protocol mismatch ----------> fallback
   +-- device/GPU blacklisted -----> fallback
   +-- backend unavailable --------> fallback
   +-- LUT33 unsupported ----------> fallback
   +-- generated assets missing ---> fallback
   +-- shader self-test failed ----> fallback
   |
   v
native GPU eligible
```

Fallback reasons include:

- `protocolMismatch`
- `backendUnavailable`
- `lut33Unsupported`
- `shaderSelfTestFailed`
- `nativeAssetsUnavailable`
- `rendererInitializationFailed`
- `runtimeRenderFailure`
- `blacklisted`

Renderer initialization/runtime failure invalidates cached capability data before later retry.

## Native GPU control protocol

`lib/gpu/native_gpu_preview_bridge.dart`

Channel:

```text
dev.pixelcraft/gpu_preview_v1
```

Protocol version:

```text
1
```

Core renderer controls:

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

No encoded image or raw frame buffer crosses this channel during live preview.

## Renderer/session lifecycle

`lib/gpu/gpu_preview_session.dart` defines the Dart-side lifecycle contract.

```text
idle
  -> createRenderer
created
  -> surface available
surfaceConfigured
  -> pause
paused
  -> resume
surfaceConfigured / created
  -> destroyRenderer
destroyed
```

The native renderer can therefore survive normal state changes without rebuilding Camera2 simply because the user changes Film strength.

## Background capability probing

`android/app/src/main/kotlin/dev/pixelcraft/pixelcraft/GpuPreviewChannel.kt`

Capability EGL/shader validation executes on a dedicated single-thread executor rather than synchronously inside the Android MethodChannel/UI-thread handler.

Explicit G0.2 harness calls use the same background execution rule.

## Capability cache and native assets

`android/app/src/main/kotlin/dev/pixelcraft/pixelcraft/GpuCapabilityProbe.kt`

The production probe verifies generated LUT assets and caches capability results against app/device identity including app version/build, `Build.FINGERPRINT` and SDK level.

`GpuPreviewBlacklist` provides an evidence-based device/renderer exclusion hook.

---

# G1 Android Camera2 + OES renderer

For the detailed G1 code-by-code walkthrough, also see:

`docs/walkthrough/14_g1_android_camera_oes.md`

## Android PlatformView boundary

Flutter host:

`lib/gpu/android_gpu_camera_preview.dart`

Native host:

`android/app/src/main/kotlin/dev/pixelcraft/pixelcraft/GpuCameraPreviewPlatformView.kt`

View type:

```text
dev.pixelcraft/gpu_camera_preview_v1
```

Flutter sends only `rendererId` when creating the AndroidView.

The native PlatformView uses `TextureView`. Its `SurfaceTexture` is wrapped in an Android `Surface` and attached directly to the native renderer registry.

```text
Flutter AndroidView
  -> native TextureView
  -> output Surface
  -> renderer registry
  -> EGL window surface
```

The actual Android `Surface` never crosses MethodChannel.

## Native renderer session registry

`android/app/src/main/kotlin/dev/pixelcraft/pixelcraft/GpuPreviewRendererSession.kt`

Each renderer ID now owns one concrete `AndroidGpuCameraOesRenderer`.

The registry coordinates:

- output Surface attach/detach
- Film Profile
- Film strength
- enabled/original state
- pause/resume
- clean JPEG capture
- front/rear switching
- destruction

## Camera2/OES renderer

`android/app/src/main/kotlin/dev/pixelcraft/pixelcraft/AndroidGpuCameraOesRenderer.kt`

The renderer creates two dedicated threads:

```text
PixelCraft-GpuCamera-Camera2
PixelCraft-GpuCamera-GL
```

Live frame path:

```text
Camera2 repeating preview request
  -> renderer-owned Surface
  -> SurfaceTexture
  -> GL_TEXTURE_EXTERNAL_OES
  -> SurfaceTexture.updateTexImage()
  -> OES fragment shader
  -> canonical 33^3 Film LUT atlas
  -> EGL window surface
  -> native TextureView
```

No per-frame Dart callback occurs.

## Canonical LUT shader

The live Camera shader uses the same atlas structure already validated by G0.2:

- 33^3 LUT
- 6 x 6 tiles
- 33 x 33 texels per tile
- 198 x 198 RGBA8 atlas
- manual bilinear R/G interpolation
- linear interpolation between adjacent B slices

Assets come from:

```text
assets/gpu_luts/<profileId>.rgba8
```

These atlases are generated from the canonical Rust Film LUT output, not from the fallback matrices.

## Camera orientation / crop state

The OES shader receives:

```text
uSurfaceTextureMatrix
uCropScale
uRotationSteps
uMirrorX
```

The renderer combines Camera sensor orientation, Android display rotation, front-camera mirroring and center-crop behavior.

This code is implemented but exact portrait/front/rear behavior remains a **physical-device validation item** before G1 can be called complete.

## Android Camera permission

`android/app/src/main/kotlin/dev/pixelcraft/pixelcraft/MainActivity.kt`

Because eligible Android devices bypass `CameraController.initialize()`, the native GPU path cannot rely on the Flutter camera plugin to request permission.

`MainActivity` therefore owns the CAMERA runtime permission request and returns only the boolean result through the existing GPU control channel.

## Android Camera2 control bridge

`lib/gpu/android_gpu_camera_bridge.dart`

G1-specific control messages:

```text
requestCameraPermission
availableCameraLenses
capturePhoto
switchCamera
runtimeFailure    // native -> Dart
```

Only permission state, lens identifiers, renderer IDs, error strings and clean capture file paths cross this bridge.

## Runtime GPU failure -> matrix fallback

Fatal renderer/camera failures call the registry runtime failure listener.

```text
AndroidGpuCameraOesRenderer
  -> GpuPreviewRendererSessionRegistry.runtimeFailureListener
  -> GpuPreviewChannel
  -> invalidate capability cache
  -> runtimeFailure(rendererId, message)
  -> CameraFilmPreviewScreen
  -> remove Android GPU path
  -> destroy renderer
  -> initialize Flutter camera fallback
```

The selected Film state remains intact, so the user can continue with the matrix approximation and still get authoritative Rust rendering after capture.

## App lifecycle and route lifecycle

App pause/inactive:

```text
CameraFilmPreviewScreen
  -> pause(rendererId)
  -> close Camera2 session/device
```

App resume:

```text
resume(rendererId)
  -> ensure output EGL state
  -> reopen Camera2
  -> restart repeating preview
```

Before navigating into Editor after native capture, the camera renderer is paused. After returning, the same renderer session resumes.

Destroying the Camera route destroys the renderer and releases Camera2/EGL/OES resources.

---

# Color-space contract

`docs/G0_3_GPU_PREVIEW_CONTRACTS.md` defines the color-pipeline boundary:

```text
camera source transfer / color space
  -> GPU shader input assumptions
  -> LUT domain
  -> preview output space
  -> Rust decoder assumptions
  -> export color space
```

G0.2 proves LUT atlas sampling/addressing for deterministic RGB fixture values.

G1 adds real camera frames, but full visual parity still requires validation of:

- Camera YUV -> RGB conversion
- transfer/gamma assumptions
- camera primaries
- HDR/wide-gamut behavior
- Android display color management
- Rust decoded JPEG vs live camera preview conversion

Do not claim full camera-to-Rust visual parity until those boundaries are measured.

---

# Tests and validation

## Host/editor checks

```bash
flutter pub get
make codegen
cargo fmt --manifest-path rust/Cargo.toml --all
cargo clippy --manifest-path rust/Cargo.toml --all-targets -- -D warnings
cargo test --manifest-path rust/Cargo.toml
flutter analyze
flutter test test/state
flutter test test/ui --exclude-tags=golden
```

## GPU foundation checks

```bash
flutter test test/gpu/gpu_preview_capability_test.dart
make gpu-lut-verify
make gpu-luts
make gpu-native-test DEVICE=RF8Y909V0LV
```

## G1 Android build/device checks

```bash
flutter build apk --debug
flutter run -d RF8Y909V0LV
```

Manual G1 validation:

1. Camera screen shows `GPU FILM PREVIEW` on an eligible Android device.
2. Original preview has no Film LUT applied.
3. All six Film Profiles update live without rebuilding Camera2.
4. Strength slider remains responsive and does not reload the LUT per tick.
5. Capture opens Editor with a clean source and the selected Film state.
6. Front/rear switching works.
7. Portrait orientation, crop and front-camera mirroring are correct.
8. App pause/resume recovers the camera preview.
9. Camera -> Editor -> Camera route round-trip does not leak resources.
10. Forced renderer failure automatically selects matrix fallback.
11. Sustained preview reaches the G1 target of >= 30 fps on the reference device.

## Current G1 status

Implemented in code:

- Camera2 native ownership
- renderer-owned external OES texture
- OpenGL ES LUT shader
- canonical generated LUT atlas usage
- TextureView PlatformView output
- native CAMERA permission flow
- Film Profile state updates
- strength-only state update hook
- clean JPEG ImageReader capture
- front/rear switching
- pause/resume/destroy lifecycle
- runtime failure fallback signaling
- Dart control-plane tests

Still requiring Android/device proof:

- Kotlin/Android compilation on the project toolchain
- first live OES frame on RF8Y909V0LV
- portrait/front/rear orientation and crop
- capture EXIF/orientation correctness
- >= 30 fps measurement
- repeated route/lifecycle/context-loss stress tests
- end-to-end visual parity against Rust under the documented color-space contract

Until those checks pass, the matrix approximation remains the production safety fallback.
