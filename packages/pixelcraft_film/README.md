# pixelcraft_film

Film Profile product/domain orchestration for PixelCraft.

`pixelcraft_film` sits above `pixelcraft_editing`: it coordinates reusable Film Profile creation, library, duplication, import, creator-draft, and library-query workflows while keeping image-processing semantics and LUT authority in Rust.

P3 is merged. The package is now part of the canonical post-P3 application graph.

## Owns

- `FilmProfileRepository` persistence contract
- `FilmProfileLibrary` use-case orchestration
- `FilmProfileDraft` creation/edit composition state
- `FilmProfileQuery` pure-Dart library search/origin filtering
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
- Editor history/checkpoints/recovery
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

## Why this package exists

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

P3 moved those rules behind package APIs so widgets collect/display values while the package owns reusable Film Profile behavior.

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

Parameter clamp/reset behavior delegates to semantic parameter specs owned by `pixelcraft_editing`. Neutral values are normalized by `FilmProfileV1` when the final profile is built.

Time-based ID generation remains outside the package so package behavior stays deterministic and testable.

## Library query contract

`FilmProfileQuery` keeps reusable library filtering outside Flutter widgets.

- text matching is case-insensitive;
- matches profile name, description, base-Film id, and tags;
- optional origin filtering uses `FilmProfileOrigin`;
- an empty origin set means all origins;
- repository order is preserved.

The app remains responsible for SearchBar/ChoiceChip presentation state.

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

Applying a profile follows:

```text
Film Profile configuration
 -> deterministic Dart recipe shaping
 -> restore/commit through Rust
 -> Rust-authoritative preview/history/checkpoint/export
```

Canonical Film LUT data remains Rust-owned. `pixelcraft_film` coordinates configuration/product workflows only.

## Validation

Package-local validation:

```bash
cd packages/pixelcraft_film
dart pub get
dart analyze
dart test
```

Root CI also runs package-boundary guards and the full Flutter/Rust/GPU/native packaging suite.

The final G7A PR head passed Film package dependencies, analyze, and tests as part of full CI run #221 (`31611799174`):

```text
HEAD: d5e0aab14a0ae9a5b8124a0b37fef78249cbbeb5
conclusion: SUCCESS
```

See [`CODE_WALKTHROUGH.md`](CODE_WALKTHROUGH.md) for the detailed data flow.
