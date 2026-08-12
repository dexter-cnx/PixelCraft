# G5.1 Tone Controls

## Status

G5.1A Rust semantics: **IMPLEMENTED / VERIFICATION REQUIRED**

Branch: `feature/editor-tone-controls`

This milestone starts after the merged G4 product editor workflow. Rust remains authoritative for committed edit semantics, history, checkpoints, recovery recipes and full-resolution export. GPU work is intentionally deferred until the Rust contract is verified.

## Scope

Initial tone controls:

- Exposure
- Highlights
- Shadows

These use the existing `EditOperation::Filter { name, value }` representation so the session-recipe schema does not need a version change for G5.1A.

## Authoritative semantics

### Exposure

Filter name: `exposure`

- Unit: EV
- Neutral: `0.0`
- Supported range: `-2.0 ... +2.0`
- Out-of-range input: clamped
- RGB transform: `channel * 2^EV`
- Output channel range: `0 ... 255`
- Alpha: preserved

The current implementation operates on the decoded RGB channel values used by the existing PixelCraft raster pipeline. This milestone does **not** claim scene-linear or professional colorimetric exposure accuracy.

### Highlights

Filter name: `highlights`

- Neutral: `0.0`
- Supported range: `-1.0 ... +1.0`
- Out-of-range input: clamped
- Selection mask: smooth luminance mask rising from mid-tones toward white
- Positive values: lift selected bright tones toward white
- Negative values: darken selected bright tones
- Alpha: preserved

The authoritative mask is based on PixelCraft's existing Rec.709-style RGB luminance coefficients and a smoothstep range of `0.45 ... 1.0`.

### Shadows

Filter name: `shadows`

- Neutral: `0.0`
- Supported range: `-1.0 ... +1.0`
- Out-of-range input: clamped
- Selection mask: inverse smooth luminance mask falling from black toward mid-tones
- Positive values: lift selected dark tones
- Negative values: deepen selected dark tones
- Alpha: preserved

The authoritative mask uses the inverse of a smoothstep range of `0.0 ... 0.55`.

## Operation / history contract

Because these controls use the existing non-Photon Filter slot semantics:

- each filter name owns one replaceable draft slot per checkpoint
- changing Exposure does not remove Highlights, Shadows or existing Adjust operations
- revisiting the same parameter replaces its current draft value rather than stacking another node
- Apply promotes the current draft through the existing Rust checkpoint contract
- Discard restores the checkpoint through the existing Rust contract
- Undo / Redo remain bounded by the checkpoint rules already established by G2-G4
- full-resolution export replays the same Rust filter operation; GPU pixels are never export input

## Tests added in `rust/src/filters.rs`

- neutral Exposure is a no-op
- positive and negative Exposure move values in the expected direction
- neutral Highlights and Shadows are no-ops
- Highlights affect bright pixels more than dark pixels
- Shadows affect dark pixels more than bright pixels
- all three tone controls preserve alpha

## Required verification before G5.1A closure

Run from a clean checkout of this branch:

```bash
cargo fmt --manifest-path rust/Cargo.toml --all -- --check
cargo clippy --manifest-path rust/Cargo.toml --all-targets -- -D warnings
cargo test --manifest-path rust/Cargo.toml
flutter analyze
make test
```

Do not mark the Rust semantics closed until these gates actually pass.

## Next implementation step — G5.1B

After Rust verification:

1. add Exposure / Highlights / Shadows to the product Adjust/Light UI
2. define slider labels, range mapping and neutral markers
3. integrate with the G4 authoritative recipe-derived changed indicators
4. integrate Reset Parameter / Reset Adjust semantics
5. verify remembered values across tool switching
6. verify History labels and recovery persistence

## GPU rule — G5.1C

Do not add realtime GPU stages until G5.1B uses the verified Rust contract.

If GPU stages are added:

- renderer ordering must exactly preserve Rust operation order
- unsupported order must fail closed to Rust preview
- deterministic Rust-vs-GPU parity fixtures are required
- latency must be measured on a physical device
- Rust remains the full-resolution export authority
