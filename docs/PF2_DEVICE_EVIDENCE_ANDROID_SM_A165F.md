# PF2 Android Device Evidence — Samsung SM A165F

Status: **PASS — PF2 ANDROID PHYSICAL GATE COMPLETE**

Date: 2026-08-17

## Device

```text
platform: Android
device: Samsung SM A165F
adb serial: RF8Y909V0LV
build mode: debug/profile physical-device validation
branch: feature/pf2-unified-camera-look
```

The final user-reported Android validation was performed after the PF2 camera-control and expanded Adjust work landed on the active branch. The exact installed device SHA was not independently captured from the device, so repository history remains the source of truth for the branch head used to reproduce the run.

## Final physical result

```text
Camera2 framework/HAL:               PASS
Native Camera2/OES activation:       PASS
Native OpenGL/LUT harness:           PASS
Film Profile Pack v2 parity:         PASS
Preview orientation:                 PASS
Rear camera preview:                 PASS
Front camera preview:                PASS
Front/rear switching:                PASS
Film:                                PASS
Creative Filter:                     PASS
Adjust:                              PASS
Film + Filter + Adjust together:     PASS
Expanded Adjust controls:            PASS
Flash controls:                      PASS
Torch controls:                      PASS
Mirror control/default behavior:     PASS
Controls bottom sheet readability:   PASS
Rapid interaction / stale state:     PASS
Lens/session switching:              PASS
Lifecycle handling:                  PASS
Sustained physical use:              PASS
Capture/editor handoff:              PASS
Gallery neutrality/regression smoke: PASS
Overall PF2 Android gate:            PASS
```

Expanded Camera Adjust scope validated on device:

```text
Exposure
Temperature
Tint
Brightness
Contrast
Saturation
Vignette
```

## Android native-camera activation root cause and fix

The original PF2 Android physical failure was not a Camera2 or LUT compatibility failure. Diagnostics showed:

```text
probe                  PASS
camera permission      PASS
available lenses       PASS
createRenderer         PASS
setEnabled             PASS
configure GPU surface  FAIL: shader compile
```

The Camera2/OES renderer created GLES shader/program objects before an EGL window surface existed and before the EGL context was current.

The corrected lifecycle is:

```text
eglGetDisplay
 -> eglInitialize
 -> eglChooseConfig
 -> eglCreateContext
 -> eglCreateWindowSurface
 -> eglMakeCurrent
 -> initialize GL program/OES texture
 -> Camera2 session
```

After that fix the physical native GPU camera path activated and Film / Filter / Adjust became available and usable.

## Preview-orientation fix

A separate physical-device issue rotated the GPU preview by 90 degrees. The final preview path separates display-preview orientation from JPEG capture orientation so the Camera2/OES preview is not rotated a second time while JPEG orientation remains independently correct.

## GPU/LUT parity evidence

Earlier physical harness run on the same device passed:

```text
androidOpenGl identity  maxError=0.0019607843137254832
provia_inspired         maxError=0.002587138484078433
velvia_inspired         maxError=0.001898172972549017
astia_inspired          maxError=0.0022858335429019327
e100_inspired           maxError=0.0027846084767372548
ektar_inspired          maxError=0.003337962745098011
chrome64_inspired       maxError=0.0026495893291921813
```

Result:

```text
native GPU identity LUT reference harness: PASS
native GPU Film Profile Pack v2 LUT harness: PASS
```

## Remaining non-PF2 tooling note

Flutter reported the Built-in Kotlin migration warning for plugins including `dxtr_pixs_gpu` and `share_plus`. This did not block PF2 physical validation and remains separate tooling/compatibility debt.

## Closure

Android physical-device validation no longer blocks PF2. PR #48 may use this document as the Android device evidence record. Exact-head automated CI remains a separate merge gate.
