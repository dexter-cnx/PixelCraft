# PF2 Android Device Evidence — Samsung SM A165F

Status: **ACTIVE INVESTIGATION / PF2 ANDROID GATE NOT YET PASSED**

Date: 2026-08-17

## Device

```text
platform: Android
device: Samsung SM A165F
adb serial: RF8Y909V0LV
build mode observed: debug
exact tested commit: NOT RECORDED — record on the next validation run
```

## Observed Camera behavior

The application launches and the Flutter camera fallback can open the rear Camera2 device successfully.

Observed device log evidence includes:

```text
CameraService::connect ... camera ID 0 ... API version 2
CameraCaptureSession onConfigured
preview stream: 1280 x 720 IMPLEMENTATION_DEFINED
JPEG stream: 1280 x 720
repeating request starts successfully
```

Result:

```text
Android Camera2 framework / HAL: PASS
Flutter camera fallback: PASS
PF2 native Camera2/OES activation: FAIL / root cause under investigation
```

The PF2 UI therefore reports that Filter and Adjust require the native GPU camera preview. This is expected fail-closed behavior once the application has fallen back, but the fallback itself is not the intended PF2 success path.

## Native GPU LUT harness

Command:

```bash
make gpu-native-test DEVICE=RF8Y909V0LV
```

Result:

```text
native GPU identity LUT reference harness: PASS
native GPU Film Profile Pack v2 LUT harness: PASS
All tests passed
```

Measured parity evidence:

```text
androidOpenGl identity  maxError=0.0019607843137254832
provia_inspired         maxError=0.002587138484078433
velvia_inspired         maxError=0.001898172972549017
astia_inspired          maxError=0.0022858335429019327
e100_inspired           maxError=0.0027846084767372548
ektar_inspired          maxError=0.003337962745098011
chrome64_inspired       maxError=0.0026495893291921813
```

Interpretation:

- physical-device OpenGL/LUT execution is working;
- canonical Film LUT parity is working on this device;
- the current PF2 failure is narrower than generic Android GPU/LUT incompatibility;
- investigation should focus on native camera activation/session/surface/OES setup and its control-plane handoff.

## Film control interaction finding

During fallback testing, Film preset interaction was reported as not selectable/usable.

Inspection found a UI hit-test overlap:

```text
PF2 look panel bottom offset: 156
CameraPrimaryControls previous top padding: 42
```

The primary controls widget was tall enough to overlap the Film/Filter/Adjust ChoiceChip region and was later in the Stack, allowing it to intercept pointer events.

Fix applied after this finding:

```text
CameraPrimaryControls top padding: 42 -> 0
```

This keeps the primary control strip below the look-panel controls while preserving the Film-only fallback behavior.

The next physical run must revalidate Film selection before marking this item PASS.

## Added diagnostics for the next run

Debug-only bridge diagnostics now emit these prefixes:

```text
[PF2][NativeGpu]
[PF2][NativeCamera]
```

The next run should identify the failing activation stage among:

```text
probe
requestCameraPermission
availableLenses
createRenderer
setEnabled
configureSurface / native camera runtime
runtimeFailure
```

Recommended log command:

```bash
adb -s RF8Y909V0LV logcat -c
flutter run -d RF8Y909V0LV
```

In another terminal:

```bash
adb -s RF8Y909V0LV logcat | grep -E "PF2|NativeGpu|NativeCamera|runtimeFailure|EGL|GLES|Camera2|Camera"
```

## Kotlin Gradle Plugin warning

The device test build also reported Flutter's migration warning for plugins that still apply the Kotlin Gradle Plugin explicitly:

```text
dxtr_pixs_gpu
share_plus
```

This warning did not block the current build or GPU harness and is not treated as the PF2 native-camera root cause. `dxtr_pixs_gpu` should migrate to Flutter Built-in Kotlin in a separate compatibility/tooling task rather than mixing that migration into this physical-device bug fix unless evidence proves otherwise.

## Current PF2 Android status

```text
Camera2 framework/HAL:               PASS
Flutter camera fallback:             PASS
Native OpenGL/LUT harness:           PASS
Film Profile Pack v2 parity:         PASS
Native Camera2/OES activation:       FAIL / INVESTIGATING
Fallback Film interaction:           FIX APPLIED / RETEST REQUIRED
Filter:                              BLOCKED while native GPU inactive
Adjust:                              BLOCKED while native GPU inactive
Sustained PF2 native preview:         NOT RUN
Lens/lifecycle native PF2 checks:     NOT RUN
Capture/editor combined look:         NOT RUN
Overall PF2 Android gate:             FAIL / NOT READY
```

PR #48 must remain Draft until the native camera path activates successfully and the full physical-device checklist passes.
