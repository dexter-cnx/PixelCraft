# pixelcraft_editing Code Walkthrough

`pixelcraft_editing` is the pure Dart editing-domain boundary introduced in P2.

Its job is to own reusable editing contracts that must be shared by the PixelCraft app and infrastructure packages without creating package -> app dependencies.

## 1. Architectural position

```text
Flutter app / product state
        ↓
pixelcraft_editing domain contracts
        ↓
preview adapters / serialization boundaries

Rust engine = authoritative committed semantics
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

After P2:

```text
pixelcraft_gpu ──> pixelcraft_editing
PixelCraft app ──> pixelcraft_editing
```

Former app paths remain compatibility exports/adapters during migration.

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

`EditorAdjustmentSpec` now lives in `pixelcraft_editing` and contains only semantic/product metadata:

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

The former app catalog remains a compatibility/policy adapter. It wraps the package-owned semantic specs and adds whether a control currently has verified continuous GPU preview support.

This separation prevents a pure editing-domain package from learning about Metal/OpenGL/backend rollout state.

## 6. Film Profile model

`FilmProfileV1` is reusable configuration, not a per-image edit session.

Schema identifiers:

```text
schema            pixelcraft-film-profile
schemaVersion     1
minEngineVersion  1
```

It carries profile metadata, optional base Film, strength, normalized parameter values, and tags. It excludes source pixels, history/checkpoint state, and GPU frames.

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

This dependency is allowed:

```text
pixelcraft_gpu -> pixelcraft_editing
```

The reverse direction is forbidden. `pixelcraft_editing` must not learn about Metal, OpenGL ES, MethodChannels, renderer lifecycle, or platform capability policy.

GPU behavior remains preview-only and fail-closed.

## 10. What remains app-owned

```text
EditorController / Riverpod state
UI/navigation
GPU rollout/capability policy
recovery persistence
Film Profile storage
export/file/gallery services
Rust bridge implementation
native GPU implementation
```

P2 moves reusable semantics, not orchestration.

## 11. Validation

The package is validated independently:

```bash
cd packages/pixelcraft_editing
dart pub get
dart analyze
dart test
```

Package tests cover edit-graph behavior, semantic adjustment defaults/ranges, Film Profile normalization/round-trip, import mapping classification, and active-draft materialization/redo-tail truncation.

## 12. Dependency invariant

```text
pixelcraft_editing -> Dart SDK only
```

A future import of Flutter UI, Riverpod, `pixelcraft_gpu`, native APIs, or app source into this package is an architectural regression.
