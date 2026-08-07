# Pixel Craft Performance & Memory Profiling

Pixel Craft intentionally separates interactive preview work from full-resolution export work.

## Performance model

```text
Original full-resolution source
        ↓
1024 px bounded editor preview
        ↓
Adjust / Filters / Film / transforms
        ↓
semantic EditOperation recipe
        ↓
Apply = promote reduced checkpoint only
        ↓
Export = replay complete recipe on full-resolution source
```

This keeps interaction latency proportional to the editor preview size rather than the camera/gallery image resolution.

## Device profiling command

Run on a real Android/iOS device:

```bash
make profile-native DEVICE=<device-id>
```

For the current Android development device, for example:

```bash
make profile-native DEVICE=RF8Y909V0LV
```

The integration scenario prints machine-readable lines such as:

```text
PIXELCRAFT_PROFILE load_preview_ms=...
PIXELCRAFT_PROFILE film_thumbnails_ms=...
PIXELCRAFT_PROFILE film_preview_ms=...
PIXELCRAFT_PROFILE apply_checkpoint_ms=...
PIXELCRAFT_PROFILE export_full_ms=...
PIXELCRAFT_PROFILE total_ms=...
PIXELCRAFT_MEMORY rss_start=...
PIXELCRAFT_MEMORY rss_after_load=...
PIXELCRAFT_MEMORY rss_after_thumbnails=...
PIXELCRAFT_MEMORY rss_after_profile=...
PIXELCRAFT_MEMORY rss_end=...
PIXELCRAFT_MEMORY rss_peak_delta=...
```

`rss_peak_delta` is an observational process-RSS delta, not a hard CI threshold. Different Android/iOS versions, allocator behavior, debug/release builds and image sizes produce different values.

## What to compare

For each optimization, record at least:

- device model and OS version
- debug/profile/release mode
- source image dimensions and encoded size
- `load_preview_ms`
- Film preview processing latency
- Apply checkpoint latency
- full-resolution export latency
- peak RSS delta

Do not compare a debug build on one device against a release build on another as if the numbers were equivalent.

## Target behavior

Interactive operations should stay bounded by the 1024 px working image. Apply should remain substantially cheaper than Export because Apply does not decode and process the full-resolution source. Export is expected to be the expensive stage.

Film Profile pixel transforms use Rayon across the RGBA buffer. Film thumbnail variants are also generated in parallel from one reduced base image.

## Memory guidance

The engine intentionally keeps:

1. the compressed original source bytes,
2. one reduced checkpoint image,
3. current reduced preview/output buffers,
4. small filter/Film thumbnail buffers,
5. the semantic operation recipe.

Session recovery stores the full source once per image and rewrites only the small JSON recipe during normal edits. This avoids repeatedly writing large source images while the user adjusts controls.

## Future profiling work

Before adding live camera Film previews, establish a stable baseline for 12 MP, 24 MP and 48 MP sources. Camera work should use a separate frame-time benchmark because throughput/latency requirements differ from still-image editing.
