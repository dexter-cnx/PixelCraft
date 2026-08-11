# Editor Draft Composition Contract

## Principle

Changing editor tools does not implicitly apply or discard edits.

Until the user presses the editor-level **Apply**, PixelCraft maintains one composable draft session on top of the current Rust checkpoint. Rust remains authoritative for the recipe and rendered result.

## Draft slots

### Adjust

Core adjustments are independent parameter slots and may coexist:

- brightness
- contrast
- saturation
- gaussian blur
- sharpen

Each adjustment name may appear at most once in the active draft. Revisiting a control replaces its value in the existing slot rather than stacking another copy of the same adjustment.

Example:

```text
Brightness 1.20
Contrast 1.35
Brightness 1.40
```

Active draft:

```text
Brightness 1.40
Contrast 1.35
```

### Creative Filter

Creative presets are mutually exclusive and share one active draft slot.

Selecting a different preset replaces the current creative slot while preserving the slot's position in the recipe. UI memory may retain the last intensity used for each preset so returning to a previously visited preset restores its previous control value.

Example:

```text
Vintage 0.60
Brightness 1.20
Oceanic 0.80
```

Active draft:

```text
Oceanic 0.80
Brightness 1.20
```

### Film

Film profiles are mutually exclusive and share one active draft slot.

Changing Film profile replaces the existing Film slot even when Adjust or Creative nodes were added after it. UI memory may retain the last strength used for each profile.

Example:

```text
Velvia 0.70
Brightness 1.20
Vintage 0.60
Provia 0.85
```

Active draft:

```text
Provia 0.85
Brightness 1.20
Vintage 0.60
```

## Cross-tool composition

Film and Creative are different slots and therefore may coexist. Adjust slots may coexist with both.

The following is valid without an intermediate Apply:

```text
Brightness 1.20
Contrast 1.35
Velvia 0.70
Vintage 0.60
```

Switching between Adjust, Filters, Film, Crop, Rotate, or Details must not itself clear these draft values.

## Apply and Cancel

Editor-level **Apply** promotes the entire active draft to a new checkpoint. A new draft then starts with neutral controls.

Editor-level **Cancel** discards the active draft back to the checkpoint and resets draft controls.

Tool switching is neither Apply nor Cancel.

## Transform distinction

Crop keeps its uncommitted interactive rectangle when switching tools as long as source geometry has not changed. `Apply Crop` converts that rectangle to an authoritative Rust Crop operation inside the current draft.

Rotate 90 and Flip are discrete commands and each invocation is a real operation.

Straighten currently commits a Rust `RotateDegrees` operation when the gesture ends. Its transient compositor angle must not simply be restored as a visual rotation after commit because that would rotate the already-rotated Rust preview twice. Editable straighten-slot semantics require a separate control-value vs live-preview-angle model.

## Recipe invariants before Apply

Within the active checkpoint range:

- at most one Filter operation for each core adjustment name,
- at most one creative Photon Filter operation,
- at most one FilmProfile operation,
- Film and Creative may coexist,
- core adjustments may coexist with Film and Creative,
- editing an existing slot preserves its recipe position,
- Rust recipe/render/export remains authoritative.
