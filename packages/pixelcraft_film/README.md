# pixelcraft_film

Film Profile library and import orchestration for PixelCraft.

`pixelcraft_film` sits above `pixelcraft_editing`: it coordinates reusable Film Profile workflows while keeping image-processing semantics and LUT authority in Rust.

## Owns

- `FilmProfileRepository` contract
- `FilmProfileLibrary` orchestration
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

## Dependency direction

```text
PixelCraft app
   ├── pixelcraft_film
   ├── pixelcraft_gpu
   └── pixelcraft_engine

pixelcraft_film
   └── pixelcraft_editing

pixelcraft_editing
   └── Dart SDK only
```

`pixelcraft_film` must not import PixelCraft app source, `pixelcraft_gpu`, or `pixelcraft_engine`.

## Why P3 extracts this

Before P3, `FilmProfilesScreen` performed product/domain orchestration directly:

```text
paste JSON
 -> detect PixelCraft profile vs generic recipe
 -> map recipe fields
 -> create imported profile
 -> persist
 -> display mapping report
```

P3 moves parsing and library rules behind package APIs so UI only gathers input, invokes the library, and renders the result.

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

## Validation

```bash
cd packages/pixelcraft_film
dart pub get
dart analyze
dart test
```

See [`CODE_WALKTHROUGH.md`](CODE_WALKTHROUGH.md) for the detailed data flow.
