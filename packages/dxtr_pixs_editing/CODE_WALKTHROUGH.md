# pixelcraft_editing Code Walkthrough

`pixelcraft_editing` is the pure Dart editing-domain boundary introduced in P2.

Its job is to own reusable editing contracts shared by the PixelCraft app, `pixelcraft_gpu`, and `pixelcraft_film` without creating package -> app dependencies.

## 1. Architectural position

```text
PixelCraft app
   ├── pixelcraft_film ──> pixelcraft_editing
   ├── pixelcraft_gpu  ──> pixelcraft_editing
   └── pixelcraft_editing

pixelcraft_editing -> Dart SDK only
Rust engine        = authoritative committed semantics
```

The package models editing intent, adjustment semantics, reusable Film Profile configuration, serialized graph structure, and deterministic draft shaping. It does not execute committed image processing.

## 2. Why this package exists

Before P2, shared GPU/domain code reached into app-owned files such as:

```text
lib/core/edit_graph.dart
lib/core/film_profile_v1.dart
lib/core/film_profile_recipe.dart
lib/state/editor_adjustment_catalog.dart
```

After P2/P3, reusable contracts live in `pixelcraft_editing`; GPU infrastructure and Film Profile product orchestration depend on those contracts without importing root app source.

Root app compatibility exports/adapters may remain for existing call sites, but they are not the canonical package API.

## 3. Public API

Public barrel:

```text
lib/pixelcraft_editing.dart
```

Primary implementation files:

```text
lib/src/edit_graph.dart
lib/src/editor_adjustment_catalog.dart
lib/src/film_profile_v1.dart
lib/src/film_profile_recipe.dart
```

## 4. Edit graph model

Current schema:

```text
pixelCraftEditGraphSchemaVersion = 3
```

Public graph types:

```text
EditGraphDocument
EditGraphNode
EditNodeType
EditMask
EditOverlay
```

`EditGraphDocument.decode()` / `fromJson()` validate schema compatibility, object/list shapes, known node types, opacity bounds, mask references, and unique IDs. Invalid data throws `FormatException` rather than being coerced into a partially valid graph.

## 5. Adjustment semantic catalog

`EditorAdjustmentSpec` contains semantic/product metadata only:

```text
id
label
min
max
neutral
group
unit
```

It deliberately does **not** contain GPU/backend capability flags.

Package-owned helpers:

```text
editorAdjustmentSpecs
coreFilters
adjustmentSpec(id)
defaultAdjustmentValue(id)
```

The root app adjustment adapter may add whether a control currently has verified continuous GPU preview support. This prevents a pure editing-domain package from learning about Metal/OpenGL/backend rollout state.

## 6. Film Profile model

`FilmProfileV1` is reusable configuration, not a per-image edit session.

Schema identifiers:

```text
schema            pixelcraft-film-profile
schemaVersion     1
minEngineVersion  1
```

It carries profile metadata, optional base Film, strength, normalized parameter values, and tags. It excludes source pixels, history/checkpoint state, and GPU frames.

`pixelcraft_film` builds library/import/creator orchestration on top of these models; the ownership direction remains:

```text
pixelcraft_film -> pixelcraft_editing
pixelcraft_editing -X-> pixelcraft_film
```

## 7. Import compatibility reporting

Generic recipe import uses:

```text
FilmProfileMappingKind.exact
FilmProfileMappingKind.approximated
FilmProfileMappingKind.unsupported
```

Unsupported fields remain visible in the import report. PixelCraft must not silently discard them or claim proprietary vendor processing is reproduced 1:1.

## 8. Film Profile recipe materialization

`applyFilmProfileToSessionRecipe()` reshapes the active serialized draft while preserving the applied prefix and truncating stale redo state.

The helper does **not** commit editor state by itself. The application must restore the rewritten recipe through the Rust engine before presenting it as authoritative state.

```text
pixelcraft_editing helper = deterministic draft transformation
Rust engine               = semantic authority
```

## 9. Relationship to pixelcraft_gpu

Allowed:

```text
pixelcraft_gpu -> pixelcraft_editing
```

The reverse direction is forbidden. `pixelcraft_editing` must not learn about Metal, OpenGL ES, MethodChannels, renderer lifecycle, or platform capability policy.

GPU behavior remains preview-only and fail-closed.

## 10. What remains outside this package

App/platform responsibilities:

```text
EditorController / Riverpod state
UI/navigation
GPU rollout/capability policy
recovery persistence
Film Profile filesystem storage
export/file/gallery services
Rust bridge integration
native GPU implementation
```

Film Profile product/domain orchestration belongs to `pixelcraft_film`, not `pixelcraft_editing`.

## 11. Validation

The package is validated independently:

```bash
cd packages/pixelcraft_editing
dart pub get
dart analyze
dart test
```

Package tests cover edit-graph behavior, semantic adjustment defaults/ranges, Film Profile normalization/round-trip, import mapping classification, and active-draft materialization/redo-tail truncation.

The final G7A PR head passed editing package dependencies/analyze/tests in full CI run #221 (`31611799174`).

## 12. Dependency invariant

```text
pixelcraft_editing -> Dart SDK only
```

A future import of Flutter UI, Riverpod, `pixelcraft_gpu`, `pixelcraft_film`, native APIs, or app source into this package is an architectural regression.
