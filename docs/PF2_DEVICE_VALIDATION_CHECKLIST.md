# PF2 Physical-Device Validation Checklist

## Purpose

Physical-device close gate for **PF2 Unified Camera Film / Filter / Adjust** on PR #48.

Final status as of 2026-08-17:

```text
Android physical gate: PASS
  Samsung SM A165F / RF8Y909V0LV

iOS physical gate: PASS
  iPhone 11 / 00008030-0004694C3E68C02E
```

Canonical evidence:

```text
docs/PF2_DEVICE_EVIDENCE_ANDROID_SM_A165F.md
docs/PF2_DEVICE_EVIDENCE_IOS_IPHONE_11.md
```

Rust remains authoritative for final pixels. Metal/OpenGL ES remain preview-only.

---

# 1. Validated camera pipeline

```text
camera frame
 -> Adjust
 -> Film
 -> Creative Filter
 -> display
```

Validated realtime Adjust scope:

```text
Exposure
Temperature
Tint
Brightness
Contrast
Saturation
Vignette
```

Validated camera-device controls:

```text
Flash: Off / Auto / On
Torch: Off / On
Mirror: user-controlled, default OFF
Switch Camera: rear / front
```

---

# 2. Physical-device checklist

The following required PF2 areas were reported PASS on both Android and iOS physical hardware:

- [x] App launches into Camera successfully on phone.
- [x] Native GPU camera preview activates.
- [x] Preview orientation is correct.
- [x] Rear camera preview works.
- [x] Front camera preview works.
- [x] Front/rear switching works repeatedly.
- [x] Gallery, Shutter, and Controls remain usable.
- [x] Film selection and strength work.
- [x] Creative Filters work.
- [x] Exposure works interactively.
- [x] Temperature works interactively.
- [x] Tint works interactively.
- [x] Brightness works interactively.
- [x] Contrast works interactively.
- [x] Saturation works interactively.
- [x] Vignette works interactively.
- [x] Film + Filter + Adjust coexist without state loss.
- [x] Rapid switching does not resurrect stale Film/Filter state.
- [x] Slider final values do not roll back after release.
- [x] Sustained preview remains usable.
- [x] No unacceptable thermal/frame-pacing regression was reported.
- [x] Background/foreground lifecycle resumes coherently.
- [x] Shutter after an Adjust interaction uses the committed/latest look state.
- [x] Temporary PF2 capture -> editor handoff remains coherent.
- [x] Gallery-originated sources remain neutral and do not inherit Camera look.
- [x] Flash Off/Auto/On behavior works where hardware capability permits.
- [x] Torch behavior works where hardware capability permits.
- [x] Mirror control works and default is OFF.
- [x] Controls bottom sheet remains readable on dark Camera UI.
- [x] Camera controls remain usable in the validated mobile UI.
- [x] Regression smoke passed on both physical platforms.

---

# 3. Android-specific closure

Samsung SM A165F originally exposed two runtime issues during PF2 validation:

1. GLES program/OES texture creation happened before the EGL window surface/context was current.
2. GPU preview orientation was rotated by 90 degrees because preview orientation and JPEG orientation were not sufficiently separated.

Both were corrected and the final Android physical run passed the native Camera2/OES path.

See:

```text
docs/PF2_DEVICE_EVIDENCE_ANDROID_SM_A165F.md
```

---

# 4. iOS-specific closure

iPhone 11 physical validation passed the AVFoundation + Metal camera-preview path after the final PF2 controls and expanded Adjust set were present.

See:

```text
docs/PF2_DEVICE_EVIDENCE_IOS_IPHONE_11.md
```

---

# 5. Runtime fail-closed contract

Expected fallback remains:

```text
native runtime failure
 -> detach CameraLookPreviewCoordinator
 -> destroy failed native renderer
 -> fall back to Flutter camera path
 -> visible look reduces to Film-only
 -> Filter/Adjust controls are hidden/unavailable
```

The physical close gate does not require destructive fault injection when it cannot be safely induced. Automated failure-path coverage remains the authority for explicitly forced failure cases.

---

# 6. PF2 close criteria

- [x] Historical implementation CI baseline is green (`b4451dce...`, CI #420 / run `31946914217`).
- [x] Historical Flutter/Rust/GPU/package/build gates passed on that implementation baseline.
- [x] Android required physical-device checklist passes.
- [x] iOS required physical-device checklist passes.
- [x] Sustained-preview/frame-pacing result is acceptable on physical devices.
- [x] Android device evidence is recorded.
- [x] iOS device evidence is recorded.
- [ ] Current post-device-evidence PR head receives exact-head automated CI and is green.
- [ ] `PROJECT_HANDOFF.md`, `CODE_WALKTHROUGH.md`, `PF2_CAMERA_LOOK_CONTRACT.md`, and `README.md` are synchronized to the final PF2 state.
- [ ] PR #48 is changed from Draft to Ready after the exact-head automated gate is green.

After merge:

- [ ] verify resulting `main` CI;
- [ ] update final PF2 status to merged/verified;
- [ ] remove `feature/pf2-unified-camera-look` when no longer needed;
- [ ] proceed to PF3 from the verified merged baseline.
