# PixelCraft Code Walkthrough

เอกสารนี้อธิบาย architecture ปัจจุบันของ PixelCraft ตั้งแต่เปิดแอป เลือกรูป ส่งงานผ่าน `flutter_rust_bridge` ไปยัง Rust, operation history, full-resolution export, transform tools, responsive editor, workflow ของ Adjust/Creative Filters และ Camera Film Preview / GPU Preview foundation จนถึง G0.3

> หลักการสำคัญคือ Flutter รับผิดชอบ UI และ state projection ส่วนงาน decode, filter, histogram, transform, operation replay และ export อยู่ใน Rust โดยงานหนักที่เรียกผ่าน synchronous FRB API ถูก dispatch ผ่าน background Dart isolate เพื่อลดการ block UI isolate
>
> สำหรับ real-time GPU preview นั้น Dart เป็น **control plane เท่านั้น**: ส่ง capability, renderer lifecycle และ effect state ขนาดเล็กไป native backend โดยไม่ส่ง camera/image frame buffers ผ่าน MethodChannel หรือ Flutter Rust Bridge. Rust ยังคงเป็น authoritative renderer สำหรับ final/full-resolution output

## Current flow summary

```text
Select image
  -> background isolate -> Rust load_image
  -> decode and build one reduced editor preview (max edge 1024)
  -> histogram from reduced preview
  -> background prewarm of creative-filter thumbnails

Adjust / Creative Filter / Crop / Rotate / Flip / Straighten
  -> operate only on the reduced editor preview
  -> retain EditOperation recipe for full-resolution replay

Apply
  -> promote the already-rendered reduced preview to the next checkpoint
  -> keep the full EditOperation recipe
  -> reset draft cursor/UI state
  -> no full-resolution processing

Cancel
  -> restore the previous reduced Apply checkpoint
  -> discard the current draft branch

Export
  -> decode untouched original at full resolution
  -> replay the complete EditOperation recipe once
  -> encode requested PNG/JPEG/WebP
```

Camera Film Preview currently follows a separate non-destructive preview flow:

```text
Camera source
  -> current CameraPreview
  -> Film Profile matrix approximation (safe fallback)

Capture
  -> keep original capture clean
  -> transfer selected Film Profile state to Editor
  -> Rust applies authoritative 33^3 Film LUT for final rendering
```

The matrix camera preview is deliberately treated as an approximation, not as the Film Profile reference renderer. G0.3 prepares the native GPU path that will replace this approximation in G1 without changing capture semantics.

## Reduced-preview editing architecture

PixelCraft deliberately separates **interactive editing resolution** from **export resolution**.

`rust/src/engine.rs` keeps the untouched full-resolution compressed source bytes plus the complete `Vec<EditOperation>`. The editor also keeps a cached `checkpoint_preview` whose maximum edge is currently 1024 pixels. Interactive filters and transforms replay only the operations after the latest Apply checkpoint against this reduced image.

This removes the previous hot path where every preview operation could decode/replay the original full-resolution image and then resize it for display. It also makes Apply inexpensive because Apply no longer needs to render and re-encode the full-resolution image.

Supported operations include Filter, Crop, Rotate90, RotateDegrees/Straighten, FlipHorizontal, FlipVertical, and Resize.

## Apply checkpoints and operation recipe

The engine uses two cursor concepts internally:

- `cursor` — absolute position in the complete operation recipe
- `checkpoint_cursor` — boundary marking operations already accepted by the most recent Apply

The UI session reports only draft operations after `checkpoint_cursor`, so after Apply the editor returns to `0/0 edits` even though earlier operations are still preserved internally for export.

Pressing Apply now performs this lightweight flow:

```text
current reduced preview
  -> encode/cache as checkpoint preview
  -> checkpoint_cursor = cursor
  -> retain operations[0..cursor]
  -> UI draft count resets to 0
```

No full-resolution source decode, filter replay, resize, or bake happens during Apply.

Undo is bounded by the Apply checkpoint, so it cannot cross into already-applied edits. A new operation after Undo still truncates the redo tail inside the current draft branch.

## Full-resolution export

Export is intentionally the expensive path. `export_image()` decodes the untouched original source and replays all active operations from the beginning at full resolution, then encodes the selected PNG/JPEG/WebP result.

This means editing can stay responsive while export preserves full image quality:

```text
Editor:  original -> 1024px checkpoint preview -> fast draft operations
Export:  original full resolution -> replay complete operation recipe -> output
```

Applied checkpoints therefore do not degrade image quality by repeatedly baking resized intermediates.

## Flutter state and background processing

`lib/state/editor_controller.dart` projects the Rust engine state into Flutter. It tracks preview bytes, checkpoint preview, histogram, Adjust filter selection, creative filter selection/intensity, thumbnail cache, current tool, busy state, and draft cursor values.

Initial image preparation now uses `ImageEngine.loadImageInBackground()` so decode, reduced-preview generation, histogram construction, and Rust session initialization execute outside the UI isolate. The editor working preview uses `editorPreviewMaxEdge = 1024`.

`lib/core/image_engine.dart` wraps synchronous FRB calls using `Isolate.run()`. Heavy filter, transform, Apply, Cancel, Undo/Redo, preview generation, image preparation, and full-resolution export work therefore execute away from the UI isolate.

## Adjust controls

`FilterSlider` changes only its local thumb/value while the user drags. Rust is called once on `onChangeEnd`. Processing is performed against the reduced working preview rather than the original full-resolution image.

The first release creates one draft filter operation. Releasing the same Adjust slider again before Apply replaces that draft operation instead of stacking a second copy.

## Creative filter previews

Creative filters currently include grayscale, invert, vintage, oceanic, lofi, dramatic, golden, and pastel pink. There is no default selected creative filter.

Thumbnail generation starts automatically after the reduced checkpoint preview is available. `generate_filter_previews()` decodes that already-small checkpoint source once, resizes once to about 180 px max edge, runs variants in parallel with Rayon, and caches the resulting thumbnails.

Trying Vintage and then Oceanic does not regenerate thumbnails and does not make Oceanic depend on the Vintage draft. After Apply changes the checkpoint, PixelCraft prewarms one new thumbnail set from the new reduced checkpoint.

## Creative filter replacement and intensity

The first creative-filter tap creates one Filter draft at intensity `1.0` and shows a `0.0..1.0` intensity slider.

Selecting another filter or changing intensity replaces the same active filter draft rather than stacking another Filter operation. The source remains the same reduced checkpoint until Apply.

## Shared Apply / Cancel workflow

`EditorToolPanel` exposes shared Cancel and Apply controls for Adjust, Filters, Crop, and Rotate workflows.

Apply promotes the current reduced preview to a checkpoint while retaining the full operation recipe. Cancel restores the previous reduced checkpoint and removes the current draft branch. Filter/tool selections reset after either action.

## Transform tools

Crop uses normalized centered presets (1:1, 4:3, 3:4, 16:9, 9:16). Rotate supports quarter turns. Flip supports horizontal and vertical. Straighten uses -15°..15° and processes only after slider release.

All transform previews are computed at reduced editor resolution. Their normalized/semantic operations are retained so export can replay equivalent edits at full source resolution.

## Before / After

`original_preview()` returns the cached reduced preview for the latest Apply checkpoint. Long press temporarily compares the current draft against that checkpoint rather than decoding the full-resolution source again.

## Import / export storage

Gallery import shows progress while the selected asset is read and image preparation continues in the editor. Export saves an app-private backup and publishes a copy to the device photo gallery. Android public exports use `Pictures/PixelCraft`.

## Responsive UI

`EditorScreen` uses a compact vertical layout on phones and a side tool panel from 900 px upward. Editing controls are temporarily disabled while a background operation is running.

## Camera Film Preview

Camera Film Preview keeps the capture source non-destructive. The selected Film Profile affects what the user sees in preview and is carried forward as edit state, but it is not baked into the JPEG produced by the camera plugin.

The current Camera path still uses a `ColorFilter.matrix`-style approximation as the fallback preview. This remains intentionally available while the real Android GPU LUT renderer is brought up in G1.

The architectural rule is:

```text
preview failure
  -> fall back to matrix approximation
  -> never mutate/bake the captured source
```

When the user captures a photo, the original camera output remains clean. The selected Film Profile is transferred into the normal Editor flow, and Rust remains responsible for authoritative LUT rendering during final processing/export.

## Versioned Edit Graph

`lib/core/edit_graph.dart` defines the shared versioned edit contract. The current schema version is `3`.

The long-term architecture is:

```text
Input / Camera
      |
      v
  Edit Graph
      |
      +----------------------+----------------------+
      |                                             |
      v                                             v
GPU Preview Renderer                         Rust Final Renderer
interactive / low latency                    authoritative / full-res
Camera + Editor                              Export + Batch + Resume
```

The Edit Graph is intended to become the common semantic state for Film Profiles, adjustments, masks, overlays, presets and later Editor GPU Preview. GPU code must not invent a second effect-state model with different parameter meanings.

## GPU preview renderer abstraction

`lib/gpu/gpu_preview_renderer.dart` contains the renderer-neutral Dart contract and capability types.

Backend kinds are currently:

- `fallback`
- `androidOpenGl`
- `iosMetal`

`FallbackGpuPreviewRenderer` explicitly reports that it does not support a real 33^3 LUT. That distinction allows callers to know whether they are looking at a parity-capable GPU renderer or only the current approximation.

Dart does not own live frame buffers in this design. Renderer state changes should consist only of small values such as Film Profile ID, strength, viewport, enabled state and Edit Graph metadata.

## G0.3 capability and fallback policy

`lib/gpu/gpu_preview_capability.dart` centralizes the production decision about whether native GPU preview is eligible.

The decision flow is:

```text
Native probe
   |
   +-- protocol mismatch ----------> fallback
   +-- device/GPU blacklisted -----> fallback
   +-- backend unavailable --------> fallback
   +-- LUT33 unsupported ----------> fallback
   +-- generated assets missing ---> fallback
   +-- shader self-test failed ----> fallback
   |
   v
native GPU eligible
```

Runtime failures are represented separately from probe failures. The policy distinguishes at least:

- `protocolMismatch`
- `backendUnavailable`
- `lut33Unsupported`
- `shaderSelfTestFailed`
- `nativeAssetsUnavailable`
- `rendererInitializationFailed`
- `runtimeRenderFailure`
- `blacklisted`

This is important because a renderer that failed during initialization should invalidate the previously cached capability result rather than continually retry a backend that is no longer trustworthy for the current session.

The fallback capability continues to use the existing Camera matrix preview until G1 has proven stable.

## Native GPU control protocol

`lib/gpu/native_gpu_preview_bridge.dart` is the Flutter side of the versioned native control protocol.

Channel:

```text
dev.pixelcraft/gpu_preview_v1
```

Protocol version:

```text
1
```

Normal production capability negotiation calls `probe`. The G0.2 parity harness methods remain available for validation but are deliberately separated from normal Camera startup.

The bridge now exposes the production lifecycle control messages:

```text
probe
createRenderer
configureSurface
setFilm
setStrength
setViewport
setEnabled
pause
resume
destroyRenderer
```

The Android channel also exposes capability-cache invalidation internally so renderer initialization failures can force a fresh capability decision later.

No JPEG, PNG, raw camera plane, RGBA frame or other image buffer is passed through this MethodChannel.

## Renderer/session lifecycle

`lib/gpu/gpu_preview_session.dart` defines the Dart-side renderer/session state contract, while `NativeGpuPreviewSession` in `lib/gpu/native_gpu_preview_bridge.dart` implements that contract over the native channel.

The lifecycle separates renderer existence from surface ownership:

```text
idle
  -> createRenderer
created
  -> configureSurface
surfaceConfigured
  -> pause
paused
  -> resume
surfaceConfigured / created
  -> destroyRenderer
destroyed
```

A renderer can therefore survive normal state updates without rebuilding the camera session. Film Profile changes and strength changes become renderer state/uniform changes rather than camera restarts.

This contract is designed to handle future route changes, app pause/resume, front/rear camera switching, surface recreation and GPU context loss without leaving stale native objects behind.

## Android background capability probing

`android/app/src/main/kotlin/dev/pixelcraft/pixelcraft/GpuPreviewChannel.kt` no longer performs EGL/shader capability work synchronously inside the MethodChannel handler.

Heavy GPU validation is serialized onto a dedicated single-thread executor. Results are posted back to Flutter on Android's main looper only after the background work completes.

This keeps operations such as:

```text
EGL display/context creation
shader compile/link
LUT texture upload
reference draw/readback
```

away from the Android platform/UI thread.

The explicit G0.2 harness methods (`runReferenceHarness` and `runFilmProfileHarness`) also use the background executor.

## Android capability cache and native assets

`android/app/src/main/kotlin/dev/pixelcraft/pixelcraft/GpuCapabilityProbe.kt` owns the production Android probe.

Before running the shader self-test it verifies that the generated LUT package is present, including the manifest, parity fixture and all Film Profile atlas assets.

The result is cached against an identity containing:

```text
cache schema
+ app version name
+ app version code
+ Android Build.FINGERPRINT
+ SDK level
```

Normal startup therefore uses a cheap cached result instead of recreating an EGL context every time the Camera opens.

A forced self-test can bypass the cache when validation is explicitly required. Renderer initialization failure invalidates the cache so the next decision is not based on a stale successful probe.

`GpuPreviewBlacklist` is the explicit extension point for narrow, evidence-based device or renderer exclusions. The blacklist is currently empty; its presence allows a known-bad GPU/driver combination to fail distinctly from a generic backend error.

## Android native renderer session registry

`android/app/src/main/kotlin/dev/pixelcraft/pixelcraft/GpuPreviewRendererSession.kt` stores the native renderer/session state independently of Flutter widgets.

Each renderer receives a stable renderer ID. The registry owns configuration such as:

- surface configuration
- Film Profile ID
- Film strength
- viewport
- enabled state
- pause/resume state

This G0.3 implementation is intentionally a lifecycle/state foundation, not yet a live camera renderer. It provides the resource boundary that G1 will fill with actual EGL/OES objects.

Destroying a renderer removes its session from the registry, preventing later control messages from silently updating stale native state.

## Android Camera OES boundary for G1

`android/app/src/main/kotlin/dev/pixelcraft/pixelcraft/GpuCameraOesRenderer.kt` defines the native interface that G1 should implement.

Target G1 frame path:

```text
Camera frame
  -> SurfaceTexture / GL_TEXTURE_EXTERNAL_OES
  -> OpenGL ES fragment shader
  -> canonical 33^3 Film LUT atlas
  -> output Surface / Flutter texture/native view
```

The interface separates renderer lifecycle, input camera surface, output surface and effect state so Camera2/CameraX ownership does not become entangled with Flutter's control protocol.

G0.3 deliberately does **not** attach the current camera feed to this interface yet. That prevents lifecycle/surface design from being debugged at the same time as frame rendering.

The following approaches are explicitly excluded:

```text
Camera frame -> JPEG/PNG every frame
Camera ImageStream -> Dart -> GPU
Camera frame -> Flutter Rust Bridge -> Rust -> Flutter every frame
```

## Canonical Film LUT path

The Film Profile authoring source remains the Rust Film Profile Pack:

```text
rust/film_profiles/*/look.json
        -> rust/build.rs
        -> canonical 33^3 lut.cube
             -> Rust final renderer
             -> GPU atlas generator
```

The Android GPU atlas is therefore not a separately authored approximation. It is generated from the same canonical LUT that Rust uses.

Atlas v1 uses:

- 33^3 LUT
- 6 x 6 tile grid
- 33 x 33 texels per tile
- 198 x 198 RGBA8 atlas
- bilinear R/G interpolation
- linear interpolation between adjacent B slices
- no mipmaps

The physical-device harness validates shader sampling/addressing against canonical reference fixtures within the agreed tolerance.

## Color-space contract

`docs/G0_3_GPU_PREVIEW_CONTRACTS.md` documents the color-pipeline boundary that must be resolved before Camera preview can be described as visually equivalent to Rust final output.

The contract distinguishes:

```text
camera source transfer / color space
  -> GPU shader input assumptions
  -> LUT domain
  -> preview output space
  -> Rust decoder assumptions
  -> export color space
```

The existing G0.2 parity harness proves **LUT atlas sampling math and addressing**, because both its input values and expected values are deterministic RGB fixture values.

It does not yet prove full visual parity for:

- camera YUV -> RGB conversion
- transfer function / gamma handling
- camera color primaries
- wide-gamut / HDR inputs
- display/output color management
- Rust image decode vs camera-preview conversion

Those boundaries must be fixed and validated during G1 before claiming Camera GPU Preview matches the final Rust render.

## G0.3 -> G1 handoff

At the end of G0.3 the architecture is intentionally in this state:

```text
Camera
  -> current matrix fallback ---------------------> visible preview

Dart
  -> capability/fallback policy
  -> renderer lifecycle/state only
                 |
                 v
Android native GPU foundation
  -> cached background capability probe
  -> renderer session registry
  -> Camera OES renderer interface
  -> no live frames attached yet
```

G1 can now implement the actual OpenGL ES/OES renderer without changing the public lifecycle semantics.

The key G1 validation targets remain:

- profile changes update live preview without rebuilding camera session
- strength changes update shader state/uniforms only
- at least 30 fps on the reference Android device
- captured source remains clean
- Film state still reaches Editor/Rust final rendering
- front/rear camera switching works
- orientation/crop remains correct
- pause/resume and route changes release/recreate resources safely
- GPU failure falls back automatically to matrix preview

## FRB code generation

The reduced-preview architecture changes engine internals but keeps the existing FRB function signatures for `prepare_preview`, `apply_edits`, and `export_image`. Generated bridge files only need regeneration when public Rust API signatures change.

The G0.3 Camera GPU control path is independent of FRB: it uses the native MethodChannel only for small renderer state/control messages. Rust final rendering remains unchanged by the addition of the native preview lifecycle.

## Testing / validation

Host/editor checks:

```bash
flutter pub get
make codegen
cargo fmt --manifest-path rust/Cargo.toml --all
cargo clippy --manifest-path rust/Cargo.toml --all-targets -- -D warnings
cargo test --manifest-path rust/Cargo.toml
flutter analyze
flutter test test/state
flutter test test/ui --exclude-tags=golden
```

GPU foundation checks:

```bash
flutter test test/gpu/gpu_preview_capability_test.dart
make gpu-lut-verify
make gpu-luts
make gpu-native-test DEVICE=RF8Y909V0LV
```

Existing native/editor validation remains available:

```bash
make golden-update
make golden-test
make verify-native
make native-test DEVICE=RF8Y909V0LV
```

For editor architecture, the most important device checks are large-image import latency, filter/transform latency, Apply latency, and full-resolution export correctness after several Apply checkpoints.

For G0.3/G1 GPU work, additionally check capability cache behavior, forced self-test, fallback selection, renderer create/destroy cycles, app pause/resume, surface recreation and absence of UI-thread stalls during GPU probing.
