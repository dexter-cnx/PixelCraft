# pixelcraft_film

Film Profile product/domain orchestration for PixelCraft.

`pixelcraft_film` sits above `pixelcraft_editing`: it coordinates reusable Film Profile creation, library, duplication and import workflows while keeping image-processing semantics and LUT authority in Rust.

## Owns

- `FilmProfileRepository` persistence contract
- `FilmProfileLibrary` use-case orchestration
- `FilmProfileDraft` creation/edit composition state
- PixelCraft profile JSON vs generic recipe import classification
- propagation of exact / approximated / unsupported mapping reports
- duplicate / save / delete product rules for reusable Film Profiles

## Does not own

- LUT pixels or canonical Film LUT data
- Rust filter semantics
- final rendering/export
- GPU preview backends
- Flutter UI/navigation
- filesystem or `path_provider` storage implementation
- editor history/checkpoints/recovery
- base-Film discovery from the Rust LUT catalog

## Dependency direction

```text
PixelCraft app
   ├── pixelcraft_film
   ├── pixelcraft_gpu
   ├── pixelcraft_engine
   └── pixelcraft_editing

pixelcraft_film
   └── pixelcraft_editing

pixelcraft_editing
   └── Dart SDK only
```

`pixelcraft_film` must not import PixelCraft app source, `pixelcraft_gpu`, `pixelcraft_engine`, Flutter, `path_provider`, or `dart:io`.

## Why P3 extracts this

Before P3, Film screens performed reusable product/domain orchestration directly:

```text
Creator UI
 -> initialize every parameter/default
 -> mutate/reset parameter values
 -> normalize name/tags
 -> build FilmProfileV1
 -> save

Library UI
 -> detect PixelCraft profile vs generic recipe
 -> map recipe fields
 -> create imported profile
 -> persist
 -> display mapping report
```

P3 moves those rules behind package APIs so widgets collect/display values while the package owns reusable Film Profile behavior.

## Draft contract

`FilmProfileDraft` provides pure-Dart creation/edit state:

```text
FilmProfileV1? existing profile
        ↓
FilmProfileDraft.fromProfile
        ↓
semantic neutral defaults for all profile parameters
        ↓
withParameter / resetParameter / copyWith
        ↓
toProfile(newId: ...)
        ↓
FilmProfileV1
```

Parameter clamp/reset behavior delegates to the semantic parameter specs owned by `pixelcraft_editing`. Neutral values are normalized by `FilmProfileV1` when the final profile is built.

Time-based ID generation remains outside the package so package behavior stays deterministic and testable.

## Persistence

The current filesystem adapter remains app-owned:

```text
lib/core/film_profile_store.dart
```

It implements `FilmProfileRepository` and continues to use `path_provider` plus atomic file replacement. Keeping it outside this package preserves a pure-Dart package boundary and leaves platform storage policy replaceable.

## Import contract

`FilmProfileImportService.parse()` returns:

```text
FilmProfileImportResult
  profile
  sourceKind
  optional FilmProfileImportReport
```

For native PixelCraft profile JSON, the decoded profile is marked `imported`.

For generic recipe JSON, `pixelcraft_editing.importRecipeMap()` remains the semantic mapping authority and reports every mapped field as exact, approximated, or unsupported.

Unsupported fields are never silently discarded from the report.

## Rust authority

This package does not make an imported or user-created Film Profile authoritative image state.

Applying a profile still follows the existing path:

```text
Film Profile configuration
 -> deterministic Dart recipe shaping
 -> restore/commit through Rust
 -> Rust-authoritative preview/history/checkpoint/export
```

Canonical Film LUT data remains Rust-owned. `pixelcraft_film` coordinates configuration/product workflows only.

## Validation

```bash
cd packages/pixelcraft_film
dart pub get
dart analyze
dart test
```

Root CI also runs package-boundary guards and the full Flutter/Rust/GPU/native packaging suite.

See [`CODE_WALKTHROUGH.md`](CODE_WALKTHROUGH.md) for the detailed data flow.
