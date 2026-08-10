# PixelCraft — G1 iOS Metal Verification

Date: 2026-08-10
Branch: `feature/camera-film-preview`
Reference device: iPhone 11 / Apple A13 GPU

## Status

G1 iOS AVFoundation + Metal Camera Film Preview has passed physical-device functional validation and the measured verification work completed in G1V.1–G1V.3.

Rust remains authoritative for final/full-resolution rendering. Native GPU preview is interactive/low-latency and must not be treated as the final-render source of truth.

## Functional device validation

Validated on physical iPhone:

- native `iosMetal` preview starts successfully
- Original preview is live and stable
- all six Film Profiles update live
- strength changes remain live
- front/rear switching works
- mirror/orientation/crop behavior is correct in the tested device flow
- capture remains clean via `AVCapturePhotoOutput`
- Film state transfers to Editor
- lifecycle/route recreation works
- preview no longer stalls on the first frame

## G1V.1 — Metal LUT numeric parity

The iOS native harness uses the same Rust-generated canonical parity fixture as Android and samples the canonical 33^3 `MTLTexture3D` using the documented texel-center mapping:

```text
grid = clamp(source, 0..1) * 32
lutUv = (grid + 0.5) / 33
```

Tolerance contract:

```text
max channel error <= 2 / 255
```

The in-app GPU Diagnostics path is used on Personal Team devices to avoid the integration-test runner replacing the installed app/provisioning state.

## G1V.2 — Performance and pipeline health

### Velvia 100% Film workload

60-second physical-device result:

```text
Workload        Velvia 100%
Display FPS     58.44
Display avg     17.11 ms
Display p95     16.89 ms
Display p99     34.35 ms
Display max     366.42 ms
> 40 ms         29 frames
Draw callbacks  3507
```

User-visible G1 target:

```text
Display FPS >= 30       PASS
Display p95 <= 40 ms    PASS
```

### AVCapture pipeline

```text
Capture FPS        29.81
Capture avg        33.54 ms
Capture p95        35.71 ms
Captured frames    1796
Overwritten        10
AVFoundation drop  11
Capture loss       1.17%
```

### Metal completion

```text
Unique Metal FPS     29.64
Unique frames        1785
Command completions  3507
Completion avg       1.12 ms
Completion p95       1.31 ms
Completion p99       1.48 ms
Completion max       2.20 ms
Elapsed              60.2 s
```

Pipeline-health target:

```text
Capture FPS >= 24             PASS
Unique Metal FPS >= 24        PASS
Capture loss <= 2%            PASS
Metal completion p95 <= 16ms  PASS
```

The measured relationship is expected:

```text
Camera unique frames  ~30 FPS
Metal unique frames   ~30 FPS
MTKView display loop  ~60 FPS
```

The display loop can present the latest camera frame more than once between unique camera deliveries; this is not evidence that the camera itself is producing 60 unique FPS.

## G1V.3 — Camera preview vs Rust final color characterization

The diagnostic does not send live frame buffers through Dart. Native code samples only center-square ROI RGB statistics from the latest `32BGRA` camera frame. A separate clean JPEG is captured with `AVCapturePhotoOutput` and processed by Rust.

Measured source-path values:

```text
Native source      R 0.3782  G 0.3942  B 0.3914
Rust clean JPEG    R 0.3772  G 0.3992  B 0.4028
Source |Delta|     R 0.0010  G 0.0050  B 0.0113
Source max Delta   0.0113
```

Measured Velvia path values:

```text
Native Film estimate  R 0.3288  G 0.3590  B 0.3611
Rust Velvia           R 0.3238  G 0.3642  B 0.3732
Film |Delta|          R 0.0050  G 0.0053  B 0.0121
Film max Delta        0.0121
```

Native ROI samples:

```text
4624
ROI = centerSquare
Native format = 32BGRA
```

Interpretation:

- source-path maximum mean-channel deviation is about 0.0113 (~2.9/255)
- Velvia-path maximum mean-channel deviation is about 0.0121 (~3.1/255)
- the deviations are small and of similar magnitude before and after Film application
- the remaining difference is consistent with the fact that `AVCaptureVideoDataOutput` and `AVCapturePhotoOutput` are different camera/ISP paths and are not sampled at exactly the same instant
- this is a color-path characterization, not a pixel-perfect parity assertion

The canonical LUT sampler itself is verified separately by G1V.1. Therefore this characterization should not be used to redefine Film semantics or to make the Metal preview authoritative.

## G1 iOS conclusion

For the reference iPhone 11 / Apple A13 GPU, the iOS G1 Camera GPU Preview is considered verified for the current G1 scope:

```text
Functional physical-device validation   PASS
Metal LUT numeric parity                PASS
Display frame pacing                    PASS
Camera/Metal pipeline health            PASS
Color-path characterization             RECORDED / ACCEPTABLE
Clean capture contract                  PASS
Rust authoritative final rendering      PRESERVED
```

Known boundary:

The preview and still-photo paths are intentionally not claimed to be pixel-identical. Camera ISP conversion, still-photo processing, timing, transfer functions and display color management can introduce small differences. Rust final rendering remains authoritative.
