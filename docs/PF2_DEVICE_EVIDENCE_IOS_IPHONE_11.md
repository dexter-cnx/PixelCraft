# PF2 iOS Device Evidence — iPhone 11

Status: **PASS — PF2 iOS PHYSICAL GATE COMPLETE**

Date: 2026-08-17

## Device

```text
platform: iOS
device: iPhone 11
UDID: 00008030-0004694C3E68C02E
branch: feature/pf2-unified-camera-look
```

The final user-reported iPhone validation was performed after the PF2 unified Camera Film / Filter / Adjust implementation, camera controls, preview-orientation fixes, and expanded Adjust controls landed on the active branch. The exact installed device SHA was not independently captured from the device, so repository history remains the source of truth for reproducing the validated branch state.

## Final physical result

```text
Native AVFoundation camera activation: PASS
Metal GPU preview:                  PASS
Preview orientation:                PASS
Rear camera preview:                PASS
Front camera preview:               PASS
Front/rear switching:               PASS
Film:                               PASS
Creative Filter:                    PASS
Adjust:                             PASS
Film + Filter + Adjust together:    PASS
Expanded Adjust controls:           PASS
Flash controls:                     PASS
Torch controls:                     PASS
Mirror control/default behavior:    PASS
Rapid interaction / stale state:    PASS
Lens/session switching:             PASS
Lifecycle handling:                 PASS
Sustained physical use:             PASS
Capture/editor handoff:             PASS
Gallery neutrality/regression smoke: PASS
Overall PF2 iOS gate:               PASS
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

## Architecture validated

The iOS physical run validates the intended PF2 native preview path:

```text
AVFoundation camera frame
 -> Adjust
 -> Film
 -> Creative Filter
 -> Metal display preview
```

Camera buffers remain native and do not cross MethodChannel. Rust remains authoritative for final pixels; Metal remains preview-only.

## Camera controls validated

The camera-first UI includes:

```text
Flash: Off / Auto / On
Torch: Off / On
Mirror: user-controlled, default OFF
Switch Camera: rear / front
```

The top-bar Flash control and Controls bottom sheet share the same camera-device state.

## Closure

iOS physical-device validation no longer blocks PF2. PR #48 may use this document as the iOS device evidence record. Exact-head automated CI remains a separate merge gate.
