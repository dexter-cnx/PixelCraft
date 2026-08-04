import '../src/rust/frb_generated.dart';

/// Initializes the native Rust library before the first widget is built.
Future<void> initializeRustBridge() => RustLib.init();
