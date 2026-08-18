# PF3 Capture → Process → Save

Status: **IMPLEMENTATION IN PROGRESS / REBASED ON MAIN**

Branch: `feature/pf3-capture-process-save`

Base: `main`

PF3 UX now follows the camera-first mobile direction: permissions are handled before Camera use, capture processing stays on the Camera screen, and the mobile/tablet visual identity uses an orange-black palette rather than the previous purple accents.

## Goal

PF3 replaces the temporary PF2 camera capture → Editor handoff with the product capture flow:

```text
Greeting / What's New when required
 -> permissions settled
 -> Camera
 -> clean camera JPEG + final CameraLookState
 -> Rust authoritative full-resolution render
 -> JPEG
 -> MediaSaveService
 -> system Gallery
 -> remain in Camera
```

Gallery-picked/external sources remain on the normal Editor path and are not routed through the camera capture-save pipeline.

## Hard invariants

1. Camera/GPU preview pixels are never final-output authority.
2. Native camera capture remains a clean JPEG input.
3. The final CameraLook is rendered by Rust in deterministic order: Adjust → Film → Creative Filter.
4. Flutter/MethodChannel never receives live camera frame buffers.
5. Processed camera output is JPEG.
6. `GalleryMediaSaveService` owns only platform Gallery persistence; it does not own image semantics.
7. A render failure must never save clean or partially processed bytes as if PF3 succeeded.
8. Temporary clean capture remains available on failure so Retry can use the exact same source.
9. Gallery-picked/external sources remain neutral and unchanged by the active CameraLook.
10. A neutral camera capture is still a camera capture; routing is explicit and never inferred from look neutrality.

## Greeting / What's New gate

`lib/ui/screens/greeting_screen.dart`

- first run shows a branded Greeting screen before Camera;
- Camera and Gallery-write permission are requested from this flow rather than after shutter;
- the screen contains app title, key feature highlights, permission status, and a Continue-to-Camera action;
- the gate persists `permissions_prompted` and the latest `currentWhatsNewId` with SharedPreferences;
- when `currentWhatsNewId` changes for a future release, What's New appears once again and then remains hidden until the next ID change;
- normal launches skip this screen when permissions were already prompted and the current What's New ID was already seen.

The mobile/tablet visual identity is **orange + black**. Camera/Greeting accents use `#FF6A00` against black/dark surfaces. This replaces the earlier purple visual direction.

## Camera-first launcher icon

`tool/generate_camera_first_icon.py` is the reproducible source for the mobile/tablet launcher icon set.

- the mark is a conventional camera silhouette so the app reads as Camera-first at Home Screen size;
- no text is embedded in the icon;
- black is the base surface and `#FF6A00` is the primary camera/accent color;
- `assets/branding/app_icon.png`, Android mipmap launchers, and the iPhone/iPad AppIcon set are generated from the same mark;
- temporary generation workflow files are removed after generation and must not remain in the merge diff.

## Permission behavior

`lib/app/platform_media_services.dart` provides `PlatformPermissionService` through a small platform MethodChannel.

- iOS requests Camera and Photo Library add-only access;
- Android requests Camera access;
- Android 10+ Gallery write resolves without a storage prompt because PF3 adds new MediaStore items;
- Android 9 and earlier request legacy `WRITE_EXTERNAL_STORAGE`;
- system permission dialogs therefore occur before the user enters the normal shutter flow.

## iOS Rust bridge bootstrap

The iOS engine plugin builds `pixelcraft_engine` as a static library and force-loads `libpixelcraft_engine.a` into Runner through `packages/dxtr_pixs_engine/ios/dxtr_pixs_engine.podspec`.

FRB's default loader expects to open a dynamic framework on iOS. That is not the packaging model used by this repository, so a bare `RustLib.init()` can fail at runtime while looking for `pixelcraft_engine.framework/pixelcraft_engine` even though the Rust symbols are already linked into the app process.

`lib/core/bridge.dart` therefore supplies a platform-selected external library:

- iOS uses `ExternalLibrary.process(...)` so FRB resolves the statically linked Rust symbols from Runner itself;
- Android and desktop keep the normal FRB default loader by returning `null`;
- web remains isolated from `dart:io` through a conditional import.

This is a bootstrap/linkage correction only; it does not change Rust image-processing semantics.

## Capture processing behavior

`lib/camera/camera_capture_pipeline.dart`

- `CameraCaptureRenderer` isolates final-pixel rendering from platform persistence;
- `RustCameraCaptureRenderer` executes the complete CameraLook inside one background isolate;
- `CameraCapturePipeline` enforces render-before-save sequencing;
- Rust-exported JPEG bytes, never preview pixels, are passed to Gallery save.

`lib/camera/camera_capture_save_handoff.dart`

- the capture handoff is now transient rather than a processing destination;
- it immediately returns visual focus to Camera;
- processing, Gallery save, success, and failure/Retry feedback are presented with Camera-level SnackBars;
- no standalone processing screen is shown after shutter.

`lib/ui/screens/camera_film_preview_screen_g1.dart`

- native and fallback camera captures use the PF3 capture-save path;
- Gallery selection continues to open `CameraFilmEditorHandoff` with a neutral `CameraLookState`.

## Settings / About / What’s New

- Camera Controls acts as the current mobile Settings surface.
- Settings includes **About**.
- About shows a **What’s New** entry whenever `currentWhatsNewId` is non-empty.
- Opening What’s New from About is always allowed and does not modify the one-time Greeting seen-state.
- The About What’s New page reuses the same localized feature copy as the release Greeting so release notes do not drift.

## Camera UX polish

- capture process/save SnackBars are floating with a semi-transparent black surface so they do not visually block the camera preview;
- after a processed JPEG is saved successfully, the Gallery control shows that latest saved image as its thumbnail for the current app session;
- the thumbnail intentionally uses PixelCraft's own processed output and does not broaden Photo Library read permission just for decoration;
- before the first successful save in a session, the Gallery control falls back to the standard Gallery icon;
- Greeting is non-scrollable; it uses responsive scale-down within the available SafeArea instead of `SingleChildScrollView`.

## Automated coverage

`test/camera/camera_capture_pipeline_test.dart` covers authoritative source/render/save ordering and ensures render failure never reaches Gallery persistence.

The canonical CI remains the repository `Pixel Craft CI`; PF3 must not carry temporary workflow files into merge.

## Remaining validation

Before PF3 can close:

- exact-head CI/analyze/tests green;
- verify Rust bridge initialization on the physical iPhone after the static-link bootstrap correction;
- first-run Greeting and permission flow on Android and iPhone;
- What's New appears once for `currentWhatsNewId`, then skips on subsequent launch;
- verify the orange-black launcher icon on Android phone/tablet and iPhone/iPad;
- Android neutral and combined Film + Filter + Adjust capture/save;
- iPhone neutral and combined Film + Filter + Adjust capture/save;
- saved JPEG visually corresponds to the committed final CameraLook;
- capture processing/saving feedback remains on Camera via SnackBars;
- failure/Retry preserves the clean temporary source where practical;
- Gallery still opens the normal Editor path;
- Camera remains responsive/resumes correctly after save;
- update `PROJECT_HANDOFF.md`, `CODE_WALKTHROUGH.md`, and README after the verified final head is known.

## Merge policy

PF2 is merged. PF3 remains Draft until exact-head CI and Android/iOS physical validation pass.