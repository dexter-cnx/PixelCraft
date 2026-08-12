# pixelcraft_editing

Pure editing-domain contracts and serialization models for PixelCraft.

`pixelcraft_editing` exists to remove reusable edit-graph types from the application layer so other internal packages can depend on editing semantics without importing `package:pixelcraft/...` app source.

> Rust remains authoritative for committed edit semantics, recipe/history/checkpoint state, recovery, and full-resolution export. This Dart package defines transport/domain contracts; it does not replace Rust authority.

## Owns

- `EditGraphDocument`
- `EditGraphNode`
- `EditNodeType`
- `EditMask`
- `EditOverlay`
- edit-graph schema versioning and JSON validation

## Does not own

- Flutter UI or Riverpod state
- `EditorController`
- native GPU runtime
- Rust engine implementation
- history/checkpoint mutation
- recovery persistence
- Film Profile storage
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

The package must stay app-independent and should remain usable from host-side tests without Flutter bindings.

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

Decoding validates:

- root/document object shape
- supported schema version
- node/mask/overlay object lists
- known node type
- opacity bounds
- referenced mask existence
- unique node/mask/overlay IDs

## Why P2 extracts this

Before P2, GPU adapters such as `GpuPreviewRenderer` depended on `lib/core/edit_graph.dart`, which made the GPU boundary understand an app-owned source path. Moving the pure graph model here allows `pixelcraft_gpu` to depend on a stable internal package instead of depending back on the application.

## Detailed walkthrough

See [`CODE_WALKTHROUGH.md`](CODE_WALKTHROUGH.md).
