# pixelcraft_editing Code Walkthrough

`pixelcraft_editing` is the pure Dart editing-domain boundary introduced in P2.

Its job is to own reusable edit-graph contracts that must be shared by the PixelCraft app and infrastructure packages without creating package -> app dependencies.

## 1. Architectural position

```text
Flutter app / product state
        ↓
pixelcraft_editing domain contracts
        ↓
preview adapters / serialization boundaries

Rust engine = authoritative committed semantics
```

The package models editing intent and serialized graph structure. It does not execute committed image processing.

## 2. Why this package exists

Before P2:

```text
lib/core/edit_graph.dart
        ↑
lib/gpu/gpu_preview_renderer.dart
```

That coupling prevented GPU renderer/capability contracts from moving fully into `pixelcraft_gpu` because they needed app-owned types.

After P2:

```text
pixelcraft_gpu ──> pixelcraft_editing
PixelCraft app ──> pixelcraft_editing
```

No package needs to import PixelCraft application source to understand `EditGraphDocument` or `EditNodeType`.

## 3. Public API

The package exports its public domain surface through:

```text
lib/pixelcraft_editing.dart
```

Current primary implementation:

```text
lib/src/edit_graph.dart
```

Public types:

```text
EditGraphDocument
EditGraphNode
EditNodeType
EditMask
EditOverlay
```

## 4. Schema model

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

The schema is intentionally explicit so transport boundaries do not silently accept incompatible graph formats.

## 5. Node semantics

`EditNodeType` currently contains:

```text
adjustment
filmProfile
crop
rotate
flip
resize
overlay
```

Each `EditGraphNode` carries:

```text
id
type
enabled
opacity
params
maskId
```

`params` remains a JSON-compatible map because individual operation semantics continue to be defined authoritatively in Rust and higher-level adapters.

## 6. Validation

`EditGraphDocument.decode()` / `fromJson()` fail early for malformed or incompatible data.

Validation includes:

```text
schemaVersion must be an integer
schemaVersion must match the supported version
document must be an object
nodes/masks/overlays must be object arrays
node types must be known
opacity must stay within 0...1
mask references must exist
node/mask/overlay IDs must be unique
```

Invalid input throws `FormatException`; it is not coerced into a partially valid graph.

## 7. Relationship to Rust

A crucial distinction:

```text
pixelcraft_editing = shared Dart domain/transport model
Rust               = authoritative processing semantics
```

Moving a model into this package does not move semantic authority out of Rust.

The package must not become a second independent recipe engine, history implementation, or final renderer.

## 8. Relationship to pixelcraft_gpu

`pixelcraft_gpu` may depend on this package for:

- supported edit-node capability sets
- `EditGraphDocument` transport
- preview renderer contracts

GPU behavior remains preview-only and fail-closed. Unsupported graph order/composition must fall back to the valid Rust/product path rather than mutate or reinterpret the graph.

## 9. What belongs here next

A type is a good P2 candidate when it is:

- pure Dart
- editing-domain focused
- independent of Flutter widgets/Riverpod/navigation
- independent of native GPU implementation
- useful to more than one package/app adapter

Do not move app orchestration here merely to reduce file count.

## 10. Dependency rule

The package should remain at the bottom of the Dart package graph:

```text
pixelcraft_editing -> Dart SDK only
```

If it begins importing `pixelcraft_gpu`, app UI, Riverpod, or native platform APIs, the boundary has regressed.
