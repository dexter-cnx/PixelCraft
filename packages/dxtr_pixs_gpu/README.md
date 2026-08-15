# pixelcraft_gpu

Preview-only Flutter plugin for PixelCraft's native GPU preview runtime.

`pixelcraft_gpu` provides low-latency preview infrastructure while keeping committed image semantics in Rust.

> GPU is an optimization and preview surface. Rust remains authoritative for committed recipes, history, checkpoints, recovery, and full-resolution export.

## Dependency boundary

`pixelcraft_gpu` depends on the pure Dart `pixelcraft_editing` package for shared edit-graph contracts:

```text
pixelcraft_gpu
   └── pixelcraft_editing
```

The package owns GPU renderer/capability/session transport contracts while shared edit-domain types come from `pixelcraft_editing`.

Key package-owned contracts include:

- `GpuPreviewRenderer`
- `GpuPreviewCapabilities`
- `GpuPreviewFilmState`
- `GpuPreviewViewport`
- `GpuPreviewCapabilityPolicy`
- `GpuPreviewCapabilityDecision`

Shared graph types include:

- `EditGraphDocument`
- `EditNodeType`

Root `lib/gpu/*` paths may remain as app compatibility exports, but new reusable GPU code must use package APIs rather than importing root app source.

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

The plugin manifest declares Android, iOS, Linux, macOS, and Windows integration points. The production mobile preview behavior documented here is intentionally narrower: Android camera preview and iOS camera/editor preview. Desktop declarations must not be interpreted as feature parity with the mobile native preview paths.

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

Current native asset packaging remains app-owned:

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

The package is validated independently in root CI with dependency resolution, `flutter analyze`, and package tests. The final G7A PR head passed those gates in full CI run #221 (`31611799174`) alongside LUT parity, native packaging, release packaging, and wgpu Linux/macOS/Windows.

P1 physical smoke previously passed on both iOS and Android for the mobile native preview paths.

## Related documentation

- [`CODE_WALKTHROUGH.md`](CODE_WALKTHROUGH.md)
- [`../pixelcraft_editing/README.md`](../pixelcraft_editing/README.md)
- [`../pixelcraft_editing/CODE_WALKTHROUGH.md`](../pixelcraft_editing/CODE_WALKTHROUGH.md)
- [`../../docs/CODE_WALKTHROUGH.md`](../../docs/CODE_WALKTHROUGH.md)
