# G1 Android Camera OES — Code Walkthrough

Status: initial implementation / device validation required
Branch: `feature/camera-film-preview`

G1 replaces the Android Film Camera matrix approximation with a native Camera2 + OpenGL ES preview on devices that pass the G0.3 capability policy. Rust remains the authoritative final renderer and the captured source JPEG remains clean.

## Runtime decision flow

`lib/ui/screens/camera_film_preview_screen_g1.dart`

Startup now follows this sequence:

```text
CameraFilmPreviewScreen
  -> NativeGpuPreviewBridge.probe()
  -> GpuPreviewCapabilityPolicy.evaluate()
      -> not eligible: existing Flutter camera + ColorFilter.matrix fallback
      -> eligible:
           -> AndroidGpuCameraBridge.requestCameraPermission()
           -> availableCameraLenses()
           -> NativeGpuPreviewBridge.createRenderer()
           -> AndroidGpuCameraPreview(rendererId)
```

The native path is Android-only. iOS and unsupported/failed Android devices stay on the existing `camera` plugin preview until the iOS peer is implemented.

If native rendering fails after startup, Android invokes the `runtimeFailure` control message. The Flutter screen destroys the failed renderer, invalidates its capability cache, and initializes the existing matrix fallback camera flow.

No fallback path modifies the captured source pixels.

## Flutter native preview host

`lib/gpu/android_gpu_camera_preview.dart`

`AndroidGpuCameraPreview` is a thin `AndroidView`. Its creation parameters contain only:

```text
rendererId
```

It does not receive camera frames, JPEG data, LUT bytes, or image buffers.

View type:

```text
dev.pixelcraft/gpu_camera_preview_v1
```

## Android PlatformView

`android/app/src/main/kotlin/dev/pixelcraft/pixelcraft/GpuCameraPreviewPlatformView.kt`

The PlatformView uses `TextureView` as the GPU output host. When Android creates or resizes its `SurfaceTexture`, the view creates an Android `Surface` and attaches it directly to the renderer registry.

```text
Flutter AndroidView
  -> native TextureView
  -> TextureView SurfaceTexture
  -> Surface
  -> GpuPreviewRendererSessionRegistry.attachOutputSurface()
  -> AndroidGpuCameraOesRenderer.configureOutputSurface()
```

The actual `Surface` never crosses MethodChannel.

`TextureView` is used instead of placing a second independent `SurfaceView` over the Flutter view hierarchy, making composition with the Film controls/shutter UI more predictable.

## Native renderer registry

`android/app/src/main/kotlin/dev/pixelcraft/pixelcraft/GpuPreviewRendererSession.kt`

Each `rendererId` owns one `AndroidGpuCameraOesRenderer`.

The registry coordinates:

- output Surface attach/detach
- selected Film Profile
- Film strength
- enabled/original state
- pause/resume
- clean JPEG capture
- front/rear camera switching
- renderer destruction

Film strength is now a strength-only update. Moving the slider updates renderer state/uniform input and does not intentionally reload the 33^3 LUT atlas.

## Camera2 -> OES pipeline

`android/app/src/main/kotlin/dev/pixelcraft/pixelcraft/AndroidGpuCameraOesRenderer.kt`

The renderer owns two dedicated Android threads:

```text
PixelCraft-GpuCamera-Camera2
PixelCraft-GpuCamera-GL
```

The intended frame path is:

```text
Camera2 repeating preview request
  -> Surface backed by renderer-owned SurfaceTexture
  -> GL_TEXTURE_EXTERNAL_OES
  -> SurfaceTexture.updateTexImage()
  -> external-OES fragment shader
  -> canonical Film LUT atlas
  -> EGL window surface
  -> TextureView / Flutter PlatformView
```

Dart is not part of this per-frame path.

### OES texture ownership

The GL thread creates:

- EGL display/config/context
- external OES texture
- renderer-owned input `SurfaceTexture`
- Camera2 input `Surface`
- shader program
- Film LUT texture

Camera2 targets the OES-backed `Surface` directly.

### Film LUT sampling

The Camera shader uses the same atlas layout established in G0:

```text
33^3 LUT
6 x 6 tiles
33 x 33 texels per tile
198 x 198 RGBA8 atlas
manual bilinear R/G interpolation
linear interpolation between adjacent B slices
```

The LUT asset path is:

```text
assets/gpu_luts/<profileId>.rgba8
```

Profile selection can upload/change the LUT texture. Strength changes update the scalar renderer state used by shader uniform `uStrength`.

`Original` disables Film application without baking or modifying camera input.

## Preview orientation and crop

The renderer combines:

- Camera sensor orientation
- Android display rotation
- front-camera mirroring
- SurfaceTexture transform matrix
- center-crop scale to fill the output viewport

The shader receives:

```text
uSurfaceTextureMatrix
uCropScale
uRotationSteps
uMirrorX
```

This is the first implementation and must be verified on the physical reference device in portrait, front camera and rear camera before the orientation/crop exit criterion is considered complete.

## Clean capture path

G1 capture is intentionally separate from the Film preview render target.

The Camera2 capture session contains both:

```text
preview target -> external OES Surface
still target   -> JPEG ImageReader Surface
```

When the user presses the shutter:

```text
CameraDevice.TEMPLATE_STILL_CAPTURE
  -> JPEG ImageReader
  -> app cache / pixelcraft-camera/capture-<timestamp>.jpg
  -> AndroidGpuCameraBridge.capturePhoto()
  -> Dart receives file path only
  -> CameraFilmEditorHandoff
  -> Rust applies selected canonical Film Profile in Editor/final renderer
```

The Film shader output is never used as the capture source.

Therefore:

```text
preview = non-destructive GPU effect
capture = clean camera JPEG
final Film render = Rust 33^3 LUT
```

## Camera permission

`android/app/src/main/kotlin/dev/pixelcraft/pixelcraft/MainActivity.kt`

The Android GPU path cannot rely on `CameraController.initialize()` to request permission because G1 bypasses the Flutter camera plugin on eligible Android devices.

`MainActivity` therefore owns the runtime CAMERA permission request and exposes its boolean result over the existing versioned GPU control channel.

Only permission state crosses the channel.

## G1 control-plane additions

`lib/gpu/android_gpu_camera_bridge.dart`

Additional Android Camera2 controls are:

```text
requestCameraPermission
availableCameraLenses
capturePhoto
switchCamera
runtimeFailure (native -> Dart)
```

Existing G0.3 lifecycle controls remain:

```text
createRenderer
setFilm
setStrength
setEnabled
pause
resume
destroyRenderer
```

These are state/control messages only.

## Lifecycle

When the app becomes inactive/paused:

```text
CameraFilmPreviewScreen.didChangeAppLifecycleState()
  -> pause(rendererId)
  -> renderer closes Camera2 session/device
```

On resume:

```text
resume(rendererId)
  -> renderer ensures output EGL surface
  -> Camera2 opens again
  -> repeating OES preview resumes
```

Before navigating to Editor after a native capture, the screen pauses the native camera renderer. After returning, it resumes the same renderer session.

Destroying the route destroys the renderer and releases Camera2, EGL, OES, LUT and SurfaceTexture resources.

## Runtime failure fallback

`AndroidGpuCameraOesRenderer` reports fatal renderer/camera errors through the registry to `GpuPreviewChannel`.

The channel:

1. invalidates the G0.3 capability cache;
2. sends `runtimeFailure(rendererId, message)` to Dart.

The Camera screen then:

1. removes the native AndroidView path;
2. destroys the renderer;
3. initializes the existing Flutter `camera` plugin path;
4. keeps the selected Film preset for the matrix fallback preview and Editor handoff.

## Tests added/updated

`test/state/native_gpu_preview_bridge_test.dart`

The protocol mismatch test now reflects the G0.3 policy design: parsing preserves the incompatible protocol number and `GpuPreviewCapabilityPolicy` decides fallback instead of `NativeGpuProbe.fromMap()` throwing early.

`test/state/android_gpu_camera_bridge_test.dart`

Covers the G1 control-plane contract for:

- camera permission
- available lens identifiers
- clean capture path return value
- camera switching

Native Camera2/OES rendering still requires Android compilation and a physical-device test.

## Validation required before calling G1 complete

Host checks:

```bash
flutter analyze
flutter test test/state
flutter test test/ui --exclude-tags=golden
make gpu-lut-verify
```

Android build/device checks:

```bash
flutter build apk --debug
make gpu-native-test DEVICE=RF8Y909V0LV
flutter run -d RF8Y909V0LV
```

Manual device validation:

1. Open Film Camera and confirm the label shows `GPU FILM PREVIEW`.
2. Confirm Original is visually unfiltered.
3. Select each Film Profile and verify the live look changes without reopening the camera.
4. Drag Film strength continuously and verify interaction stays responsive.
5. Capture a photo and verify Editor receives a clean source plus the selected Film state.
6. Switch rear/front camera and verify orientation/mirroring.
7. Background/foreground the app and verify preview recovers.
8. Enter Editor, return to Camera and verify preview recovers.
9. Force or simulate renderer failure and verify automatic matrix fallback.
10. Measure sustained preview frame rate; G1 target is >= 30 fps on the reference Android device.

## Current G1 status

Implemented in code:

- native Camera2 ownership
- renderer-owned external OES input texture
- EGL output into Android TextureView PlatformView
- canonical 33^3 Film LUT shader path
- Film profile changes
- strength state updates
- clean JPEG capture path
- front/rear switching
- pause/resume/destroy lifecycle
- runtime failure fallback signaling
- Android CAMERA permission flow

Still pending physical-device proof:

- Android/Kotlin compilation on the project toolchain
- first live OES frame on the reference device
- exact portrait/front/rear orientation and crop
- >= 30 fps measurement
- capture orientation verification
- context-loss/recreation stress testing
- end-to-end visual comparison against Rust final output under the documented color-space contract

Do not remove the matrix fallback until these device validations are complete.
