# PF9 — Native Preview Suspension During Capture Handoff

Status: **IMPLEMENTED / CI PENDING**

Branch: `feature/pf9-pause-preview-during-capture-handoff`

## Problem

PF7 hides the live Camera behind a frozen captured still while authoritative Rust processing and Gallery delivery run. On the native GPU camera path, the underlying Metal/OpenGL preview renderer could still continue running during that handoff even though it was not visible.

That behavior is functionally correct but wastes camera/GPU work and creates an avoidable lifecycle race if the app backgrounds and resumes while the frozen handoff is still active.

## Implemented flow

```text
capture clean JPEG
  ↓
push CameraCaptureSaveHandoff
  ↓
NativeGpuPreviewSuspension.acquire()
  ↓
pause tracked native preview renderer(s), best effort
  ↓
PF7/PF8 frozen still + process/save/Retry/Back semantics
  ↓
route is actually disposed
  ↓
NativeGpuPreviewSuspension.release()
  ↓
if app lifecycle == resumed
    resume still-current tracked renderer(s)
else
    wait for the camera screen's normal lifecycle resume call
```

## Architecture

`lib/gpu/native_gpu_preview_bridge.dart` remains the app-level import used by the camera screen. PF9 turns that file from a pure re-export into a narrow wrapper around the package `NativeGpuPreviewBridge`.

The wrapper preserves the package bridge API while tracking renderer identity and coordinating a reference-counted suspension state.

Key properties:

1. renderers are registered when `createRenderer()` succeeds;
2. renderers are unregistered when `destroyRenderer()` completes;
3. `NativeGpuPreviewSuspension.acquire()` pauses tracked renderers best effort;
4. normal `resume(rendererId)` calls are suppressed while suspension is active;
5. `release()` resumes only when the app lifecycle is `resumed`;
6. acquire/release operations are serialized so a fast route disposal cannot race a pending pause and leave the renderer paused;
7. a renderer created while suspension is already active is immediately paused best effort;
8. stale/destroyed renderer identity is never resumed.

`CameraCaptureSaveHandoff` acquires suspension once when the route becomes active and releases it from `dispose()`. This deliberately waits for route disposal rather than `Navigator.pop()` initiation, so the live preview does not resume underneath the reverse route transition.

## Failure policy

Preview suspension is an optimization, not capture authority.

- pause failure must not fail an already-captured authoritative shutter transaction;
- PF7/PF8 processing, save, Retry, and clean-source cleanup remain authoritative;
- lifecycle resume while the handoff is active is suppressed;
- once suspension is released, the camera screen's existing runtime failure/fallback path remains responsible for native renderer failures.

## Fallback camera

Flutter `camera` fallback behavior is unchanged. That path already detaches/disposes its `CameraController` before the save handoff and reinitializes it after the handoff returns.

## Automated validation

`test/gpu/native_gpu_preview_suspension_test.dart` covers:

- handoff suspension blocks a lifecycle `resume()` call;
- releasing while resumed causes one native resume;
- releasing while app-paused does not resume prematurely;
- a later normal lifecycle resume works after suspension is released;
- a destroyed renderer is never resumed after release.

Existing PF7/PF8 widget tests continue to cover frozen-still transaction and failed-source cleanup behavior.

## Physical smoke

Android and iPhone should verify:

1. shutter -> frozen still -> processed save -> live preview returns;
2. no visible live preview is exposed during processing/save;
3. background/foreground during processing does not prematurely resume preview;
4. failed capture -> Retry still works;
5. failed capture -> Back still cleans the temporary clean source;
6. lens/flash/torch/mirror state remains coherent after return;
7. repeated capture cycles do not leave the native renderer permanently paused.

## Non-goals

PF9 does not change:

- authoritative clean JPEG source semantics;
- Rust render/export authority;
- PF7 frozen-still UX;
- PF8 failed-source cleanup;
- Metal/OpenGL rendering architecture;
- RAW, MobileSAM/ONNX, external-edit transport, Dart 3.13 RecordUse, or generic plugin runtime.
