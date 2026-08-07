# Pixel Craft film profile files

Each bundled film profile lives in its own directory and contains two source files:

```text
<profile-id>/
  profile.json
  lut.cube
```

`profile.json` owns product-facing metadata and the default strength. `lut.cube` owns the color transform. The Rust engine parses both once through a lazy cache and applies the 3D LUT with trilinear interpolation for preview and full-resolution export.

Example metadata:

```json
{
  "id": "provia_inspired",
  "name": "Provia Inspired",
  "description": "Balanced slide-film color.",
  "lut": "lut.cube",
  "defaultStrength": 1.0
}
```

Supported `.cube` directives are `TITLE`, `LUT_3D_SIZE`, `DOMAIN_MIN`, and `DOMAIN_MAX`. 1D LUTs are intentionally rejected. Pixel Craft stores samples in red-fastest order and validates that the file contains exactly `size^3` RGB triplets.

The current profiles are bundled with `include_str!`, so changing or adding a profile requires rebuilding the Rust library but does not require changing the processing algorithm. A future external-profile importer can reuse the same parser and validation path.

The supplied profiles are simulations inspired by film characteristics; they are not manufacturer color-science data.
