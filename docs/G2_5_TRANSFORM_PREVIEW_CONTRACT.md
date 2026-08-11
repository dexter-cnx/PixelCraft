# G2.5 Transform Preview Contract

## Status

**G2.5 CLOSED on the iOS G2 reference device.**

- G2.5a realtime straighten preview: implemented and functionally validated on the iOS reference device.
- G2.5b quarter-turn/flip GPU handoff: intentionally deferred because the existing Rust operations are inexpensive and do not have a continuous interaction loop.
- G2.5c interactive crop: implemented and functionally validated on device.
- G2.5d cleanup/regression coverage: duplicate crop controls removed; crop geometry tests added; source-pixel aspect handling corrected.

Rust remains authoritative for committed transforms, Undo/Redo and full-resolution export.

## Rust semantics

Authoritative straighten is:

```text
rotate_about_center(
  rgba,
  degrees.to_radians(),
  Interpolation::Bilinear,
  transparent RGBA(0,0,0,0)
)
```

The output keeps the same image dimensions and exposes transparent corners as the source rotates inside those bounds.

Quarter turns and flips remain Rust operations:

- Rotate 90° / 180° / 270°
- Flip horizontal
- Flip vertical

Crop remains the existing Rust normalized operation:

```text
Crop { x, y, width, height }
```

## G2.5a realtime straighten

During slider drag:

```text
EditorState.straightenDegrees
  -> Flutter Transform.rotate
  -> compositor/GPU presentation only
  -> no Rust render per tick
```

On slider release:

```text
commitStraighten(degrees)
  -> Rust rotate_about_center + Bilinear
  -> Editor operation history
  -> straightenDegrees reset to 0
```

The compositor transform is an interactive approximation. The Rust result is authoritative after release.

## G2.5c interactive crop

The crop editor is a UI transaction over the current Rust checkpoint:

```text
Rust preview image
  -> BoxFit.contain image rect
  -> InteractiveCropOverlay
  -> normalized CropDraft
  -> Apply Crop
  -> Rust Crop { x, y, width, height }
  -> authoritative recipe/controller resync
```

During drag/resize there is no Rust render. The UI changes only the normalized crop draft.

Supported modes:

- Free
- 1:1
- 4:3
- 3:4
- 16:9
- 9:16

The crop tool panel no longer exposes a second set of immediate crop actions. Aspect selection, reset and Apply Crop exist only on the interactive canvas so there is one crop transaction path.

## Aspect-ratio contract

Crop coordinates are normalized, but aspect ratios are defined in source-pixel space.

For a source image with aspect `sourceWidth / sourceHeight`:

```text
pixelCropAspect
  = (normalizedWidth / normalizedHeight)
    * sourceImageAspect
```

Therefore a target aspect ratio must be converted before constraining a normalized crop rectangle:

```text
normalizedRatio = targetPixelAspect / sourceImageAspect
```

This matters for non-square images. For example, a 1:1 crop on a 4:3 source is not `width=1,height=1`; it is a centered normalized rectangle with `width=0.75,height=1.0`.

The same conversion is used both when creating an aspect preset and while resizing a locked crop rectangle.

## Runtime rules

1. Pixel buffers are not sent over MethodChannel for transform interaction.
2. Straighten drag and crop drag/resize do not render through Rust per gesture tick.
3. Apply Crop is the only interactive-crop action that commits to Rust.
4. Leaving Crop mode discards the uncommitted CropDraft.
5. A new preview image resets the CropDraft.
6. Undo/Redo, Apply/Cancel checkpoint semantics and export remain Rust-authoritative.
7. Crop bounds stay inside normalized `[0,1]` and maintain a minimum interactive size.
8. Crop aspect locking is evaluated in source-pixel space, not normalized-square space.

## Regression coverage

`test/ui/widgets/interactive_crop_overlay_test.dart` covers:

- centered aspect presets
- target aspect mapping for a non-square source
- normalized drag movement
- movement clamping to image bounds
- locked-aspect resize in source-pixel space

## G2.5 closure evidence

- Interactive crop and realtime straighten were functionally validated on the physical iOS reference device: **PASS**.
- 1:1 and 16:9 crop behavior on non-square source geometry was validated after the source-pixel aspect correction: **PASS**.
- Duplicate crop commit controls were removed: **PASS**.
- Undo/Redo/Apply/Cancel remain on the Rust-authoritative editor path: **PRESERVED**.
- Host regression commands are included in the final G2 merge gate: see `docs/G2_FINAL_VERIFICATION.md`.
