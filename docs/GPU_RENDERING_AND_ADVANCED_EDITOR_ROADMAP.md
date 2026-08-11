# GPU Rendering and Advanced Editor Roadmap

Status: Architecture plan
Branch prepared from: `feature/camera-film-preview`

## 1. Target Architecture

Pixel Craft should converge on one non-destructive edit model with two renderers:

1. **GPU Preview Renderer** — low-latency interactive rendering for Camera and Editor.
2. **Rust Final Renderer** — authoritative full-resolution render, export, batch processing, persistence, and recipe replay.

The edit model is the contract between them. UI must not encode effect behavior directly.

```text
Input image / camera frame
        |
        v
  Edit Graph / Recipe
        |
        +----------------------+-----------------------+
        |                                              |
        v                                              v
GPU Preview Renderer                            Rust Final Renderer
30/60 fps interactive                          deterministic full-res
native GPU / shader                            CPU initially, GPU optional later
        |                                              |
        v                                              v
Camera / Editor preview                        Export / Batch / Resume
```

### Source-of-truth rule

Rust owns the canonical semantics of every edit operation. GPU preview may use a lower precision or preview-specific implementation, but operation names, ranges, transforms, mask coordinates, blend order, color-space assumptions, and Film Profile IDs must match Rust.

## 2. Camera Film Preview: matrix -> real GPU LUT

### Current state

The embedded Film Camera uses lightweight `ColorFilter.matrix` approximations for the six Film Profile Pack v2 looks. The accepted capture remains unmodified and the selected Film Profile is applied later by the Rust 33³ LUT renderer.

### Target state

Replace matrix approximation with a native GPU viewfinder that evaluates the same 33³ LUT data used by Rust.

Do **not** stream camera frames through Dart or Rust at 30/60 fps. Camera frames should remain on the platform GPU path.

### Proposed implementation

#### Shared LUT source

Keep `rust/film_profiles/*` as the authoring source. Extend the build/generation step to emit two artifacts from the same profile definition:

- Rust generated LUT table for final rendering.
- GPU preview LUT atlas for native camera/editor preview.

Recommended preview texture format:

- LUT size: 33³.
- 2D atlas: 6 x 6 tiles, each tile 33 x 33 pixels; 33 slices used, 3 unused.
- Atlas dimensions: 198 x 198.
- Preferred runtime texture: RGBA16F where supported.
- Compatibility fallback: RGBA8.
- Interpolation: hardware bilinear within R/G slice + manual interpolation between adjacent B slices.

This keeps the preview data compact and avoids depending on 3D texture support across older Android devices.

#### Android

Target: Android API 21+.

Use a native camera pipeline and GPU surface processor rather than trying to sample Flutter's `CameraPreview` texture from a Dart fragment shader.

Preferred design:

```text
Camera2 / CameraX frame
      -> external OES texture
      -> OpenGL ES shader
           - YUV/RGB conversion as required
           - exposure / WB preview uniforms later
           - 33³ LUT atlas
           - LUT strength mix
      -> SurfaceTexture / Flutter texture
```

The Flutter layer owns controls and sends only small state updates:

```text
profile id
strength
camera lens
flash/exposure controls
```

No per-frame pixel buffers cross the platform channel.

#### iOS

Use AVFoundation + Metal/Core Image:

```text
AVCapture frame
      -> CVPixelBuffer / Metal texture
      -> Metal fragment shader or CIColorCube
      -> Flutter texture / native view
```

Use the same generated LUT data and strength semantics as Android/Rust.

### Camera acceptance criteria

- Preview remains >= 30 fps on the project's reference Android device.
- Selecting a Film Profile updates the viewfinder in < 1 frame where possible.
- Capture contains the clean source image, not the preview LUT baked in.
- Editor automatically applies the selected Film Profile through Rust.
- Preview vs Rust final render should be visually close; define a small image-difference tolerance for preview parity tests.
- Portrait/landscape/front/rear orientation remains correct.
- Android minSdk stays 21.

## 3. Unified Edit Graph

Before Selective Adjustments, Masks, Text/Stickers, Batch, and Presets are implemented, migrate the current linear editor recipe toward a versioned edit graph.

Proposed conceptual model:

```json
{
  "schemaVersion": 3,
  "document": {
    "canvas": {"width": 0, "height": 0},
    "nodes": [
      {
        "id": "n1",
        "type": "filmProfile",
        "enabled": true,
        "opacity": 1.0,
        "params": {"profileId": "provia_inspired", "strength": 1.0},
        "maskId": null
      }
    ],
    "masks": [],
    "overlays": []
  }
}
```

Each operation should have:

- stable ID
- operation type
- enabled flag
- opacity/strength
- versioned parameters
- optional mask reference
- deterministic order

The Rust renderer replays the graph. GPU preview consumes the same graph and renders supported nodes interactively.

## 4. Selective Adjustments

Selective adjustments are normal adjustment nodes with a mask.

Initial scope:

- brightness / exposure
- contrast
- saturation
- temperature / tint
- highlights / shadows
- clarity or local contrast later

Data model:

```text
AdjustmentNode
  filter
  value(s)
  maskId
  opacity
```

Rendering:

```text
base pixel
  -> adjusted pixel
  -> mix(base, adjusted, mask * opacity)
```

GPU preview should combine masks and adjustment uniforms without round-tripping image bytes to Rust.

Rust final renderer must use the same normalized mask coordinates and blend semantics.

## 5. Masks

Implement masks before advanced selective tools because they become shared infrastructure for adjustments, Film Profiles, blur, sharpening, and future AI selections.

### Phase M1

- Brush mask
- Erase brush
- Invert mask
- Feather
- Opacity
- Show mask overlay

### Phase M2

- Linear gradient
- Radial gradient
- Luminance range
- Color range

### Representation

Use normalized document coordinates for vector mask instructions. For interactive rendering, rasterize masks to a preview-size single-channel texture. Rust rasterizes the same mask instructions at final resolution.

Do not store a full-resolution mask bitmap for every edit unless required; keep vector/stroke commands as source of truth.

Example:

```json
{
  "id": "mask-1",
  "type": "brush",
  "feather": 0.3,
  "strokes": [
    {
      "points": [[0.2, 0.4, 0.7], [0.21, 0.41, 0.72]],
      "radius": 0.04,
      "flow": 0.8,
      "mode": "add"
    }
  ]
}
```

The third point component can later carry pressure where supported.

## 6. Text and Stickers

Treat Text/Stickers as overlay nodes rather than destructive raster edits.

```text
OverlayNode
  id
  type: text | sticker | image
  transform
  opacity
  blendMode
  zIndex
```

### Text

Store semantic text data:

- text string
- font family reference
- font size relative to document
- color/gradient
- alignment
- weight/style
- outline
- shadow
- transform

GPU/Flutter preview can use platform text rendering initially. Rust final rendering must eventually use a deterministic font/raster pipeline for export parity. Font licensing and font-file packaging must be explicit.

### Stickers

Store the source asset plus transform and style. Use document-relative coordinates so overlays survive resize and orientation changes.

## 7. Preset Import / Export

Presets should be a subset of the edit graph, not serialized UI state.

Suggested extension:

```text
.pixelcraft-preset.json
```

Preset includes:

- schema version
- name / description
- compatible Pixel Craft version range if required
- edit nodes and parameters
- optional Film Profile references
- optional transferable gradient/range masks
- no source image
- brush masks excluded by default because they are image-specific

Import must validate all node types and parameter ranges before applying.

Unknown future nodes should be rejected or ignored according to an explicit compatibility policy; never silently reinterpret them.

## 8. Batch Processing

Batch processing should run entirely through the Rust final renderer and recipe model.

```text
N input files
   + preset/edit recipe
       -> bounded worker queue
       -> Rust decode
       -> recipe replay
       -> encode
       -> output report
```

Requirements:

- configurable output format / quality
- preserve source file names with suffix/template
- bounded concurrency based on memory, not CPU count alone
- cancel support
- per-item progress/result/error
- never hold all decoded full-resolution images in memory simultaneously
- Film LUTs cached once per worker process

Initial mobile target: sequential or concurrency 2. Desktop can scale later.

## 9. GPU Shader Preview for the Editor

The Camera GPU path and Editor GPU path should share effect semantics, but they do not have to share the exact platform rendering widget.

### Preview pipeline

```text
Source preview texture
  -> geometry transform
  -> global adjustments
  -> Film LUT
  -> selective adjustment passes + mask textures
  -> overlays
  -> display
```

Start with one or a few fused shader passes for common operations rather than one framebuffer pass per edit node.

### GPU-supported first

1. exposure / brightness
2. contrast
3. saturation
4. Film LUT
5. temperature / tint
6. masks + local mix
7. crop/rotate/flip geometry

Blur/sharpen can remain Rust-preview-backed until a dedicated separable GPU implementation is added.

### Fallback policy

If the graph contains an operation not supported by GPU preview:

- never silently drop the operation;
- request a Rust preview checkpoint for the unsupported section;
- continue GPU rendering from that checkpoint where practical.

This allows incremental migration without blocking new editor features.

## 10. Rust Final Render

Rust remains authoritative for:

- recipe validation
- source decode + EXIF normalization
- full-resolution edit replay
- precise 33³ LUT processing
- masks at final resolution
- overlay compositing when deterministic support is ready
- export encoding
- batch processing
- session persistence compatibility

The final renderer should accept a complete document recipe rather than depend on transient UI/controller state.

Long-term API shape:

```text
load_document(source)
set_recipe(recipe_json)
render_preview(max_edge)
render_final(format, quality)
render_batch(inputs, recipe, options)
```

## 11. Recommended Delivery Order

### Phase G0 — Architecture preparation

- Keep Rust Film LUT as source of truth.
- Extract camera preview renderer behind a backend contract.
- Define generated GPU LUT atlas format.
- Version the edit recipe/document schema.
- Add preview parity fixtures.

### Phase G1 — Camera real GPU LUT

- Android native GPU LUT viewfinder first.
- Reference-device benchmark.
- iOS implementation.
- Remove matrix backend only after both platforms are stable; retain it as a debug/fallback backend if useful.

### Phase G2 — Editor GPU global preview

- Image texture + global adjustments + Film LUT.
- GPU/Rust parity tests.
- Eliminate Rust round trips during slider movement for supported operations.
- Rust still renders Apply/export.

### Phase M — Masks + Selective

- mask document model
- brush/erase/feather
- GPU mask texture
- selective global adjustments
- Rust final mask rasterizer

### Phase O — Text/Stickers

- overlay graph
- transforms and z-order
- preview rendering
- deterministic final render

### Phase P — Presets

- versioned preset schema
- import/export UI
- compatibility validation
- share preset file

### Phase B — Batch

- Rust headless recipe replay
- bounded queue
- progress/cancel
- output naming and report

## 12. Branch Strategy

Keep the current branch focused on Camera Film Preview.

Recommended follow-up branches after it merges:

```text
feature/gpu-preview-core
feature/editor-gpu-preview
feature/masks
feature/selective-adjustments
feature/text-stickers
feature/preset-io
feature/batch-processing
```

`feature/gpu-preview-core` should introduce shared LUT packaging, operation semantics, and renderer contracts before Editor GPU work begins.

## 13. Performance Budgets

Camera:

- target 60 fps on capable devices
- hard minimum 30 fps
- profile switch visible within 50 ms
- no frame-size buffers through Dart per frame

Editor interaction:

- slider response < 16 ms target / < 33 ms acceptable
- mask brush visual latency < 33 ms
- preview texture normally <= 2048 px longest edge

Final render:

- no UI-thread work
- bounded memory
- deterministic result independent of preview backend

## 14. Testing Strategy

- Unit tests for recipe schema and migration.
- LUT atlas generation tests against Rust LUT values.
- GPU-vs-Rust parity fixtures using representative color charts and photos.
- Mask raster parity tests.
- Golden tests remain UI-layout tests, not shader pixel-accuracy tests.
- Device integration tests for Camera lifecycle/orientation.
- Performance tests on reference Android hardware and at least one iPhone.

For GPU parity tests, compare rendered fixture images with a documented tolerance because GPU texture precision and color management can differ slightly from CPU float rendering.

## 15. Definition of Done for the New Rendering Architecture

The migration is complete when:

- Camera Film preview uses real LUT data on GPU.
- Editor adjustments and Film Profiles preview without Rust byte round trips during interaction.
- One versioned edit graph drives Preview, Final Render, Resume, Presets, and Batch.
- Masks and overlays are non-destructive nodes.
- Rust can reproduce the complete document at full resolution without depending on the GPU preview implementation.
