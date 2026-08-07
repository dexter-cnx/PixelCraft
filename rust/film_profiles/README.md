# Pixel Craft Film Profile Pack v2

Film Profile Pack v2 uses real `33 x 33 x 33` 3D LUTs (`35,937` RGB samples per profile) with trilinear interpolation in the Rust engine.

Each profile is authored from small, reviewable source files:

```text
<profile-id>/
  profile.json   # product metadata / pack contract
  look.json      # LUT authoring recipe
  lut.cube       # materialized 33^3 LUT (generated on demand)
```

The runtime does **not** evaluate the authoring recipe per pixel. `rust/build.rs` deterministically compiles every `look.json` into a full 33^3 `.cube` file under Cargo `OUT_DIR`, then `film_profiles.rs` embeds that generated LUT. Interactive preview and full-resolution export therefore run only LUT lookup + trilinear interpolation + strength blending.

The initial Pack v2 contains:

- `provia_inspired` — balanced memory-color / transparency style
- `velvia_inspired` — vivid color, deeper contrast for landscapes
- `astia_inspired` — softer portrait tonality and smoother highlights
- `e100_inspired` — neutral transparency style with moderate saturation
- `ektar_inspired` — high-saturation color-negative style
- `chrome64_inspired` — warm nostalgic chrome style

These are Pixel Craft interpretations. They are not manufacturer LUTs, vendor color-science data, or 1:1 emulations.

## `profile.json`

Example:

```json
{
  "id": "provia_inspired",
  "name": "Provia Inspired",
  "description": "Balanced slide-film color.",
  "lut": "lut.cube",
  "lutSize": 33,
  "packVersion": 2,
  "defaultStrength": 1.0
}
```

The Rust loader validates:

- `packVersion == 2`
- `lutSize == 33`
- `lut == "lut.cube"`
- `defaultStrength` is between `0` and `1`
- the generated `.cube` contains exactly `33^3 = 35,937` RGB samples

## `look.json`

`look.json` is an authoring recipe used only by the build-time LUT compiler. It can describe:

- global contrast
- black lift
- toe and highlight shoulder
- global saturation
- 3x3 color matrix
- per-channel gamma
- shadow/highlight tint
- hue-selective saturation/value/hue shifts

The build step samples that transform over the complete 33^3 RGB lattice and produces a standard `.cube` LUT in red-fastest ordering.

## Materialize the actual `.cube` files

Normal Rust/Flutter builds generate LUTs into Cargo `OUT_DIR` automatically. To also write inspectable `.cube` files into these profile folders, run:

```bash
make film-luts
```

The target verifies every generated file contains:

```text
LUT_3D_SIZE 33
35,937 RGB samples
```

After reviewing a LUT change you may commit the materialized `lut.cube` files if you want the exact generated tables versioned in Git. They are reproducible from `profile.json` + `look.json`.

## Runtime `.cube` support

The parser supports:

- `TITLE`
- `LUT_3D_SIZE`
- `DOMAIN_MIN`
- `DOMAIN_MAX`

1D LUTs are intentionally rejected. Runtime sampling uses trilinear interpolation and preserves the existing semantic operation:

```text
FilmProfile { id, strength }
```

That means session recovery, Apply checkpoints and full-resolution export continue to use the same recipe schema while the underlying color science can evolve independently.
