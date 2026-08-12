# pixelcraft_gpu

Preview-only Flutter plugin for PixelCraft's native GPU preview runtime.

`pixelcraft_gpu` provides low-latency preview infrastructure while keeping committed image semantics in Rust.

> GPU is an optimization and preview surface. Rust remains authoritative for committed recipes, history, checkpoints, recovery, and full-resolution export.

## P2 dependency boundary

`pixelcraft_gpu` now depends on the pure Dart `pixelcraft_editing` package for shared edit-graph contracts:

```text
pixelcraft_gpu
   └── pixelcraft_editing
```

This removes the previous package-boundary blocker where GPU renderer/capability contracts needed app-owned `lib/core/edit_graph.dart` types.

The following contracts now live in `pixelcraft_gpu` itself:

- `GpuPreviewRenderer`
- `GpuPreviewCapabilities`
- `GpuPreviewFilmState`
- `GpuPreviewViewport`
- `GpuPreviewCapabilityPolicy`
- `GpuPreviewCapabilityDecision`

The edit graph types they consume come from `pixelcraft_editing`:

- `EditGraphDocument`
- `EditNodeType`

Root `lib/gpu/*` files remain compatibility exports during the migration.

## Responsibilities

`pixelcraft_gpu` owns:

- app-independent Dart GPU transport/session infrastructure
- editor GPU render-plan transport contracts
- GPU renderer/capability contracts
- native camera control bridges
- Android Camera2/OpenGL ES **camera** runtime
- iOS AVFoundation/Metal **camera and editor** runtime
- Flutter plugin registration
- diagnostics and frame-pacing bridges

It does **not** own:

- committed edit semantics
- authoritative recipe/history state
- recovery policy
- full-resolution export
- app navigation/product state
- final image pixels
- generation/packaging of native LUT assets at the app build level

## Current platform scope

### Android

Android currently provides the native camera preview path:

```text
Camera2
 -> SurfaceTexture / external OES texture
 -> OpenGL ES
 -> Film LUT preview
 -> Flutter PlatformView
```

There is currently no Android editor GPU channel/view equivalent to the iOS `gpu_editor_preview_v1` path. Android editor interaction therefore remains on the valid Rust/product path.

### iOS

iOS currently provides both camera preview and the implemented native editor GPU preview path using Metal/AVFoundation.

Production sources live under:

```text
packages/pixelcraft_gpu/ios/Classes/
```

## Runtime boundary

```text
Flutter app
   ↓ control/session intent
pixelcraft_gpu
   ↓ shared graph contracts
pixelcraft_editing

pixelcraft_gpu native runtime
   ├── Android: Camera2 / OpenGL ES camera preview
   └── iOS: AVFoundation / Metal camera + editor preview

Flutter app
   ↓ semantic commit
Rust engine
   ↓
authoritative preview / recipe / export
```

Live camera frame buffers stay native. They never cross Dart MethodChannel or Flutter Rust Bridge.

## Camera contract

Camera Film is preview-only.

```text
native camera frames
   ↓
GPU Film preview
   ↓
user captures
   ↓
clean source JPEG/file path
```

Dart receives control data and the clean capture path, not processed live-frame buffers.

## Editor contract

Where a verified native editor path exists and the requested operation graph is representable:

```text
EditGraphDocument
   ↓
GpuPreviewRenderer / render-plan transport
   ↓
native preview

slider release
   ↓
Rust semantic commit
   ↓
authoritative Rust preview
```

At present the native editor path is implemented on iOS Metal, not Android OpenGL ES.

Unsupported ordering, unavailable platform support, or runtime failure falls back to the valid Rust path. The GPU layer must never silently reorder or approximate committed semantics.

## Canonical LUT data and packaging ownership

Film and Creative LUT **semantics** originate from Rust-owned canonical data.

Current native asset packaging is still app-owned:

- Android generation: `GenerateGpuLutAssetsTask` in `android/app/build.gradle.kts`
- iOS generation/copy: Runner/Xcode build phase

Therefore:

```text
LUT semantic authority = Rust
LUT asset packaging    = app build integration
LUT runtime consumer   = pixelcraft_gpu
```

Do not describe generated native LUT assets as package-owned until packaging is relocated.

## Validation

P1 closed only after Flutter/Rust/GPU tests, LUT parity, Android/iOS native packaging smoke, and physical-device smoke passed.

P2 additionally requires package-boundary validation so `pixelcraft_gpu` does not import PixelCraft app source for shared edit-domain types.

## Related documentation

- [`CODE_WALKTHROUGH.md`](CODE_WALKTHROUGH.md)
- [`../pixelcraft_editing/README.md`](../pixelcraft_editing/README.md)
- [`../pixelcraft_editing/CODE_WALKTHROUGH.md`](../pixelcraft_editing/CODE_WALKTHROUGH.md)
- [`../../docs/CODE_WALKTHROUGH.md`](../../docs/CODE_WALKTHROUGH.md)
