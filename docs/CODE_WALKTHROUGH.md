# PixelCraft Code Walkthrough

Repository: **PixelCraft**  
Product: **Dextryx Pixels** (`Dxtr Pixs`)

## 1. Product boundary

PixelCraft is the camera + photo editor + image-processing product. It owns mobile/tablet camera UX, editor UX/session lifecycle, Rust-authoritative edit semantics, Film/Creative Filter/Adjust, transforms/masks, realtime GPU preview where faithful, full-resolution render/export, and editor recovery.

Nixin / Dextryx Images remains the long-lived image-management product and owns Workplaces, catalog identity, organization, browsing, collections, and large-library workflows.

## 2. Platform shell

### Phone and tablet

Phone/tablet are camera-first:

```text
launch
  ↓
Greeting / permissions when needed
  ↓
Camera
  ├── Film / Filter / Adjust
  ├── Composition Guide
  └── Gallery / Shutter / Controls
```

### Desktop

Desktop is editor/open/drop-first:

```text
launch
  ↓
Open / Drop
  ↓
Editor
```

## 3. Navigation

`lib/main.dart` uses `MaterialApp.router` with one persistent `GoRouter`.

Canonical routes:

```text
/                       platform-aware initial workspace
/camera                 phone/tablet camera workspace
/desktop                desktop open/drop workspace
/editor                 product editor
/films                  Film Profiles workspace
/debug/gpu-editor-lab   debug GPU editor lab
```

Policy:

```text
workspace change = route
workspace tool change = state
```

Editor navigation uses typed `EditorRouteData` through `GoRouterState.extra`; arbitrary local paths are not encoded in public URLs.

PF4 extends `EditorRouteData` with an optional typed `EditorSource`. Gallery/desktop/future external-edit metadata can therefore remain attached to the editor route while the current `ProductEditorScreen` compatibility boundary still consumes a file path or bytes.

Non-file typed sources fail closed at the route boundary until a supported resolver/decoder exists; PixelCraft does not silently copy or invent a path.

## 4. Camera implementation

Public camera entry:

```text
lib/ui/screens/camera_film_preview_screen.dart
```

Current runtime implementation:

```text
camera_film_preview_screen.dart
  -> PF4 routing wrapper
  -> camera_film_preview_screen_g1.dart
```

The PF4 wrapper is intentionally narrow. Camera capture/runtime behavior remains in G1; the wrapper intercepts the legacy Gallery picker callback and routes Gallery selections through the canonical typed Editor route.

The current camera foundation includes:

- native GPU preview on Android/iOS;
- Flutter `camera` fallback;
- lens switching;
- flash/torch/mirror controls;
- pinch zoom;
- image-ratio guides;
- Film, Filter, Adjust trays;
- Gallery entry;
- camera-first capture/save flow;
- localized processing/save/error feedback;
- Camera Controls modal with explicit Close button.

## 5. Camera look preview

Camera Film/Filter/Adjust state is transient preview state until capture.

```text
CameraLookState
  adjustments
  film id + strength
  creative filter id + strength
```

Native GPU preview applies the current CameraLook where faithful. Film/Filter thumbnail strips use bounded non-shutter live snapshots; they never run a continuous live-frame stream through MethodChannel/FRB.

The legacy shutter-backed preview path remains disabled:

```text
_enableStillCaptureLookPreviews = false
```

Opening a Film/Filter tray must not call `capturePhoto()` or trigger a shutter sound.

## 6. PF3 authoritative capture pipeline

PF3 capture path:

```text
clean camera JPEG
+ CameraLookState
+ image ratio
+ physical capture orientation
+ zoom factor
        ↓
CameraCapturePipeline
        ↓
RustCameraCaptureRenderer
        ↓
Adjust -> Film -> Creative Filter
        ↓
JPEG export
        ↓
MediaSaveService
        ↓
system Gallery
        ↓
CameraRecentThumbnail update
        ↓
remain in Camera
```

Important files:

```text
lib/camera/camera_capture_pipeline.dart
lib/camera/camera_capture_save_handoff.dart
lib/app/platform_media_services.dart
```

The preview framebuffer is never final output authority.

### Render serialization

The current Rust image engine is process-global and bridge calls are individually synchronized. PF3 therefore serializes the complete authoritative render transaction before invoking the renderer. This prevents concurrent background captures from interleaving `loadImage`, edit operations, and `exportImage`.

Regression coverage verifies max renderer concurrency remains 1 when two pipelines are started concurrently.

## 7. Capture handoff UX

`CameraCaptureSaveHandoff` is transient. It returns visual control to Camera immediately while the background processing job continues to report status through Camera SnackBars.

Presentation phases:

```text
processing
saving
completed
failed
```

On failure, Retry reuses the temporary clean source while it remains available. Successful completion deletes the temporary source best-effort and updates the recent thumbnail.

The serialization guard lives below the transient handoff, so returning to Camera does not permit authoritative Rust transactions to interleave.

## 8. Android native GPU lifecycle

Package:

```text
packages/dxtr_pixs_gpu/
```

Android stack:

```text
Camera2
  ↓
external OES texture
  ↓
OpenGL ES renderer
  ↓
TextureView / PlatformView output
```

After pause/external activity, the renderer is recreated rather than reusing stale Camera2/EGL state. Recreation restores:

- enabled state;
- active CameraLook;
- lens direction;
- flash mode;
- torch state;
- mirror state;
- output surface/rotation.

This keeps native camera behavior and Dart-visible control state aligned after resume.

## 9. iOS native GPU lifecycle

The iOS path uses AVFoundation + Metal for realtime camera preview. Bounded live snapshots of the active Metal preview are exposed only for thumbnail generation. Final capture remains the clean still JPEG rendered through Rust.

## 10. Composition Guide

Implementation:

```text
lib/camera/camera_composition_guide.dart
```

Supported guides:

```text
Thirds
Golden Ratio
Golden Spiral
```

Golden Spiral is generated procedurally with Flutter `CustomPainter`/`Path`; PNG/SVG assets are not the canonical implementation.

Persistent settings include:

- guide selection;
- Golden Spiral flip;
- guide color.

Initial color swatches:

```text
White
Black
Red
Yellow
Green
Cyan
```

Guide color updates the overlay painter live. Composition guides remain UI-only and are never captured into output pixels.

## 11. PF4 Gallery/editor source flow

PF4 source contracts:

```text
MediaPickerService
      ↓
MediaSourceDescriptor
      ↓
EditorSourceFactory
      ↓
EditorSource
  - original descriptor
  - provenance
  - MIME type
  - external id
  - format identity
      ↓
EditorRouteData.source
      ↓
Product Editor compatibility boundary
```

Camera Gallery flow currently uses `LegacyGalleryEditorRoutingPicker` as a temporary migration adapter. It consumes Gallery selections, opens the canonical typed `/editor` route, then returns `null` to the old G1 callback so the legacy direct `CameraFilmEditorHandoff` cannot run a second time.

Gallery/external sources never inherit transient `CameraLook` automatically.

Current format identity can represent JPEG, PNG, HEIF, RAW, and unknown without claiming all are currently decodable. RAW development remains deferred.

For current file-backed Gallery sources, `EditorRouteData.imagePath` derives the filesystem path only at the Product Editor compatibility boundary. The original typed source remains preserved in `EditorRouteData.source`.

The input source remains untouched. Output is a separate file/destination decision.

## 12. State and localization

Riverpod is the Flutter application/UI orchestration standard. It may own loading, selected tools, camera/transient preview state, progress, and presentation state.

Rust remains authoritative for canonical edit recipe/history/checkpoints/full-resolution export semantics.

User-facing Flutter copy uses `easy_localization` with `en` and `th` resources.

## 13. Rust authority

```text
Flutter app
   ↓
dxtr_pixs_engine
   ↓ FRB / CargoKit
rust/
```

Rust owns untouched source handling, semantic operations, recipe/history/checkpoint/recovery semantics, and full-resolution replay/export.

Useful commands:

```bash
make codegen
make integrate
make repair
make verify-native
```

## 14. Film and Creative Filter

Film Profiles are first-class Rust operations backed by canonical 33x33x33 LUT data. Creative Filters include exact grayscale/invert behavior and LUT-backed presets.

Camera preview may use faithful GPU implementations, but authoritative capture/export always goes through Rust.

## 15. Package graph

```text
PixelCraft App
 ├── dxtr_pixs_film
 ├── dxtr_pixs_gpu
 ├── dxtr_pixs_editing
 └── dxtr_pixs_engine

dxtr_pixs_film    -> dxtr_pixs_editing
dxtr_pixs_gpu     -> dxtr_pixs_editing
dxtr_pixs_editing -> Dart SDK only
dxtr_pixs_engine  -> repository rust/ crate
```

PKG-03 camera package extraction was audited after PF3 and is deferred. The current camera boundary still depends on app services, generated Rust bindings, GPU/native runtime ownership, and product-specific UX. Revisit only when a concrete second consumer or stable reusable camera API exists.

## 16. CI behavior

The repository uses an affected-validation DAG with `Fast CI` and `CI Gate` as stable branch-protection contexts.

Local entrypoint:

```bash
make preflight
```
