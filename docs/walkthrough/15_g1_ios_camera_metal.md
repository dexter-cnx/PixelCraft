# G1 iOS Camera GPU Preview — AVFoundation + Metal Walkthrough

สถานะ: **implemented in code; awaiting Xcode + physical-device validation**

เอกสารนี้อธิบาย G1 iOS peer ของ Camera Film Preview ซึ่งใช้ protocol และ semantic contract เดียวกับ Android G1 โดยยังรักษากฎสำคัญของ PixelCraft:

- Dart เป็น control plane เท่านั้น
- camera frame ไม่ข้าม MethodChannel หรือ Flutter Rust Bridge
- Film Profile definition มาจาก canonical Rust source
- preview effect ไม่ถูก bake ลง source photo
- Rust ยังคงเป็น authoritative renderer สำหรับ Editor/final export

---

## 1. Runtime architecture

Native iOS frame path:

```text
AVCaptureSession
  -> AVCaptureVideoDataOutput
  -> CVPixelBuffer (32 BGRA)
  -> CVMetalTextureCache
  -> MTLTexture2D
  -> Metal fragment shader
  -> canonical Film 33^3 MTLTexture3D
  -> MTKView drawable
  -> Flutter UiKitView
```

Dart ไม่รับ pixel buffer และไม่มี JPEG/PNG conversion ต่อ frame.

Still capture แยกจาก preview:

```text
AVCaptureSession
  -> AVCapturePhotoOutput
  -> clean JPEG data
  -> temporary .jpg file
  -> path crosses MethodChannel
  -> CameraFilmEditorHandoff
  -> Editor
  -> Rust authoritative Film LUT
```

ดังนั้น source ที่เข้า Editor ไม่ใช่ screenshot ของ `MTKView`.

---

## 2. Shared Dart control plane

### `lib/gpu/native_gpu_preview_bridge.dart`

ใช้ channel เดิม:

```text
dev.pixelcraft/gpu_preview_v1
```

Protocol version:

```text
1
```

Backend enum มี:

```text
fallback
androidOpenGl
iosMetal
```

Renderer control operations ยังคงเหมือน Android:

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

### `lib/gpu/native_gpu_camera_bridge.dart`

Camera-specific control plane ถูกย้ายให้เป็น cross-platform abstraction:

```text
requestCameraPermission
availableCameraLenses
capturePhoto
switchCamera
runtimeFailure
```

Payload ที่ผ่าน channel มีเพียง:

- protocol version
- renderer id
- front/back lens identifier
- permission boolean
- clean photo file path
- runtime error string

ไม่มี live frame payload.

### `lib/ui/screens/camera_film_preview_screen_g1.dart`

หน้ากล้องเดิมถูกใช้ร่วมกันทั้งสอง native backend.

Startup:

```text
CameraFilmPreviewScreen
  -> NativeGpuPreviewBridge.probe()
  -> GpuPreviewCapabilityPolicy.evaluate()

Android eligible
  -> androidOpenGl
  -> AndroidGpuCameraPreview

iOS eligible
  -> iosMetal
  -> IosGpuCameraPreview

not eligible / native failure
  -> Flutter camera plugin
  -> ColorFilter.matrix fallback
```

Film selection, strength state, shutter flow, Editor handoff และ lifecycle state อยู่ใน Dart state model ชุดเดียว ไม่ได้สร้าง iOS-specific effect model.

---

## 3. Flutter iOS PlatformView

### `lib/gpu/ios_gpu_camera_preview.dart`

ใช้:

```dart
UiKitView(
  viewType: 'dev.pixelcraft/gpu_camera_preview_v1',
  creationParams: {'rendererId': rendererId},
)
```

Flutter ส่งเพียง `rendererId` เข้า native view.

### `ios/Runner/MetalCameraPreviewPlatformView.swift`

Factory สร้าง `PixelCraftMetalView`, ซึ่ง subclass จาก `MTKView`.

Responsibilities:

- attach `MTKView` เข้ากับ renderer session
- update `drawableSize` ตาม view size / scale
- อ่าน `UIWindowScene.interfaceOrientation`
- ส่ง orientation state เข้า native renderer
- detach view เมื่อ PlatformView ถูก release

Flutter overlay เช่น top bar, Film chips, strength slider และ shutter ยังคงวาดเหนือ native PlatformView.

---

## 4. Native protocol registration

### `ios/Runner/AppDelegate.swift`

เมื่อ implicit Flutter engine พร้อม จะ register:

```text
GpuPreviewPlugin
```

กับ Flutter plugin registry.

### `ios/Runner/GpuPreviewChannel.swift`

`GpuPreviewPlugin` ทำหน้าที่:

- protocol v1 validation
- cached capability probe
- camera permission request
- available lens query
- renderer create/destroy
- Film/strength/enabled state controls
- pause/resume
- clean photo capture
- native camera switching
- native -> Dart runtime failure signal
- PlatformView factory registration

`MetalRendererRegistry` map `rendererId` ไปยัง `MetalCameraPreviewRenderer` หนึ่ง instance ต่อ renderer session.

---

## 5. Capability probe

### `ios/Runner/GpuCapabilityProbe.swift`

Probe ทำงานบน utility queue จาก `GpuPreviewPlugin`, ไม่ทำ shader/LUT setup หนักบน Flutter platform thread.

Probe ตรวจ:

```text
MTLCreateSystemDefaultDevice()
canonical Film assets exist
Metal shader library compiles
identity 33^3 texture can be allocated
canonical Film texture can be loaded
```

Success payload:

```text
backend = iosMetal
available = true
supportsLut33 = true
maxLutSize = 33
selfTestPassed = true
assetsLoaded = true
```

Capability cache identity รวม:

```text
cache schema
app version
app build
OS version
device model
```

`invalidateCapabilityCache` จะล้าง cache เมื่อ renderer/native runtime failure เกิดขึ้น.

หมายเหตุ: probe ปัจจุบันเป็น startup/self-test ของ Metal pipeline และ asset loading ไม่ใช่ full numeric Metal-vs-Rust parity harness. Device parity fixture ยังเป็น validation item ก่อนประกาศ cross-platform G1 complete.

---

## 6. Canonical Film LUT packaging

Canonical authoring path ยังเป็น:

```text
rust/film_profiles/*/look.json
  -> rust/build.rs
  -> canonical 33^3 lut.cube
  -> tool/generate_gpu_lut_atlas.py
  -> <profileId>.rgba8
```

Android ใช้ `.rgba8` เป็น tiled 2D atlas โดยตรง.

iOS ใช้ **generated bytes ชุดเดียวกัน** แต่ `MetalFilmLutLoader` แปลง layout เป็น native 3D texture:

```text
198 x 198 RGBA8 atlas
  -> unpack by B tile / G row / R column
  -> 33 x 33 x 33 RGBA8 volume
  -> MTLTextureType3D
```

ไม่มี iOS-specific Film look definition.

### Xcode build integration

`ios/Runner.xcodeproj/project.pbxproj` มี build phase:

```text
Generate Film LUT Assets
```

ซึ่งรัน:

```bash
make -C "$PROJECT_ROOT" gpu-luts \
  GPU_LUT_DIR="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/gpu_luts"
```

จึงสร้าง canonical generated LUT เข้า app bundle ระหว่าง iOS build โดยไม่ commit binary LUT artifacts เข้า repo.

---

## 7. Metal 3D LUT semantics

### `ios/Runner/MetalFilmLutLoader.swift`

สร้าง:

```text
textureType = MTLTextureType3D
pixelFormat = rgba8Unorm
width = 33
height = 33
depth = 33
filter = linear (shader sampler)
```

### Texel-center mapping

Metal normalized coordinates ต้อง map canonical LUT grid ไปที่ texel centers.

Shader ใช้:

```text
grid = clamp(source, 0..1) * 32
lutUv = (grid + 0.5) / 33
```

แล้วจึงใช้ hardware trilinear sampling.

เหตุผลคือ canonical LUT มี sample ที่ grid index `0...32`; การ sample ด้วย raw normalized color โดยตรงจะเหลื่อม interpolation ครึ่ง texel และไม่ตรงกับ Rust/Android semantics.

Numeric parity บน real Metal hardware ยังต้องถูกวัดกับ fixture เดียวกับ Rust ภายใต้ tolerance ที่กำหนด.

---

## 8. `MetalCameraPreviewRenderer`

### Camera session

Renderer owns:

- `AVCaptureSession`
- current `AVCaptureDeviceInput`
- `AVCaptureVideoDataOutput`
- `AVCapturePhotoOutput`
- selected front/back lens
- dedicated session queue
- dedicated render queue

Camera session ใช้ `.high` preset.

Video output ขอ:

```text
kCVPixelFormatType_32BGRA
```

และเปิด:

```text
alwaysDiscardsLateVideoFrames = true
```

เพื่อไม่สะสม frame queue เมื่อ renderer ช้ากว่า camera.

### CVPixelBuffer -> Metal

ต่อ frame:

```text
CMSampleBuffer
  -> CVPixelBuffer
  -> CVMetalTextureCacheCreateTextureFromImage
  -> MTLTexture2D(.bgra8Unorm)
```

ไม่มี CPU copy ของ full camera frame ไป Dart.

### Render pass

Renderer bind:

```text
texture(0) = camera frame
texture(1) = Film 3D LUT
buffer(0)  = crop / mirror / strength / enable uniforms
```

แล้ว render fullscreen triangle strip ไปยัง current `MTKView` drawable.

---

## 9. Film state updates

Film profile change:

```text
Dart setFilm(profileId, strength)
  -> native profile state
  -> render queue loads generated Film asset
  -> atlas unpacked into 33^3 Metal texture
```

Strength-only change:

```text
Dart setStrength(value)
  -> update Float state only
  -> next frame consumes strength uniform
```

ดังนั้น slider tick ไม่ parse/re-upload LUT.

Selecting Original:

```text
setEnabled(false)
```

Film texture สามารถคงอยู่ใน renderer แต่ shader mix amount เป็น 0.

---

## 10. Front camera mirror and orientation

AVFoundation connection ใช้ interface orientation สำหรับ video/photo orientation.

Native preview deliberately keeps AVFoundation mirroring disabled:

```text
connection.isVideoMirrored = false
```

แล้ว mirror เฉพาะ preview ใน Metal shader เมื่อ lens เป็น front:

```text
mirrorX = 1
```

เป้าหมายคือ:

- front preview มี behavior แบบ mirror ที่ผู้ใช้คุ้นเคย
- clean captured source ไม่ถูกบังคับ bake preview mirror transform

สิ่งนี้ต้อง validate บน physical iPhone ทั้ง portrait และ landscape.

Center-crop ถูกคำนวณจาก source texture aspect เทียบกับ `MTKView.drawableSize` และส่งเป็น `cropScale` uniform.

---

## 11. Clean photo capture

`capturePhoto()` ไม่อ่าน pixels จาก Metal surface.

Flow:

```text
AVCapturePhotoOutput.capturePhoto
  -> AVCapturePhoto.fileDataRepresentation()
  -> temporary/pixelcraft-camera/capture-<UUID>.jpg
  -> Dart receives path
```

จากนั้น shared Camera screen ส่ง:

```text
imagePath
profileId
strength
```

เข้า `CameraFilmEditorHandoff`.

Rust เป็นผู้ apply authoritative Film LUT ใน Editor/final render.

---

## 12. Lifecycle

App inactive/paused:

```text
CameraFilmPreviewScreen
  -> pause(rendererId)
  -> AVCaptureSession.stopRunning()
```

Resume:

```text
resume(rendererId)
  -> configure if needed
  -> session.startRunning()
```

Route disposal:

```text
destroyRenderer(rendererId)
  -> renderer removed from registry
  -> sample-buffer delegate detached
  -> capture session stopped
  -> texture cache flushed/released
```

PlatformView detach ไม่ destroy renderer โดยตัวมันเอง เพราะ renderer lifecycle เป็น control-plane responsibility ของ route/session.

---

## 13. Runtime fallback

Fatal native renderer failure:

```text
MetalCameraPreviewRenderer.fail()
  -> MetalRendererRegistry.runtimeFailure
  -> GpuPreviewPlugin.runtimeFailure
  -> MethodChannel native -> Dart
  -> CameraFilmPreviewScreen
  -> destroy native renderer
  -> invalidate cached capability
  -> initialize Flutter camera fallback
```

Fallback ยังคงเป็น:

```text
camera plugin + CameraPreview + ColorFilter.matrix
```

Capture ใน fallback ยังคง clean/non-destructive.

---

## 14. Tests added

### `test/state/native_gpu_camera_bridge_test.dart`

ครอบคลุม control-plane contract:

- permission request
- lens identifiers
- capture returns path only
- camera switching
- native runtime failure callback

Existing native GPU protocol/capability tests ยังคงใช้ร่วมกัน.

---

## 15. Validation commands

Host/shared checks:

```bash
flutter analyze
flutter test test/state
flutter test test/ui --exclude-tags=golden
make gpu-lut-verify
```

iOS build:

```bash
flutter build ios --debug
```

Physical iPhone:

```bash
flutter devices
flutter run -d <IPHONE_DEVICE_ID>
```

ตรวจใน Xcode build log ว่า phase นี้ผ่าน:

```text
Generate Film LUT Assets
```

และ app bundle มี:

```text
gpu_luts/
  provia_inspired.rgba8
  velvia_inspired.rgba8
  astia_inspired.rgba8
  e100_inspired.rgba8
  ektar_inspired.rgba8
  chrome64_inspired.rgba8
  manifest.json
```

---

## 16. Physical-device validation checklist

1. Probe returns `iosMetal` and UI shows `GPU FILM PREVIEW`.
2. Initial Original preview renders correctly.
3. Six Film Profiles update live.
4. Strength slider is smooth and does not recreate `AVCaptureSession`.
5. Strength-only updates do not reload the LUT.
6. Rear/front switching works while Film/strength remain unchanged.
7. Front preview mirror behavior is correct.
8. Rear preview is not mirrored.
9. Portrait orientation is correct.
10. Landscape left/right orientation is correct.
11. Center crop has no stretching.
12. Capture returns a clean JPEG, not Metal preview pixels.
13. Captured photo orientation/EXIF behavior is correct.
14. Film Profile + strength arrive in Editor unchanged.
15. Rust final render remains authoritative.
16. Editor -> Back -> Camera resumes safely.
17. Background -> foreground resumes safely.
18. Route exit/re-entry releases and recreates resources safely.
19. Forced/native renderer failure falls back to matrix preview.
20. Sustained preview reaches at least 30 fps.
21. Metal 3D LUT numeric parity matches Rust within the documented tolerance.
22. SDR/color-space assumptions are checked against captured Rust decode before claiming visual parity.

---

## 17. Current limitations before G1 exit

The code path exists, but the following are not yet proven in this chat/environment:

- successful Xcode/Swift compilation on the project Mac toolchain
- first live Metal camera frame on a physical iPhone
- physical-device orientation/mirroring/crop correctness
- capture metadata/orientation correctness
- sustained >=30 fps
- route/lifecycle stress stability
- numeric Metal-vs-Rust LUT parity harness on device
- end-to-end camera-preview vs Rust final color-space parity

Until those checks pass, `GpuPreviewCapabilityPolicy` + Flutter camera/matrix fallback remains the production safety path.
