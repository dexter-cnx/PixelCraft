# pixelcraft_gpu

Preview-only Flutter plugin for PixelCraft's native GPU preview runtime.

`pixelcraft_gpu` provides low-latency native preview infrastructure while keeping committed image semantics in Rust.

> GPU is an optimization and preview surface. Rust remains authoritative for committed recipes, history, checkpoints, recovery, and full-resolution export.

## Responsibilities

`pixelcraft_gpu` owns:

- app-independent Dart GPU transport/session infrastructure
- editor GPU render-plan transport contracts
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

The Android `PixelcraftGpuPlugin.kt` registers the camera-facing `GpuPreviewChannel` and camera PlatformView/runtime.

**There is currently no Android editor GPU channel/view implementation corresponding to the iOS `gpu_editor_preview_v1` / `GpuEditorPreviewPlugin` path.**

Therefore `GpuEditorRenderPlan` must not be described as executing through Android OpenGL ES today. Android editor interaction remains on the valid Rust/product path until an Android editor renderer is implemented and parity-verified.

### iOS

iOS currently provides both camera preview and the implemented native editor GPU preview path using Metal/AVFoundation.

Production sources live under:

```text
packages/pixelcraft_gpu/ios/Classes/
```

## Runtime boundary

```text
Flutter app
   ↓ small control/session messages
pixelcraft_gpu
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
slider drag
   ↓
GPU preview session
   ↓
native low-latency preview

slider release
   ↓
Rust semantic commit
   ↓
authoritative Rust preview
```

At present this native editor path is implemented on iOS Metal, not Android OpenGL ES.

Unsupported operation ordering, unavailable platform support, or runtime failure falls back to the valid Rust path. The GPU layer must never silently reorder or approximate committed semantics.

## Native ownership

Android native camera registration belongs to the plugin rather than `MainActivity`.

The Android library namespace is:

```text
dev.pixelcraft.gpu
```

iOS production Metal/AVFoundation sources live in:

```text
packages/pixelcraft_gpu/ios/Classes/
```

The app `AppDelegate` remains an app shell; it is not the production GPU composition root.

## Canonical LUT data and current packaging ownership

Film and Creative LUT **semantics** originate from Rust-owned canonical data.

Conceptually:

```text
Rust canonical data
   ↓
33^3 LUTs / parity fixtures
   ├── Rust renderer
   └── generated native GPU assets
```

However, **native LUT asset generation/packaging is still app-owned today**, not fully owned by `pixelcraft_gpu`:

- Android LUT generation is wired from the app build through `GenerateGpuLutAssetsTask` in `android/app/build.gradle.kts`.
- iOS LUT generation/copying remains integrated through the Runner/Xcode build phase.
- `packages/pixelcraft_gpu/android/build.gradle` and `packages/pixelcraft_gpu/ios/pixelcraft_gpu.podspec` do not yet declare equivalent self-contained generated LUT resources.

So the plugin **consumes app-generated native LUT assets**. Do not describe those assets as package-owned until generation and packaging are actually relocated into `pixelcraft_gpu`.

This distinction preserves two separate truths:

```text
LUT semantic authority  = Rust
LUT native packaging    = app build integration (current)
```

## Validation

P1 was closed only after all of the following passed:

```text
Flutter analyze
Rust checks/tests
GPU plan/session tests
GPU LUT parity
Android native packaging smoke
iOS native packaging smoke
Android physical-device smoke
iOS physical-device smoke
```

The Android physical smoke validates the Android camera/plugin topology; it is not evidence that an Android editor GPU renderer exists.

## Detailed walkthrough

For the Dart control plane, editor session lifecycle, native registration, camera paths, fallback model, diagnostics, and extension rules, see:

- [`CODE_WALKTHROUGH.md`](CODE_WALKTHROUGH.md)

For the overall application architecture, see:

- [`../../docs/CODE_WALKTHROUGH.md`](../../docs/CODE_WALKTHROUGH.md)
