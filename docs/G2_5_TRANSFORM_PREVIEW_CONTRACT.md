# G2.5 Transform Preview Contract

## Status

G2.5a starts with realtime straighten preview on the Flutter compositor around the current editor preview. Rust remains authoritative when the gesture ends.

This is intentionally staged before moving geometry into the Metal vertex shader. It validates UX, clipping and transparent-corner behavior on a physical iOS device without adding duplicate transform state to the native renderer.

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

Centered crop remains a Rust crop operation using normalized coordinates.

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
  -> Editor checkpoint/operation history
  -> straightenDegrees reset to 0
```

Rules:

1. Pixel buffers are not sent over MethodChannel.
2. Export is unaffected and remains Rust full-resolution rendering.
3. Undo/Redo remain Rust-authoritative.
4. The compositor preview is an interactive approximation, not a replacement for the Rust output.
5. Device validation must check clipping, center of rotation, aspect fit, transparent corners and visual handoff after release.

## Next stages

- G2.5b: decide whether quarter-turn/flip need an immediate GPU handoff. These operations are already inexpensive in Rust, so the benefit may not justify additional native state.
- G2.5c: add interactive crop rectangle/handles before implementing a GPU crop preview path.
- If G2.5a compositor behavior is insufficient on iOS Platform Views, move straighten into the Metal vertex/UV transform while preserving the same Rust commit semantics.
