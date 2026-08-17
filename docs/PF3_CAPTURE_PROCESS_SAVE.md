# PF3 Capture → Process → Save

Status: **IMPLEMENTATION IN PROGRESS / STACKED ON PF2**

Branch: `feature/pf3-capture-process-save`

Base while PF2 remains unmerged: `feature/pf2-unified-camera-look`

## Goal

PF3 replaces the temporary PF2 camera capture → Editor handoff with the product capture flow:

```text
clean camera JPEG
+ final CameraLookState
 -> Rust authoritative full-resolution render
 -> JPEG
 -> MediaSaveService
 -> system Gallery
 -> return/remain in Camera
```

## Hard invariants

1. Camera/GPU preview pixels are never final-output authority.
2. Native camera capture remains a clean JPEG input.
3. The final CameraLook is rendered by Rust in deterministic order:
   - Exposure
   - Temperature
   - Tint
   - Brightness
   - Contrast
   - Saturation
   - Vignette
   - Film
   - Creative Filter
4. Flutter/MethodChannel never receives live camera frame buffers.
5. Processed camera output is JPEG.
6. `GalleryMediaSaveService` owns only platform Gallery persistence; it does not own image semantics.
7. A render failure must never save clean or partially processed bytes as if PF3 succeeded.
8. Temporary clean capture remains available on failure so Retry can use the exact same source.
9. Gallery-picked/external sources remain neutral and unchanged by the active CameraLook.

## Current implementation

`lib/camera/camera_capture_pipeline.dart`

- `CameraCaptureRenderer` isolates final-pixel rendering from platform persistence.
- `RustCameraCaptureRenderer` executes the complete CameraLook inside one background isolate.
- `CameraCapturePipeline` enforces render-before-save sequencing.
- output is exported as JPEG from Rust before reaching `MediaSaveService`.

`lib/app/platform_media_services.dart`

- `GalleryMediaSaveService` saves the Rust-generated JPEG to the system Gallery.
- Android relative path remains `Pictures/Dxtr Pixs`.

`lib/camera/camera_film_editor_handoff.dart`

- retained temporarily as a compatibility call site for the existing large Camera screen;
- it no longer opens the Editor;
- it reads the clean capture, invokes PF3 render/save, deletes the temporary source after success, and returns to Camera;
- failure keeps the temporary source so Retry can rerun the same clean capture;
- Cancel cleans up the temporary source.

The compatibility class name should be removed in a later cleanup once the Camera screen capture orchestration is split into a smaller controller/service boundary. Do not mix that structural refactor into PF3 correctness work unless needed.

## Current UI behavior

During processing the user sees a short processing/saving state. After Gallery save succeeds the flow returns to Camera and shows a localized saved confirmation.

PF3 does not automatically open the Editor after shutter.

## Automated coverage

`test/camera/camera_capture_pipeline_test.dart`

Covers:

- clean source bytes are passed to the authoritative renderer;
- rendered JPEG bytes, not source bytes, are passed to Gallery save;
- phase order is `processing -> saving -> completed`;
- render failure prevents Gallery save.

## Remaining validation

Before PF3 can close:

- CI/analyze/tests green on exact head;
- physical Android capture with neutral look;
- physical Android combined Film + Filter + Adjust capture;
- physical iOS neutral capture;
- physical iOS combined Film + Filter + Adjust capture;
- verify saved item appears in system Gallery;
- verify saved JPEG visually corresponds to final CameraLook;
- verify shutter after a final slider movement uses the committed final value;
- verify repeated captures do not navigate into Editor;
- verify Camera resumes correctly after each save;
- verify failure/retry and temporary-source cleanup where practical;
- update `PROJECT_HANDOFF.md`, `CODE_WALKTHROUGH.md`, and README only after the verified final head is known.

## Stacking / merge policy

PF3 currently depends on PF2 code that is not yet on `main`, so the PR must remain stacked on `feature/pf2-unified-camera-look` until PF2 merges. After PF2 merge:

1. rebase/update PF3 onto `main`;
2. confirm the diff contains only PF3 changes;
3. run exact-head CI again;
4. perform/record PF3 physical-device validation;
5. only then merge PF3.
