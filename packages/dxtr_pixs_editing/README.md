# pixelcraft_editing

Pure editing-domain contracts and serialization models for PixelCraft.

`pixelcraft_editing` removes reusable editing models from the application layer so internal packages can share them without importing `package:pixelcraft/...` app source.

> Rust remains authoritative for committed edit semantics, recipe/history/checkpoint state, recovery, and full-resolution export. This Dart package defines domain/transport contracts and deterministic recipe-shaping helpers; it does not replace Rust authority.

## Owns

### Edit graph

- `EditGraphDocument`
- `EditGraphNode`
- `EditNodeType`
- `EditMask`
- `EditOverlay`
- edit-graph schema versioning and JSON validation

### Adjustment semantics

- `EditorAdjustmentSpec`
- `editorAdjustmentSpecs`
- `coreFilters`
- neutral/default values
- semantic ranges, labels, groups, and units

GPU support is deliberately **not** part of this package's adjustment metadata. The application/GPU layer decides which adjustments have a verified continuous native preview path.

### Film Profile domain

- `FilmProfileV1`
- `FilmProfileOrigin`
- `FilmProfileParameterSpec`
- Film Profile schema/version validation
- import mapping reports (`exact`, `approximated`, `unsupported`)
- `applyFilmProfileToSessionRecipe()` draft materialization helper

The recipe materializer rewrites serialized draft data only. The caller must restore the resulting recipe through Rust before it becomes authoritative editor state.

## Does not own

- Flutter UI or Riverpod state
- `EditorController`
- GPU capability policy
- native GPU runtime
- Rust engine implementation
- authoritative history/checkpoint mutation
- recovery persistence
- Film Profile persistence/storage
- Film Profile product/library orchestration
- export rendering

## Dependency direction

```text
PixelCraft app
   ├── pixelcraft_film
   ├── pixelcraft_gpu
   ├── pixelcraft_editing
   └── pixelcraft_engine

pixelcraft_film
   └── pixelcraft_editing

pixelcraft_gpu
   └── pixelcraft_editing

pixelcraft_editing
   └── Dart SDK only
```

The package must stay app-independent and usable from host-side Dart tests without Flutter bindings.

## Edit graph contract

Current schema version:

```text
pixelCraftEditGraphSchemaVersion = 3
```

Node categories:

```text
adjustment
filmProfile
crop
rotate
flip
resize
overlay
```

Decoding validates object shape, schema version, node types, opacity bounds, mask references, and unique IDs.

## Adjustment contract

Adjustment ranges and neutral values are shared semantic metadata. Examples:

```text
Exposure       -2 ... +2   neutral 0 EV
Brightness      0 ...  2   neutral 1
Contrast        0 ...  2   neutral 1
Saturation      0 ...  2   neutral 1
Sharpness       0 ...  2   neutral 0
Gaussian Blur   0 ...  2   neutral 0
```

Whether one of these has a GPU drag-preview implementation is a separate infrastructure capability and must remain outside `pixelcraft_editing`.

## Film Profile contract

Current identifiers:

```text
schema            pixelcraft-film-profile
schemaVersion     1
minEngineVersion  1
```

Reusable Film Profiles contain configuration only: profile metadata, optional base Film, strength, normalized parameters, and tags. They do not contain source image data, editor history, checkpoint state, or captured GPU pixels.

Import mapping never silently drops unsupported source fields; every recognized input is reported as exact, approximated, or unsupported.

`pixelcraft_film` builds product/library/creator orchestration on top of these contracts. The dependency must remain one-way:

```text
pixelcraft_film -> pixelcraft_editing
pixelcraft_editing -X-> pixelcraft_film
```

## App compatibility adapters

Root app compatibility paths may remain for existing call sites:

```text
lib/core/edit_graph.dart
lib/core/film_profile_v1.dart
lib/core/film_profile_recipe.dart
lib/state/editor_adjustment_catalog.dart
```

They are not the canonical package API. The app adjustment adapter adds `gpuPreview` policy on top of the package-owned semantic spec instead of embedding backend support in the domain model.

New package/infrastructure code should import:

```dart
import 'package:pixelcraft_editing/pixelcraft_editing.dart';
```

rather than depending on root compatibility paths.

## Validation

Independent package gates:

```bash
cd packages/pixelcraft_editing
dart pub get
dart analyze
dart test
```

The package-boundary gate and these tests also run in root CI. The final G7A PR head passed editing package dependencies/analyze/tests in CI run #221 (`31611799174`).

See [`CODE_WALKTHROUGH.md`](CODE_WALKTHROUGH.md) for detailed boundary and extension rules.
