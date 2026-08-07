# PixelCraft Code Walkthrough

เอกสารนี้อธิบาย architecture ปัจจุบันของ PixelCraft ตั้งแต่เปิดแอป เลือกรูป ส่งงานผ่าน `flutter_rust_bridge` ไปยัง Rust, operation history, full-resolution export, transform tools, responsive editor และ workflow ของ Adjust/Creative Filters

> หลักการสำคัญคือ Flutter รับผิดชอบ UI และ state projection ส่วนงาน decode, filter, histogram, transform, operation replay และ export อยู่ใน Rust โดยงานหนักที่เรียกผ่าน synchronous FRB API ถูก dispatch ผ่าน background Dart isolate เพื่อลดการ block UI isolate

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

## FRB code generation

The reduced-preview architecture changes engine internals but keeps the existing FRB function signatures for `prepare_preview`, `apply_edits`, and `export_image`. Generated bridge files only need regeneration when public Rust API signatures change.

## Testing / validation

```bash
flutter pub get
make codegen
cargo fmt --manifest-path rust/Cargo.toml --all
cargo clippy --manifest-path rust/Cargo.toml --all-targets -- -D warnings
cargo test --manifest-path rust/Cargo.toml
flutter analyze
flutter test test/state
flutter test test/ui --exclude-tags=golden
make golden-update
make golden-test
make verify-native
make native-test DEVICE=RF8Y909V0LV
```

The most important device checks are large-image import latency, filter/transform latency, Apply latency, and full-resolution export correctness after several Apply checkpoints.
