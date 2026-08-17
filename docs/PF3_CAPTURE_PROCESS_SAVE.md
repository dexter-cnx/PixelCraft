# PF3 Capture → Process → Save

Status: **IMPLEMENTATION IN PROGRESS / REBASED ON MAIN**

Branch: `feature/pf3-capture-process-save`

Base: `main`

UX refinement in progress on this branch: request Gallery-write permission during Camera startup, and keep capture processing/saving feedback on the Camera screen through SnackBars instead of navigating to a processing page.

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

Gallery-picked/external sources remain on the normal Editor path and are not routed through the camera capture-save pipeline.

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
10. A neutral camera capture is still a camera capture; capture-vs-Gallery routing must never be inferred from whether `CameraLookState` is neutral.

## Current implementation

`lib/camera/camera_capture_pipeline.dart`

- `CameraCaptureRenderer` isolates final-pixel rendering from platform persistence.
- `RustCameraCaptureRenderer` executes the complete CameraLook inside one background isolate.
- `CameraCapturePipeline` enforces render-before-save sequencing.
- output is exported as JPEG from Rust before reaching `MediaSaveService`.

`lib/app/platform_media_services.dart`

- `GalleryMediaSaveService` saves the Rust-generated JPEG to the system Gallery.
- Android relative path remains `Pictures/Dxtr Pixs`.

`lib/camera/camera_capture_save_handoff.dart`

- camera-only PF3 processing/save destination;
- reads the clean capture, invokes PF3 render/save, deletes the temporary source after success, and returns to Camera;
- failure keeps the temporary source so Retry can rerun the same clean capture;
- Cancel cleans up the temporary source.

`lib/camera/camera_film_editor_handoff.dart`

- remains the PF2 Editor handoff for Gallery/external sources;
- PF3 does not repurpose it.

`lib/ui/screens/camera_film_preview_screen_g1.dart`

- shutter/native capture routes to `CameraCaptureSaveHandoff`;
- fallback camera capture routes to `CameraCaptureSaveHandoff`;
- Gallery selection continues to route to `CameraFilmEditorHandoff` with a neutral `CameraLookState`.

## Current UI behavior

During camera-capture processing the user sees a short processing/saving state. After Gallery save succeeds the flow returns to Camera and shows a localized saved confirmation.

PF3 does not automatically open the Editor after shutter. Gallery selection still opens the Editor.

## Automated coverage

`test/camera/camera_capture_pipeline_test.dart`

Covers:

- clean source bytes are passed to the authoritative renderer;
- rendered JPEG bytes, not source bytes, are passed to Gallery save;
- phase order is `processing -> saving -> completed`;
- render failure prevents Gallery save.

CI also runs `flutter test test/camera` as a dedicated camera gate.

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
- verify Gallery still opens the normal Editor path;
- verify Camera resumes correctly after each save;
- verify failure/retry and temporary-source cleanup where practical;
- update `PROJECT_HANDOFF.md`, `CODE_WALKTHROUGH.md`, and README only after the verified final head is known.

## Merge policy

PF2 is merged. PF3 is now rebased directly onto `main`, and the diff has been reduced to PF3-only files. The PR remains Draft until exact-head CI and Android/iOS physical validation pass.