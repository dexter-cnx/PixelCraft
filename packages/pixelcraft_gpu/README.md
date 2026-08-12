# pixelcraft_gpu

Preview-only Flutter plugin for PixelCraft's native GPU camera and editor rendering.

`pixelcraft_gpu` provides the low-latency Android OpenGL ES/Camera2 and iOS Metal/AVFoundation paths used during interaction.

> GPU is an optimization and preview surface. Rust remains authoritative for committed recipes, history, checkpoints, recovery, and full-resolution export.

## Responsibilities

`pixelcraft_gpu` owns:

- app-independent Dart GPU transport/session infrastructure
- editor GPU render-plan transport
- native camera control bridges
- Android Camera2/OpenGL ES runtime
- iOS AVFoundation/Metal runtime
- Flutter plugin registration
- diagnostics and frame-pacing bridges

It does **not** own:

- committed edit semantics
- authoritative recipe/history state
- recovery policy
- full-resolution export
- app navigation/product state
- final image pixels

## Runtime boundary

```text
Flutter app
   ↓ small control/session messages
pixelcraft_gpu
   ├── Android Camera2 / OpenGL ES
   └── iOS AVFoundation / Metal

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

During a representable editor gesture:

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

Unsupported operation ordering or runtime failure falls back to the valid Rust path. The GPU layer must never silently reorder or approximate committed semantics.

## Native ownership

Android native registration belongs to the plugin rather than `MainActivity`.

The Android library namespace is:

```text
dev.pixelcraft.gpu
```

iOS production Metal/AVFoundation sources live in:

```text
packages/pixelcraft_gpu/ios/Classes/
```

The app `AppDelegate` remains an app shell; it is not the production GPU composition root.

## Canonical LUT data

Film and Creative LUT meaning originates from Rust-owned canonical data and is materialized into generated native GPU assets.

```text
Rust canonical data
   ↓
33^3 LUTs / parity fixtures
   ├── Rust renderer
   └── pixelcraft_gpu native assets
```

This keeps GPU preview aligned with Rust rather than maintaining separate hand-authored Film semantics.

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

## Detailed walkthrough

For the Dart control plane, editor session lifecycle, native registration, camera paths, fallback model, diagnostics, and extension rules, see:

- [`CODE_WALKTHROUGH.md`](CODE_WALKTHROUGH.md)

For the overall application architecture, see:

- [`../../docs/CODE_WALKTHROUGH.md`](../../docs/CODE_WALKTHROUGH.md)
