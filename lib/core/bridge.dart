import 'package:flutter/foundation.dart';

import '../src/rust/frb_generated.dart';
import 'rust_external_library_stub.dart'
    if (dart.library.io) 'rust_external_library_io.dart';

bool _initialized = false;
Future<void>? _initialization;

/// Initializes the native Rust library exactly once.
///
/// Repeated widget rebuilds and Retry taps share the same in-flight future,
/// preventing concurrent `RustLib.init()` calls.
Future<void> initializeRustBridge() {
  if (_initialized) return Future<void>.value();

  return _initialization ??= _initializeOnce();
}

Future<void> _initializeOnce() async {
  try {
    await RustLib.init(
      externalLibrary: rustExternalLibraryForCurrentPlatform(),
    );
    _initialized = true;
  } catch (error) {
    // Permit a real retry after a failed native-library load.
    _initialization = null;
    debugPrint('[PixelCraft] RustLib.init error: $error');
    rethrow;
  }
}
