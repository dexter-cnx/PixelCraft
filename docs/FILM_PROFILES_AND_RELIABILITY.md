# Film Profiles, Async Preview, Recovery and Reliability

This document describes the reliability work introduced with `feature/film-profiles`.

## Scope

The branch adds six related capabilities:

1. async editor previews with latest-request-wins semantics,
2. recoverable editor sessions,
3. CI validation for Flutter, Rust and generated FRB code,
4. tablet, dark-mode and accessibility golden coverage,
5. on-device performance and memory profiling,
6. an extensible Film Profile operation family.

## Async preview + latest-request-wins

Adjust, creative Filter and Film strength changes are editor-preview requests rather than full-resolution jobs. The UI records the newest requested value immediately and a single preview worker serializes Rust state mutations.

```text
slider release / profile tap
        ↓
assign monotonically increasing request id
        ↓
replace queued-but-not-started request with newest request
        ↓
run one Rust mutation at a time
        ↓
if result.requestId != latestRequestId
    keep Rust state, but do not project stale pixels to Flutter
        ↓
run newest queued request
```

This avoids an unbounded queue when a user rapidly changes values. Rust engine state still changes serially, which is required because the editor operation list is stateful, but stale results never flash on screen.

The tool panel exposes a lightweight `Updating preview…` progress line instead of blocking the whole editor. Apply, Cancel, Undo, Redo and Export wait until the current preview queue settles.

### Replacement safety

Filter/Film edits are replaceable only when the immediately previous draft operation is from the same operation family. A sequence such as:

```text
Contrast -> Provia Inspired -> Brightness
```

must remain three semantic operations. Changing Brightness again may replace only that last Brightness operation. It must not remove the Film operation between the two Filter operations.

## Film Profiles

Film Profiles remain a first-class Rust operation:

```rust
EditOperation::FilmProfile {
    id,
    strength,
}
```

### Film Profile Pack v2

Pack v2 upgrades the initial bootstrap LUTs to real `33 x 33 x 33` 3D LUTs. Each LUT contains `35,937` RGB samples and is evaluated at runtime with trilinear interpolation.

Each bundled profile has small authoring files:

```text
rust/film_profiles/<profile-id>/
  profile.json
  look.json
  lut.cube   # generated/materialized 33^3 table
```

`profile.json` owns the product-facing contract: id, display name, description, LUT size, pack version and default strength. `look.json` is the reviewable authoring recipe used by the build-time LUT compiler. It describes global tone, matrix/gamma color response, shadow/highlight tint and hue-selective adjustments.

`rust/build.rs` samples the complete RGB lattice and deterministically generates the actual 33^3 `.cube` tables into Cargo `OUT_DIR`. `film_profiles.rs` embeds those generated files, parses them once through a lazy cache and validates that each profile really contains 33^3 samples. The authoring recipe is therefore not evaluated per image pixel.

The Pack v2 registry contains:

- Provia Inspired
- Velvia Inspired
- Astia Inspired
- E100 Inspired
- Ektar Inspired
- Chrome 64 Inspired

The looks are Pixel Craft interpretations guided by broad published characteristics such as neutral/versatile PROVIA, vivid/high-contrast Velvia, softer portrait-oriented ASTIA, neutral moderately saturated E100, and ultra-vivid Ektar. They are not manufacturer LUTs, vendor color-science replicas, or proprietary formulas.

### Runtime LUT path

```text
profile.json + look.json
        ↓ build time
33^3 lut.cube
        ↓
parse + validate once
        ↓
cached FilmProfileSpec
        ↓
RGB pixel
        ↓
3D LUT trilinear interpolation
        ↓
strength blend with source RGB
```

Supported `.cube` directives are `TITLE`, `LUT_3D_SIZE`, `DOMAIN_MIN`, and `DOMAIN_MAX`. 1D LUTs are rejected. The parser verifies that the file contains exactly `size^3` RGB samples and Pack v2 additionally requires `size == 33`.

The RGBA pixel transform remains parallelized with Rayon. Film thumbnail variants are generated in parallel from one reduced source preview. The same LUT-backed `FilmProfile { id, strength }` operation is replayed during full-resolution export, so preview and export use identical LUT data.

To materialize the generated tables into the source profile folders for inspection or versioning:

```bash
make film-luts
```

The target verifies six profiles, `LUT_3D_SIZE 33`, and exactly `35,937` RGB rows in every file.

## Preview vs full resolution

Interactive processing remains bounded to the existing reduced editor checkpoint.

```text
full-resolution source (untouched)
        ↓
1024 px editor checkpoint
        ↓
Film / Adjust / Filter / Transform preview
        ↓
EditOperation recipe
```

Apply promotes the already-rendered reduced image to the next checkpoint. It does not bake Film Profiles at full resolution.

Export remains the intentional full-resolution stage:

```text
untouched full-resolution source
+ complete operation recipe
        ↓
full-resolution replay
        ↓
PNG / JPEG / WebP
```

## Session recovery

The Rust recipe is serializable JSON with a versioned schema containing:

- preview max edge,
- complete operation list,
- absolute cursor,
- Apply checkpoint cursor.

Pixel Craft persists four small session resources in application support storage:

```text
source.bin     original compressed source
source.id      lightweight source fingerprint
recipe.json    versioned semantic edit recipe
metadata.json  save timestamp
```

The full source is rewritten only when the active image changes. Normal edits rewrite only the recipe and metadata. Writes are serialized and committed through temporary files + rename so an interrupted write is less likely to leave a partially written recipe.

The Home screen surfaces `Resume last edit`. Resume reloads the original source into Rust, reconstructs the Apply checkpoint, replays remaining draft operations, then restores the current preview and session cursor.

Session persistence is best-effort: storage errors never interrupt active editing.

## CI

`.github/workflows/ci.yml` validates:

```text
flutter pub get
FRB codegen 2.12.0
verify generated bridge has no diff
cargo fmt --check
cargo clippy -D warnings
cargo test
flutter analyze
state tests
widget tests
golden tests
```

Golden failure artifacts are uploaded when available.

Generated FRB sources remain committed files. Any Rust API change therefore requires local `make codegen` before the branch can pass CI.

## Golden matrix

Golden coverage includes:

- phone/light editor,
- tablet/light editor,
- phone/dark editor,
- phone/accessibility text scale 1.5,
- Film tool on phone,
- export dialog,
- before/original comparison,
- Home screen.

New golden baselines must be generated and visually reviewed with:

```bash
make golden-update
make golden-test
```

Do not treat `--update-goldens` as validation by itself; the generated images must be inspected before commit.

## Performance and memory profiling

`integration_test/performance_profile_test.dart` records on-device timing and RSS observations for:

- loading + 1024 px preview preparation,
- Film thumbnail generation,
- Film preview application,
- Apply checkpoint,
- full-resolution export,
- total flow,
- process RSS at major stages.

Run:

```bash
make profile-native DEVICE=<device-id>
```

The test prints `PIXELCRAFT_PROFILE` and `PIXELCRAFT_MEMORY` lines intended for comparison across commits on the same device/build configuration. There are intentionally no hard latency/RSS assertions because hardware, allocator and debug/release differences make universal thresholds misleading.

## Validation checklist

Before merging this branch:

```bash
flutter pub get
make codegen
make film-luts
cargo fmt --manifest-path rust/Cargo.toml --all
cargo clippy --manifest-path rust/Cargo.toml --all-targets -- -D warnings
cargo test --manifest-path rust/Cargo.toml
flutter analyze
flutter test test/state
flutter test test/ui --exclude-tags=golden
make golden-update
make golden-test
make verify-native
make native-test DEVICE=RF8Y909V0LV
make profile-native DEVICE=RF8Y909V0LV
```

Commit generated FRB sources, `Cargo.lock` if Cargo updates it, reviewed golden PNG baselines, and optionally the materialized 33^3 `.cube` tables before marking the PR ready for review.
