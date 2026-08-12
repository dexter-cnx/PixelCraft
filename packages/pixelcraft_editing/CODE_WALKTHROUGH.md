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

The package models editing intent, reusable Film Profile configuration, serialized graph structure, and deterministic draft shaping. It does not execute committed image processing.

## 2. Why this package exists

Before P2, shared GPU/domain code reached into app-owned files such as:

```text
lib/core/edit_graph.dart
lib/core/film_profile_v1.dart
lib/core/film_profile_recipe.dart
```

That prevented infrastructure packages from depending on stable domain types without depending back on the application.

After P2:

```text
pixelcraft_gpu ──> pixelcraft_editing
PixelCraft app ──> pixelcraft_editing
```

The former app paths remain compatibility exports during migration.

## 3. Public API

Public barrel:

```text
lib/pixelcraft_editing.dart
```

Primary implementation files:

```text
lib/src/edit_graph.dart
lib/src/film_profile_v1.dart
lib/src/film_profile_recipe.dart
```

## 4. Edit graph model

Current schema:

```text
pixelCraftEditGraphSchemaVersion = 3
```

Serialized shape:

```json
{
  "schemaVersion": 3,
  "document": {
    "nodes": [],
    "masks": [],
    "overlays": []
  }
}
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

## 5. Film Profile model

`FilmProfileV1` is reusable configuration, not a per-image edit session.

Schema identifiers:

```text
schema            pixelcraft-film-profile
schemaVersion     1
minEngineVersion  1
```

It carries:

```text
id / name / description
origin
optional base Film ID
base Film strength
normalized parameter map
tags
compatibility versions
```

It deliberately excludes source pixels, crop/rotate session state, history, checkpoint state, and captured GPU frames.

Parameter values are clamped by `FilmProfileParameterSpec`; neutral values are normalized out of persisted profile parameter maps.

## 6. Import compatibility reporting

Generic recipe import uses:

```text
FilmProfileMappingKind.exact
FilmProfileMappingKind.approximated
FilmProfileMappingKind.unsupported
```

Unsupported fields remain visible in the import report. PixelCraft must not silently discard them or claim proprietary vendor processing is reproduced 1:1.

## 7. Film Profile recipe materialization

`applyFilmProfileToSessionRecipe()` operates on serialized Rust recipe JSON:

```text
current recipe
 -> preserve operations before checkpoint_cursor
 -> inspect active draft
 -> upsert base Film operation
 -> upsert profile scalar filters
 -> truncate stale redo tail
 -> return rewritten recipe JSON
```

The helper does **not** commit editor state by itself. The application must restore the rewritten recipe through the Rust engine before presenting it as authoritative state.

This distinction is critical:

```text
pixelcraft_editing helper = deterministic draft transformation
Rust engine               = semantic authority
```

## 8. Relationship to pixelcraft_gpu

`pixelcraft_gpu` may depend on this package for graph types and other pure editing-domain contracts.

This direction is allowed:

```text
pixelcraft_gpu -> pixelcraft_editing
```

The reverse direction is forbidden. `pixelcraft_editing` must not learn about Metal, OpenGL ES, MethodChannels, renderer lifecycle, or platform capability policy.

GPU behavior remains preview-only and fail-closed. Unsupported graph order/composition must fall back to the valid Rust/product path.

## 9. What remains app-owned

P2 does not move orchestration merely to reduce file count. These remain outside this package:

```text
EditorController / Riverpod state
UI/navigation
recovery persistence
Film Profile storage
export/file/gallery services
Rust bridge implementation
native GPU implementation
```

`EditorAdjustmentSpec.gpuPreview` also mixes product metadata with backend capability policy; it should not be moved wholesale into the pure domain package without first separating semantic adjustment metadata from GPU support policy.

## 10. Validation

The package is validated independently:

```bash
cd packages/pixelcraft_editing
dart pub get
dart analyze
dart test
```

Package tests cover Film Profile normalization/round-trip, import mapping classification, and active-draft materialization/redo-tail truncation. Root compatibility tests continue to protect existing application call sites during migration.

## 11. Dependency invariant

The intended bottom-of-graph rule is:

```text
pixelcraft_editing -> Dart SDK only
```

A future import of Flutter UI, Riverpod, `pixelcraft_gpu`, native APIs, or app source into this package is an architectural regression.
