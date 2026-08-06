# PixelCraft Implementation Plan — Phases 1–4

This plan converts PixelCraft from a Flutter/Rust prototype into a production-oriented offline image editor. The work is intentionally split into reviewable increments because each phase changes the engine model, generated FRB bindings, UI state, persistence, and tests.

## Phase 1 — Production editing core

### Goals

- Replace preview-byte history with operation history.
- Replay committed operations against the original image.
- Export full-resolution PNG/JPEG/WebP.
- Save and share exported files.
- Add before/after comparison.

### Engine model

```text
EditSession
├── original compressed bytes
├── committed operations
├── cursor
├── preview cache
└── pending operation
```

### Operation schema

```text
Filter(name, value)
Crop(x, y, width, height)       // normalized coordinates
Rotate90(turns)
FlipHorizontal
FlipVertical
Resize(width, height)
```

### Acceptance criteria

- One slider gesture creates exactly one operation.
- Undo/redo changes the operation cursor instead of storing PNG snapshots.
- Full-resolution export replays the active operation range against the original.
- Preview remains bounded to 1280 px.
- Export supports format and quality selection.
- Golden tests cover export dialog and before/after mode.

## Phase 2 — Editor tools and responsive UI

### Goals

- Add crop, rotate, flip, and straighten.
- Move controls into a tool-based editor layout.
- Add adjustment groups and tablet layout.

### Tool navigation

```text
Adjust | Filters | Crop | Rotate | Details
```

### Acceptance criteria

- Crop coordinates are normalized and replay correctly at full resolution.
- Phone and tablet layouts have no overflow.
- Light, dark, and text-scale golden tests pass.
- Crop, rotate, and flip are undoable operations.

## Phase 3 — Production quality

### Goals

- Add async preview orchestration with latest-request-wins.
- Persist edit sessions and recover drafts.
- Add GitHub Actions CI.
- Add performance and memory instrumentation.

### Preview orchestration

- UI value updates immediately.
- Rendering is debounced.
- Every request receives a revision number.
- Stale results are discarded.
- Export work never blocks the UI isolate.

### Persistence

```json
{
  "version": 1,
  "source": "local-file-reference",
  "operations": [],
  "cursor": 0,
  "updatedAt": "ISO-8601"
}
```

### CI jobs

- flutter-quality
- rust-quality
- golden
- android-native-build

### Acceptance criteria

- A killed app can recover its latest draft.
- Stale preview requests cannot overwrite newer values.
- CI verifies analysis, tests, formatting, clippy, golden files, APK build, and bundled Rust library.

## Phase 4 — Advanced editing foundation

### Goals

- Add selective rectangular/gradient masks.
- Add non-destructive text and sticker operations.
- Add batch processing.
- Add preset import/export.
- Prepare a GPU preview abstraction while preserving Rust final rendering.

### Extended operation schema

```text
MaskedFilter(filter, value, mask)
TextLayer(text, transform, style)
StickerLayer(asset, transform, opacity)
Preset(name, operations)
```

### Acceptance criteria

- Advanced edits remain serializable and replayable.
- Batch processing uses the same operation pipeline as single-image export.
- Presets can be exported/imported as versioned JSON.
- CPU/Rust rendering remains the source of truth for exported output.

## Required implementation order

1. Introduce versioned operation/session models.
2. Implement Rust replay and full-resolution export.
3. Regenerate FRB bindings and update the Dart engine abstraction.
4. Migrate EditorController to operation history.
5. Add export UI and before/after.
6. Add crop/rotate/flip tools.
7. Add async orchestration and draft persistence.
8. Add CI and expanded golden coverage.
9. Add Phase 4 operation types and UI foundations.

## Validation gate for every increment

```bash
make codegen
cargo fmt --manifest-path rust/Cargo.toml --all -- --check
cargo clippy --manifest-path rust/Cargo.toml --all-targets -- -D warnings
cargo test --manifest-path rust/Cargo.toml
flutter analyze
flutter test
make golden-test
make verify-native
```

## Important constraint

FRB generated files must be regenerated after Rust API changes. A phase is not considered complete until generated Dart/Rust bridge code, host tests, golden tests, and a physical-device native test all pass.
