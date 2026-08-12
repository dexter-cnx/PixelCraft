import 'dart:ffi';
import 'dart:io';

/// Native backends currently visible to the shared wgpu core.
final class WgpuBackendSet {
  const WgpuBackendSet({
    required this.vulkan,
    required this.metal,
    required this.dx12,
    required this.gl,
  });

  factory WgpuBackendSet.fromMask(int mask) => WgpuBackendSet(
        vulkan: mask & (1 << 0) != 0,
        metal: mask & (1 << 1) != 0,
        dx12: mask & (1 << 2) != 0,
        gl: mask & (1 << 3) != 0,
      );

  final bool vulkan;
  final bool metal;
  final bool dx12;
  final bool gl;

  bool get any => vulkan || metal || dx12 || gl;
}

final class WgpuCapabilities {
  const WgpuCapabilities({
    required this.abiVersion,
    required this.adapterCount,
    required this.backends,
  });

  final int abiVersion;
  final int adapterCount;
  final WgpuBackendSet backends;

  bool get available => adapterCount > 0 && backends.any;
}

typedef _NativeU32Fn = Uint32 Function();
typedef _DartU32Fn = int Function();

/// Desktop entry point for the Rust/wgpu preview core.
///
/// Android and iOS keep their existing native zero-copy camera paths during
/// the migration. The shared wgpu core is currently enabled for macOS,
/// Windows and Linux.
final class WgpuGpuCore {
  WgpuGpuCore._();

  static bool get isSupportedPlatform =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  static WgpuCapabilities probe() {
    if (!isSupportedPlatform) {
      throw UnsupportedError(
        'The shared wgpu core is currently enabled on macOS, Windows and Linux.',
      );
    }

    final library = _openLibrary();
    final abiVersion = library
        .lookupFunction<_NativeU32Fn, _DartU32Fn>(
          'pixelcraft_gpu_wgpu_abi_version',
        )();
    final adapterCount = library
        .lookupFunction<_NativeU32Fn, _DartU32Fn>(
          'pixelcraft_gpu_wgpu_adapter_count',
        )();
    final backendMask = library
        .lookupFunction<_NativeU32Fn, _DartU32Fn>(
          'pixelcraft_gpu_wgpu_backend_mask',
        )();

    return WgpuCapabilities(
      abiVersion: abiVersion,
      adapterCount: adapterCount,
      backends: WgpuBackendSet.fromMask(backendMask),
    );
  }

  static DynamicLibrary _openLibrary() {
    if (Platform.isMacOS) {
      // CargoKit force-loads the static archive into the application process.
      return DynamicLibrary.process();
    }
    if (Platform.isWindows) {
      return DynamicLibrary.open('pixelcraft_gpu_native.dll');
    }
    if (Platform.isLinux) {
      return DynamicLibrary.open('libpixelcraft_gpu_native.so');
    }
    throw UnsupportedError('Unsupported wgpu desktop platform.');
  }
}
