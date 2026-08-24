# PF9 — Native Preview Suspension During Capture Handoff

Status: **IMPLEMENTATION STARTED**

Branch: `feature/pf9-pause-preview-during-capture-handoff`

## Problem

PF7 hides the live Camera behind a frozen captured still while authoritative Rust processing and Gallery delivery run. On the native GPU camera path, the underlying Metal/OpenGL preview renderer can still continue running during that handoff even though it is not visible.

That is functionally correct but wastes camera/GPU work and creates an avoidable lifecycle race if the app backgrounds and resumes while the frozen handoff is still active.

## Scope

PF9 will suspend only the native GPU preview around the capture handoff.

```text
capture clean JPEG
  ↓
mark capture handoff active
  ↓
pause native preview renderer
  ↓
push CameraCaptureSaveHandoff
  ↓
PF7/PF8 processing / Retry / Back semantics unchanged
  ↓
handoff route completes
  ↓
if app lifecycle is resumed and renderer is still current
    resume native preview
else
    leave renderer paused until normal lifecycle resume policy permits it
```

## Lifecycle rules

1. `processing` / `saving` presentation remains owned by `CameraCaptureSaveHandoff`.
2. Native renderer pause is best-effort and must not make an already-captured shutter transaction fail.
3. If the app enters inactive/paused while the handoff is active, normal lifecycle pause remains valid and idempotent.
4. If the app resumes while the handoff is still active, the camera screen must not resume the native renderer yet.
5. When the handoff ends, resume only if:
   - the screen is still mounted;
   - the same renderer id is still current;
   - native GPU mode is still active;
   - app lifecycle is `resumed`.
6. Resume failure uses the existing native runtime-failure/fallback policy instead of leaving the camera in a silent invalid state.
7. Flutter `camera` fallback behavior remains unchanged; that path already detaches/disposes the controller before the save handoff and reinitializes afterwards.

## Non-goals

PF9 does not change:

- authoritative clean JPEG source semantics;
- Rust render/export authority;
- PF7 frozen-still UX;
- PF8 failed-source cleanup;
- Metal/OpenGL rendering architecture;
- RAW, MobileSAM/ONNX, external-edit transport, or generic plugin runtime.

## Validation

Automated validation should cover the lifecycle policy independently from platform channels where practical:

- handoff active blocks resume-on-app-resume;
- ending handoff while app is resumed permits one resume;
- ending handoff while app is paused does not resume;
- stale renderer identity is never resumed.

Physical Android/iPhone smoke should confirm:

1. shutter -> frozen still -> processed save -> live preview returns;
2. background/foreground during processing does not expose or prematurely resume live preview;
3. failed capture -> Retry still works;
4. failed capture -> Back still cleans temporary source;
5. lens/flash/torch/mirror state remains coherent after resume.
