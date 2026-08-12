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
- native GPU runtime
- Rust engine implementation
- authoritative history/checkpoint mutation
- recovery persistence
- Film Profile persistence/storage
- export rendering

## Dependency direction

```text
PixelCraft app
   ├── pixelcraft_editing
   ├── pixelcraft_gpu
   └── pixelcraft_engine

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

## Film Profile contract

Current identifiers:

```text
schema            pixelcraft-film-profile
schemaVersion     1
minEngineVersion  1
```

Reusable Film Profiles contain configuration only: profile metadata, optional base Film, strength, normalized parameters, and tags. They do not contain source image data, editor history, checkpoint state, or captured GPU pixels.

Import mapping never silently drops unsupported source fields; every recognized input is reported as exact, approximated, or unsupported.

## Compatibility during P2

The former app paths remain compatibility exports while call sites are migrated:

```text
lib/core/edit_graph.dart
lib/core/film_profile_v1.dart
lib/core/film_profile_recipe.dart
```

New package/infrastructure code should import:

```dart
import 'package:pixelcraft_editing/pixelcraft_editing.dart';
```

rather than depending on the compatibility paths.

## Validation

P2 adds independent package gates:

```bash
cd packages/pixelcraft_editing
dart pub get
dart analyze
dart test
```

See [`CODE_WALKTHROUGH.md`](CODE_WALKTHROUGH.md) for the detailed boundary and extension rules.
