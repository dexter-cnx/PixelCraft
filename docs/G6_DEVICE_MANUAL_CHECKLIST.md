# G6 Physical Device Completion Checklist

Use this checklist only for observations actually performed on named physical hardware. Do not infer a PASS from host/CI results.

## Evidence header

- Device: ____________________
- OS: ____________________
- SoC / GPU: ____________________
- RAM: ____________________
- Commit: ____________________
- Build mode: profile / release
- Date (UTC): ____________________

## G6.3 Device matrix — product flow

Mark each item PASS / FAIL / N/A and attach a short note when behavior differs from expected.

- [ ] Camera preview starts and stops repeatedly without crash.
- [ ] Switch Film LUT/profile repeatedly; preview remains valid.
- [ ] Capture remains clean (Film preview is not baked into captured source).
- [ ] Open captured image in Editor.
- [ ] Exercise representative G5 controls including Curve and HSL.
- [ ] Apply / Discard behaves coherently.
- [ ] Undo / Redo remains coherent.
- [ ] Transform operations remain coherent.
- [ ] Film Profile create/edit/duplicate/load/import/export works.
- [ ] Background -> foreground while Camera is open recovers correctly.
- [ ] Background -> foreground while Editor is open recovers correctly.
- [ ] Camera preview/renderer can be disposed and recreated repeatedly.
- [ ] Export JPEG/PNG/WebP succeeds where supported by product UI.
- [ ] Gallery save succeeds when permission is granted.
- [ ] Share flow opens correctly.
- [ ] Reopen app/session and verify coherent state/recovery.

## G6.5 Physical failure cases

Expected architecture rule: native/GPU failure must fail closed to a valid Rust/product state. Never change image semantics merely to make a failure test pass.

- [ ] Camera permission denied: explicit product failure state; no crash.
- [ ] Photos/gallery permission denied: save failure surfaced; editor/session remains valid.
- [ ] Background app during processing: coherent resume or explicit clean failure.
- [ ] Interrupt export/share flow: session remains valid after returning.
- [ ] Missing/unavailable camera device path where reproducible: no crash; clear failure state.
- [ ] Renderer recreation after background/foreground: valid preview or Rust fallback.
- [ ] Native renderer init/runtime failure injection, when available in debug harness: Rust fallback remains valid.
- [ ] Missing/corrupt LUT injection, when available in debug harness: GPU Film path becomes unavailable/fails closed; committed Rust state remains valid.
- [ ] Missing recovery source: reject recovery/open without corrupting current valid state.
- [ ] Invalid/corrupt imported Film Profile: explicit rejection; no partially applied profile.

## Thermal/manual observation

- [ ] 15-minute sustained workload completed.
- Device heat: not warm / warm / hot but comfortable / very hot
- UI responsiveness: normal / minor slowdown / obvious slowdown
- Unexpected restart/termination: yes / no
- Notes: ____________________

## Result

- G6.3 device result: PASS / FAIL / LIMITED
- G6.5 physical result: PASS / FAIL / LIMITED
- Evidence/log paths: ____________________
- Known hardware limitations / unavailable scenarios: ____________________
