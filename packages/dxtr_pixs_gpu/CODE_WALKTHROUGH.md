# pixelcraft_gpu Code Walkthrough

`pixelcraft_gpu` is PixelCraft's preview-only Flutter plugin for native GPU preview infrastructure.

Its purpose is low-latency interaction. It is never the authoritative source for committed edit semantics or exported pixels.

## 1. Responsibility boundary

```text
Flutter app
   ↓ control/session intent
pixelcraft_gpu
   ↓ shared editing-domain contracts
pixelcraft_editing

pixelcraft_gpu native runtime
   ├── Android: Camera2 / OpenGL ES camera preview
   └── iOS: AVFoundation / Metal camera + editor preview

Rust engine
   ↑ authoritative semantic commit
Flutter app
```

`pixelcraft_gpu` owns transport/runtime contracts and native preview implementation. `pixelcraft_editing` owns shared pure Dart edit-graph types. Rust owns committed semantics.

## 2. P2 change

Before P2, two GPU contracts stayed app-side because they imported `lib/core/edit_graph.dart`:

```text
lib/gpu/gpu_preview_renderer.dart
lib/gpu/gpu_preview_capability.dart
```

P2 extracts `EditGraphDocument` / `EditNodeType` into `pixelcraft_editing`, allowing those GPU contracts to move into this package without a package -> app dependency.

Current package relationship:

```text
pixelcraft_gpu
   └── pixelcraft_editing
        └── Dart SDK only
```

Root app paths remain compatibility exports while call sites migrate.

## 3. Shared editing contracts

The GPU package consumes these from `pixelcraft_editing`:

```text
EditGraphDocument
EditGraphNode
EditNodeType
EditMask
EditOverlay
```

The GPU package must not redefine them. A single shared type identity is important for capability sets, renderer APIs, tests, and future package consumers.

## 4. GPU renderer contract

`GpuPreviewRenderer` now lives in `packages/pixelcraft_gpu/lib/gpu_preview_renderer.dart`.

It exposes small control-plane operations:

```text
initialize
setViewport
setFilm
setEditGraph
setEnabled
dispose
```

`setEditGraph(EditGraphDocument)` passes graph intent/state, not image frame buffers.

`FallbackGpuPreviewRenderer` remains an explicit non-parity fallback and reports only the capabilities it actually supports.

## 5. Capability policy

`GpuPreviewCapabilityPolicy` now lives in the package and evaluates native probes without importing app source.

Fallback reasons include:

```text
protocol mismatch
backend unavailable
LUT33 unsupported
shader self-test failure
native assets unavailable
renderer initialization failure
runtime render failure
blacklisted GPU
```

All failure paths fail closed to a valid Rust/product path.

## 6. Editor render-plan scope

`GpuEditorRenderPlan` represents a native editor preview plan only when the requested operations are faithfully representable.

Current execution scope:

```text
authoritative recipe / active draft
   ↓ adapter
GpuEditorRenderPlan
   ↓
pixelcraft_gpu editor transport
   ↓
iOS Metal editor preview
```

The implemented native editor channel/view currently exists on **iOS Metal only**.

Android OpenGL ES support is currently camera-only; do not infer an Android editor renderer from the presence of `GpuEditorRenderPlan` or `EditGraphDocument` support in Dart.

## 7. Android native path

```text
Camera2
   ↓
SurfaceTexture / external OES texture
   ↓
OpenGL ES renderer
   ↓
Film LUT preview
   ↓
Flutter PlatformView
```

The Android plugin registers the camera-facing channel/runtime. There is currently no Android editor GPU channel/view equivalent to the iOS editor path.

## 8. iOS native path

```text
AVCaptureVideoDataOutput
   ↓
CVPixelBuffer
   ↓
CVMetalTextureCache
   ↓
Metal renderer
```

iOS contains both native camera preview and the implemented editor GPU preview path.

Production sources live under:

```text
packages/pixelcraft_gpu/ios/Classes/
```

## 9. Live-frame invariant

Large live camera frame buffers remain native.

```text
MethodChannel / Dart = control plane
native GPU pipeline   = frame plane
```

Dart may carry permissions, lens IDs, viewport/film/edit state, diagnostics, and clean capture paths. It must not become the live video transport.

## 10. Camera capture contract

Camera Film is preview-only:

```text
native camera frame
   ↓ GPU Film preview
user captures
   ↓
clean source JPEG/file path
```

GPU preview pixels are not authoritative capture pixels.

## 11. LUT ownership

Keep these concepts separate:

```text
LUT semantic authority = Rust
LUT asset packaging    = app build integration (current)
LUT runtime consumer   = pixelcraft_gpu
```

Android generation remains wired through `android/app/build.gradle.kts`; iOS generation/copy remains a Runner/Xcode build phase. P2 does not change that packaging ownership.

## 12. Safe extension rules

For a new GPU effect/backend:

1. Define and test semantic behavior in Rust first.
2. Determine whether the native backend can reproduce it faithfully and in order.
3. Add parity/behavior evidence.
4. Fail closed when unsupported.

Moving Dart types between packages must not change these rendering invariants.

## 13. What no longer belongs app-side after P2

Pure reusable contracts that only depended on edit-graph domain types can move into `pixelcraft_gpu` now that the graph model is package-owned.

Examples completed in the initial P2 slice:

```text
GpuPreviewRenderer
GpuPreviewCapabilities
GpuPreviewCapabilityPolicy
```

Application orchestration still does not belong here:

```text
EditorController
navigation
Film Profile persistence
recovery/session store
Rust recipe/history ownership
export pipeline
```

## 14. Dependency invariant

```text
pixelcraft_gpu -> pixelcraft_editing
pixelcraft_gpu -X-> PixelCraft app source
```

If this package needs `package:pixelcraft/...` or relative imports back into root `lib/` to compile, the package boundary has regressed.

## 15. Related docs

- [`README.md`](README.md)
- [`../pixelcraft_editing/README.md`](../pixelcraft_editing/README.md)
- [`../pixelcraft_editing/CODE_WALKTHROUGH.md`](../pixelcraft_editing/CODE_WALKTHROUGH.md)
- [`../../docs/CODE_WALKTHROUGH.md`](../../docs/CODE_WALKTHROUGH.md)
