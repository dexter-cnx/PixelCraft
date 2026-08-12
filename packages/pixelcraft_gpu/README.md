# pixelcraft_gpu

Preview-only GPU control plane for PixelCraft.

This package may represent and transport interactive preview state, but it never owns committed edit semantics. Rust remains authoritative for recipes, history, checkpoints, recovery, and full-resolution export. Camera frame buffers stay native and never cross Dart MethodChannel or Flutter Rust Bridge.

## Platform architecture

| Platform | Preview backend | Status |
| --- | --- | --- |
| Android | Existing native camera GPU path | Active |
| iOS | Existing Metal camera path | Active |
| macOS | Rust + wgpu → Metal | Foundation wired |
| Windows | Rust + wgpu → D3D12/Vulkan | Foundation wired |
| Linux | Rust + wgpu → Vulkan/GL | Foundation wired |

The desktop path is intentionally split into two layers:

1. `rust/` owns the cross-platform wgpu GPU core.
2. Flutter platform build files are thin adapters that package/load that core.

The first ABI (`WgpuGpuCore.probe`) exposes adapter count and detected native backends. This establishes and validates the desktop build/runtime boundary before camera-frame or editor-texture presentation is migrated.

Android and iOS remain on their existing zero-copy native preview implementations during this migration. Do not route camera frame buffers through Dart/MethodChannel/FRB.

## Desktop probe

```dart
import 'package:pixelcraft_gpu/pixelcraft_gpu.dart';

final capabilities = WgpuGpuCore.probe();
print(capabilities.adapterCount);
print(capabilities.backends.dx12);
print(capabilities.backends.vulkan);
print(capabilities.backends.metal);
```

## Migration guardrails

- `pixelcraft_gpu` remains preview-only.
- Committed edit semantics remain in the authoritative Rust engine.
- Desktop rendering should use WGSL/wgpu rather than separate D3D/Vulkan/Metal shader implementations.
- Platform-specific code should be limited to Flutter texture/surface interop and zero-copy external texture import/export where required.
- A desktop platform is not considered production-ready until texture presentation, resize/device-loss handling, frame pacing, and physical-device/GPU validation are complete.
