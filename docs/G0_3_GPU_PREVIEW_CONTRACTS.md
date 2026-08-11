# G0.3 — GPU Preview Capability, Lifecycle and Color Contracts

Status: implemented foundation; Camera frames are **not connected yet**
Branch: `feature/camera-film-preview`

G0.3 makes the native GPU preview path safe to select and safe to manage before G1 connects live Camera frames.

## 1. Capability and fallback policy

The Dart policy is defined in:

```text
lib/gpu/gpu_preview_capability.dart
```

A native GPU backend is eligible only when all of the following are true:

```text
protocol compatible
AND backend available
AND generated LUT assets available
AND shader self-test passed
AND LUT33 supported
AND device/GPU not blacklisted
```

Distinct fallback reasons are preserved for:

- protocol mismatch
- backend unavailable
- LUT33 unsupported
- shader self-test failure
- generated native LUT assets unavailable
- renderer initialization failure
- runtime render failure
- explicit device/GPU blacklist

Camera fallback remains the existing matrix approximation until G1 is stable.
Fallback is preview-only. It must never bake preview pixels into the captured source image.

## 2. Capability probe behavior

Android production probing is implemented in:

```text
android/app/src/main/kotlin/dev/pixelcraft/pixelcraft/GpuCapabilityProbe.kt
```

Normal startup behavior:

1. Build an identity from app version + Android build fingerprint + SDK level.
2. Return a cached capability result when the identity matches.
3. If no valid cache exists, execute the EGL/shader self-test on the dedicated GPU executor.
4. Verify the generated GPU LUT assets are packaged before declaring the backend eligible.
5. Cache the result.

A forced self-test is still available for diagnostics/tests.

Renderer initialization failure invalidates the capability cache so a previously good capability result is not trusted indefinitely after runtime initialization becomes unstable.

The explicit blacklist extension point is intentionally empty until there is evidence for a concrete device/GPU exclusion. Entries must be narrow and evidence-based.

## 3. Renderer lifecycle contract

Dart session contract:

```text
lib/gpu/gpu_preview_session.dart
lib/gpu/native_gpu_preview_bridge.dart
```

Native Android control-plane state:

```text
android/app/src/main/kotlin/dev/pixelcraft/pixelcraft/GpuPreviewRendererSession.kt
```

Protocol lifecycle:

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

The session identifier is opaque. Dart may pass only small state/control values.
Frame pixels are prohibited from MethodChannel messages.

Expected lifecycle:

```text
idle
  -> createRenderer
created
  -> configureSurface
surfaceConfigured
  -> pause
paused
  -> resume
surfaceConfigured
  -> destroyRenderer
destroyed
```

Surface recreation may call `configureSurface` again on the same renderer session.
Camera switching must not require re-parsing/re-uploading the Film LUT when the GPU context remains valid.

## 4. Android Camera OES boundary for G1

G0.3 defines the native-only interface in:

```text
android/app/src/main/kotlin/dev/pixelcraft/pixelcraft/GpuCameraOesRenderer.kt
```

Target G1 pipeline:

```text
Camera producer
  -> SurfaceTexture backed by GL_TEXTURE_EXTERNAL_OES
  -> OpenGL ES fragment shader
  -> canonical 33^3 Film LUT atlas
  -> native output Surface / Flutter texture or platform surface
```

The Camera producer and GPU renderer must connect natively.
Do not use Camera image-stream callbacks to move per-frame YUV/RGB/JPEG/PNG data through Dart.
Do not send live frames through Flutter Rust Bridge.

## 5. Color-space contract

The existing G0.2 parity harness proves LUT atlas addressing and interpolation. It does **not** prove Camera-to-export visual color parity.

The G1 renderer must follow this contract before Pixel Craft claims visual parity with Rust final rendering.

### 5.1 Canonical LUT domain

The canonical Film LUT is a 33^3 RGB transform over normalized values:

```text
R,G,B in [0, 1]
```

GPU atlas sampling must not silently insert a transfer-function conversion around the LUT. The values presented to the GPU LUT must represent the same RGB numeric domain presented to the authoritative Rust Film transform.

### 5.2 Camera source

Android Camera commonly produces YUV that the external-OES texture path converts to RGB through the platform/driver pipeline. The exact source primaries, range, transfer characteristics and conversion metadata can vary by device/camera path.

Therefore G1 must record/verify, for each selected Camera stream:

```text
source format
source color standard / primaries when exposed
source transfer characteristics when exposed
source range (full/limited) when exposed
orientation and crop transform
```

Unknown metadata must be treated as unknown rather than assumed to be proof of sRGB parity.

### 5.3 GPU shader input assumption

The Film LUT shader receives normalized RGB sampled from the Camera external-OES texture.

Before the LUT is applied, G1 must ensure those RGB values are in the same effective transfer/domain used by Rust for Film evaluation. If Camera/OES delivery is not already in that domain, conversion belongs in the native shader pipeline and must be explicit/versioned.

No implicit linearization or gamma encoding should be added merely because the renderer is GPU-based.

### 5.4 Preview output

The initial G1 output target is SDR display preview.

Until a wider-gamut/HDR contract is implemented, preview output should be treated as an SDR display path and should avoid silently promoting the Film LUT to HDR/wide-gamut semantics.

If Android surface/color-space APIs negotiate a non-SDR output, the renderer must either:

- perform an explicit documented conversion, or
- mark that path unsupported and fall back.

### 5.5 Rust final rendering

Rust remains authoritative for export/full-resolution rendering.

Before visual parity is signed off, add fixtures that compare representative decoded source pixels/images through:

```text
Rust decode -> Rust Film transform -> export color encoding
```

against:

```text
Camera/OES-equivalent RGB input -> GPU Film LUT -> preview output conversion
```

The comparison must include the transfer/color conversions surrounding the LUT, not only the LUT sampler.

### 5.6 Export color space

G0.3 does not change export behavior.

Export remains on the current Rust path. Any future explicit output profile/ICC/wide-gamut work must be versioned separately from GPU preview selection so preview capability cannot change final rendered source pixels.

## 6. Failure handling requirements

Production Camera selection should use this sequence:

```text
probe capability
  -> policy decision
      -> fallback if ineligible
      -> create renderer if eligible
          -> invalidate capability cache + fallback if init fails
          -> configure native surface
              -> fallback if render/session fails
```

A runtime fallback must:

- preserve the current Film Profile selection and strength
- keep the clean Camera source/capture path unchanged
- release or destroy stale native GPU resources
- return to the matrix approximation without crashing navigation/camera lifecycle

## 7. G0.3 boundary

G0.3 intentionally stops before:

- attaching Camera frames to the OES renderer
- replacing `CameraPreview`
- creating a production GL render loop
- measuring Camera preview FPS
- claiming full visual color parity

Those are G1 tasks.
