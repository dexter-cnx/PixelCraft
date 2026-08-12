# G6 Physical Device Completion Checklist

Use this checklist only for observations actually performed on named physical hardware. Do not infer a PASS from host/CI results.

## Evidence header

- Device: iPhone 11
- OS: iOS 26.6
- SoC / GPU: A13 / Apple GPU
- Commit: `6c63e60d9e9776bc4f10fc7273b17d35c7c19a6f` automated evidence head; manual checks completed on the G6 branch
- Build mode: device verification / physical product checks
- Date (UTC): 2026-08-12

## G6.3 Device matrix — product flow

User-confirmed physical checks completed successfully on iPhone 11.

- [x] Camera preview starts and stops repeatedly without crash.
- [x] Switch Film LUT/profile repeatedly; preview remains valid.
- [x] Capture remains clean (Film preview is not baked into captured source).
- [x] Open captured image in Editor.
- [x] Exercise representative G5 controls including Curve and HSL.
- [x] Apply / Discard behaves coherently.
- [x] Undo / Redo remains coherent.
- [x] Transform operations remain coherent.
- [x] Film Profile create/edit/duplicate/load/import/export works.
- [x] Background -> foreground while Camera is open recovers correctly.
- [x] Background -> foreground while Editor is open recovers correctly.
- [x] Camera preview/renderer can be disposed and recreated repeatedly.
- [x] Export JPEG/PNG/WebP succeeds where supported by product UI.
- [x] Gallery save succeeds when permission is granted.
- [x] Share flow opens correctly.
- [x] Reopen app/session and verify coherent state/recovery.

## G6.5 Physical failure cases

Expected architecture rule: native/GPU failure must fail closed to a valid Rust/product state. Never change image semantics merely to make a failure test pass.

User-confirmed manual physical failure/lifecycle checks are complete for the available iPhone 11 test environment.

- [x] Camera permission denied: explicit product failure state; no crash.
- [x] Photos/gallery permission denied: save failure surfaced; editor/session remains valid.
- [x] Background app during processing: coherent resume or explicit clean failure.
- [x] Interrupt export/share flow: session remains valid after returning.
- [x] Missing/unavailable camera device path where reproducible: no crash; clear failure state.
- [x] Renderer recreation after background/foreground: valid preview or Rust fallback.
- [x] Native renderer init/runtime failure injection, where available in the debug harness: Rust fallback remains valid.
- [x] Missing/corrupt LUT injection, where available in the debug harness: GPU Film path becomes unavailable/fails closed; committed Rust state remains valid.
- [x] Missing recovery source: reject recovery/open without corrupting current valid state.
- [x] Invalid/corrupt imported Film Profile: explicit rejection; no partially applied profile.

## Thermal/manual observation

- [x] 15-minute sustained workload completed on iPhone 11 / iOS 26.6.
- Device heat: not warm
- UI responsiveness: normal
- Unexpected restart/termination: no
- Notes: 15:03 automated sustained workload completed 420 cycles; user observed no heat and no perceived lag.

## Automated closure evidence

The remaining automated validation completed successfully on commit `6c63e60d9e9776bc4f10fc7273b17d35c7c19a6f`.

- [x] G6.0 host baseline PASS.
- [x] G6.1 configured image-size characterization through `G6_MAX_MP=48` PASS.
- [x] G6.5 deterministic host failure injection PASS.
- [x] Consolidated physical-device smoke PASS on iPhone 11 verifier app.
- [x] PixelCraft main app was not uninstalled or overwritten.
- [x] Main Xcode checkout was not mutated; isolated worktree was removed after the run.
- [x] GitHub CI run #136 PASS on the code head.

Automated evidence root from the physical run:

`build/g6/final/`

Device metrics from the final smoke run:

`build/g6/device/20260812T062943Z-00008030-0004694C3E68C02E-metrics.txt`

## Result

- G6.3 device result: **PASS on available iPhone 11 physical hardware**
- G6.5 physical result: **PASS for completed/reproducible physical checks**
- Thermal/manual result: **PASS — not warm, normal responsiveness, no unexpected termination**
- Additional device diversity not represented by this checklist remains a hardware-availability limitation, not an inferred result.
