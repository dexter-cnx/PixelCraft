# PF1 Camera Runtime Wiring

Status: implementation branch `feature/pf1-camera-runtime-wiring`.

This slice activates the camera-first shell on the existing mobile camera runtime without changing PF3 capture semantics.

## Runtime flow

```text
Mobile/tablet launch
  -> CameraFilmPreviewScreen
  -> live native GPU camera when supported, Flutter camera fallback otherwise
  -> Film controls remain real and connected to the existing preview path
  -> bottom hierarchy: Gallery / Shutter / Controls
```

The implementation keeps a **single camera runtime** in `camera_film_preview_screen_g1.dart`; PF1 extends that runtime rather than maintaining a second camera implementation.

Gallery uses `MediaPickerService` and opens the existing editor handoff with the selected source untouched and no camera Film automatically applied.

Shutter keeps the pre-PF3 behavior:

```text
clean capture -> existing CameraFilmEditorHandoff
```

PF3 will separately replace that with:

```text
clean capture -> Rust authoritative render -> JPEG -> MediaSaveService -> Gallery -> remain in Camera
```

Controls opens a bounded camera controls surface. Camera switching is available there when the runtime reports more than one lens/camera.

Film is the only active camera tool in PF1. Filter and Adjust are visible as the target information architecture but do not expose fake editing controls; real integration belongs to PF2.

## Guardrails

- one camera runtime only; no duplicate camera stack;
- no live camera buffers through Flutter bridge/MethodChannel;
- GPU remains preview-only;
- Rust remains authoritative for committed edit semantics;
- no PF3 save/render behavior is pulled into PF1;
- Gallery source is not rewritten on selection.
