# PF7 — Frozen Captured-Still Processing

Status: **MERGED**

- PR: #59
- final exact head: `af63c0fbf7d813a5f319730c27407eece2775560`
- merge commit: `b75ac64085d5c2909c832f5f22f22698dcca684b`
- exact-head Pixel Craft CI: **#816 PASS**
- review threads: none open at merge

## Product problem

Before PF7, `CameraCaptureSaveHandoff` popped immediately after capture and continued authoritative processing in the background. The user therefore returned to a moving live camera preview while the just-captured photo was still being rendered and saved.

PF7 changes the shutter transaction so the clean captured JPEG remains visible until authoritative processing and Gallery delivery complete.

## Canonical flow

```text
Shutter
  ↓
capture clean JPEG
  ↓
push CameraCaptureSaveHandoff
  ↓
show captured clean JPEG as frozen still
  ↓
CameraCaptureHandoffTransaction.execute
  ↓
Rust authoritative full-resolution render
  ↓
Gallery save
  ↓
short success state
  ↓
initiate handoff route pop
  ↓
begin best-effort cleanup of temporary clean source
  ↓
return to live Camera as route transition completes
```

## Architecture

`CameraCaptureSaveHandoff` owns presentation and route lifecycle only:

- frozen-still presentation;
- processing/saving/completed/failed phase UI;
- Back gating while processing/saving;
- Retry affordance on failure;
- route completion after successful delivery.

`CameraCaptureHandoffTransaction` owns the authoritative transaction boundary:

- source file I/O;
- `CameraCapturePipeline` invocation;
- Rust authoritative full-resolution render;
- `MediaSaveService` delivery;
- best-effort temporary-source cleanup once successful route pop has been initiated.

The default implementation is `DefaultCameraCaptureHandoffTransaction`.

## Invariants

1. The clean camera JPEG remains the authoritative capture source.
2. The preview framebuffer is never used as final output.
3. Rust remains authoritative for full-resolution processing.
4. The captured still stays visible throughout processing and saving.
5. Conflicting Back/navigation is blocked only during active processing/saving.
6. Completed and failed phases are allowed to leave the route.
7. Failure preserves the captured source so Retry can execute the same authoritative transaction again.
8. On success, cleanup begins only after `Navigator.pop()` has been initiated. `MaterialPageRoute` may still be mounted during its reverse transition, so PF7 does not claim cleanup waits for route disposal.
9. PF7 does not change Metal/OpenGL ES preview architecture.
10. PF7 does not activate RAW, MobileSAM/ONNX, external-edit transport, Dart 3.13 RecordUse, or a generic plugin runtime.

## Important production bug found during PF7 validation

An intermediate implementation used `PopScope(canPop: false)` for the completed phase as well as active processing. That caused the handoff's own `Navigator.pop()` to be blocked and could leave the frozen still stuck on screen after a successful save.

The final implementation permits route exit for `completed` and `failed`, while retaining the lock for `processing` and `saving`.

## Test strategy

Regression coverage lives in:

```text
test/ui/camera/camera_capture_frozen_still_test.dart
```

The final test deliberately avoids asserting route-animation timing through widget-tree disappearance. It verifies the meaningful contract instead:

- transaction starts while the frozen still is visible;
- controls under the handoff are not hit-testable during processing;
- the handoff does not pop before the transaction finishes;
- after success, `NavigatorObserver.didPop` confirms route pop initiation;
- source cleanup follows that successful pop initiation.

This avoids coupling the regression test to `MaterialPageRoute` animation timing or incorrectly treating `didPop` as route disposal.

## Physical smoke recommended after merge

On Android and iPhone:

1. open Camera;
2. capture with a non-neutral Film/Filter/Adjust combination;
3. confirm the captured still freezes immediately;
4. confirm the underlying live preview is not exposed while processing/saving;
5. confirm processed output appears in system Gallery;
6. confirm the app returns to live Camera automatically;
7. confirm recent Gallery thumbnail refreshes;
8. repeat with neutral CameraLook;
9. if practical, induce a save/render failure and confirm Retry keeps using the clean captured source.

Hosted CI does not substitute for this physical-device smoke.
