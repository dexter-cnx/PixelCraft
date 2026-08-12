# G5 — Editing Feature Completeness

## Status

G5.1-G5.7 implementation is **INTEGRATED / VERIFICATION IN PROGRESS** on:

```text
feature/editor-tone-controls
PR #8
```

Do not mark G5 CLOSED until the latest host CI and the required product/device smoke pass.

## Architectural invariants

1. Rust remains authoritative for semantic edits, recipe/history/checkpoints and full-resolution export.
2. Flutter owns product/presentation state and reusable Film Profile data.
3. GPU remains preview-only. Unsupported G5 operations/order fall back to the valid Rust preview.
4. New scalar edits continue to use `EditOperation::Filter`; the session recipe schema does not need a G5 bump.
5. User Film Profiles are data/configuration, never compiled shader code.
6. Import never silently discards unsupported recipe fields.

---

## G5.1 — Tone Controls

Implemented Rust-authoritative controls:

| Control | Range | Neutral | Semantics |
|---|---:|---:|---|
| Exposure | -2…+2 EV | 0 | RGB gain `2^EV` |
| Highlights | -1…+1 | 0 | smooth luminance-weighted highlight adjustment |
| Shadows | -1…+1 | 0 | smooth luminance-weighted shadow adjustment |

Existing Brightness / Contrast / Saturation / Sharpen / Gaussian Blur remain supported.

Flutter now uses one adjustment catalog for range, neutral value, grouping and GPU eligibility. This also corrects Sharpen neutral semantics to `0.0`, matching the Rust kernel.

New G5 controls currently commit through Rust on slider release unless a verified GPU implementation exists. This is deliberate fail-closed behavior, not a silent approximation.

---

## G5.2 — White Balance / Color

Implemented:

- Temperature `[-1,+1]`
- Tint `[-1,+1]`
- Vibrance `[-1,+1]`

The current V1 implementation operates on decoded RGB pixels. It is a deterministic creative-edit contract; PixelCraft does **not** claim camera-raw white-balance reconstruction or professional colorimetric accuracy from this implementation.

Camera input WB, per-image Temperature/Tint edits and reusable Film Profile color bias remain distinct concepts.

---

## G5.3 — Finish / Texture

Implemented:

- Vignette `[-1,+1]`
- Grain `[0,1]`

Grain is deterministic. It uses a stable coordinate hash so recipe replay, recovery and full-resolution Rust export do not depend on hidden RNG state.

G5 V1 exposes Grain amount only. Grain size/roughness/film-stock response remain future extensions.

---

## G5.4 — Film Profile Foundation

Added vendor-neutral `FilmProfileV1` with:

- explicit schema name/version
- explicit minimum engine version
- id / name / description / tags
- origin: built-in / user / imported
- optional built-in Base Film + strength
- normalized semantic parameter map
- immutable built-in policy; duplicate to edit
- local JSON persistence

Reusable profile data intentionally excludes:

- crop
- rotation
- source-image identity
- editor history/checkpoints
- captured GPU pixels

A profile can be materialized into the active Rust session recipe as Base Film + semantic Filter operations. The resulting recipe is restored through Rust before it becomes editor state.

---

## G5.5 — Film Profile Creator V1

Implemented creator workflow:

```text
Create Film
  -> name / description / tags
  -> optional Base Film + strength
  -> Tone
  -> Color
  -> Texture
  -> Curve
  -> HSL
  -> Save Film
```

The control catalog is shared with profile serialization so UI ranges and persisted values cannot drift independently.

Profiles can be duplicated and edited without mutating built-ins.

---

## G5.6 — Recipe Import / Export Compatibility

PixelCraft Profile payload:

```text
schema: pixelcraft-film-profile
schemaVersion: 1
minEngineVersion: 1
```

The JSON payload is suitable for a future `.pixelcraftprofile` file wrapper. The current product workflow supports copy/paste JSON import/export.

Generic recipe import classifies every source field as:

```text
exact
approximated
unsupported
```

Unsupported fields remain visible in the import report and are never silently discarded.

Examples of approximation include vendor-specific highlight/shadow tone or WB-shift concepts where PixelCraft cannot claim 1:1 reproduction of a proprietary processing pipeline.

---

## G5.7 — Advanced Film Lab V1

Implemented deterministic Rust operations for:

### Parametric curve zones

- Curve Shadows
- Curve Midtones
- Curve Highlights

This is intentionally a three-zone parametric curve for V1, not an arbitrary point-curve editor.

### HSL Color Mixer

Six explicit hue sectors:

```text
Red      0°
Yellow  60°
Green  120°
Cyan   180°
Blue   240°
Magenta 300°
```

Each sector exposes:

```text
Hue
Saturation
Luminance
```

Hue-sector influence is blended by angular distance rather than hard-cut boundaries.

Advanced Film Lab controls are available to Film Profile creation and serialize as normal semantic filter operations, so replay/export remain Rust-authoritative.

---

# Verification gates

## Automated host gate

Required before closure:

```text
cargo fmt --check
cargo clippy -D warnings
cargo test
flutter analyze
flutter test test/state
flutter test test/gpu
flutter test test/ui --exclude-tags=golden
flutter test test/golden
make gpu-lut-verify
```

Record only actual results from CI/local verification; do not infer PASS.

## Required product/device smoke

### G5.1-G5.3

- [ ] Exposure direction and neutral reset
- [ ] Highlights selectivity
- [ ] Shadows selectivity
- [ ] Temperature warm/cool direction
- [ ] Tint green/magenta direction
- [ ] Vibrance behavior on low/high saturation content
- [ ] Vignette edge behavior
- [ ] Grain repeatability after reopen
- [ ] Apply / Discard / Undo / Redo across new controls
- [ ] full-resolution Rust export matches committed semantics

### G5.4-G5.6

- [ ] create custom Film Profile
- [ ] duplicate profile
- [ ] edit/save profile
- [ ] load profile into active editor draft
- [ ] Base Film + semantic parameters survive recovery
- [ ] copy/export profile JSON
- [ ] import native PixelCraft profile
- [ ] generic recipe import reports exact/approx/unsupported mappings
- [ ] unsupported input is never silently dropped

### G5.7

- [ ] Curve Shadows/Midtones/Highlights direction
- [ ] HSL each sector targets expected colors
- [ ] neutral Advanced Film Lab controls are no-ops
- [ ] Advanced Film Lab profile survives save/reload
- [ ] full-resolution export replays Advanced Film Lab semantics

## GPU note

The established G3 render plan only implements verified GPU stages. New G5 filters are allowed to remain Rust-preview-on-release until a matching native implementation has numeric parity and latency evidence. Adding a visually similar shader without parity would violate the project authority contract.

---

# Exit definition

G5 can be marked CLOSED when:

1. G5.1-G5.7 host gates are green.
2. Required product/device smoke is recorded.
3. Custom Film Profiles can be created, persisted, imported/exported and materialized into Rust-authoritative editor recipes.
4. Export remains full-resolution Rust replay.
5. Unsupported GPU composition continues to fail closed.
