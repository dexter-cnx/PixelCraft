import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/bridge.dart';
import 'ui/screens/gpu_editor_preview_lab_screen.dart';
import 'ui/screens/home_screen.dart';

const _launchGpuEditorLab = bool.fromEnvironment('GPU_EDITOR_LAB');

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught platform error: $error');
    debugPrintStack(stackTrace: stack);
    return true;
  };

  runApp(const ProviderScope(child: PixelCraftApp()));
}

class PixelCraftApp extends StatelessWidget {
  const PixelCraftApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Pixel Craft',
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: const Color(0xFF7259E7),
          brightness: Brightness.light,
          scaffoldBackgroundColor: const Color(0xFFF8F7FC),
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: const Color(0xFF9D8CFF),
          brightness: Brightness.dark,
        ),
        home: kDebugMode && _launchGpuEditorLab
            ? const GpuEditorPreviewLabScreen()
            : const RustBootstrapScreen(),
      );
}

class RustBootstrapScreen extends StatefulWidget {
  const RustBootstrapScreen({super.key});

  @override
  State<RustBootstrapScreen> createState() => _RustBootstrapScreenState();
}

class _RustBootstrapScreenState extends State<RustBootstrapScreen> {
  static const _timeout = Duration(seconds: 15);

  late Future<void> _initialization;

  @override
  void initState() {
    super.initState();
    _initialization = _initialize();
  }

  Future<void> _initialize() async {
    final stopwatch = Stopwatch()..start();
    debugPrint('[Pixel Craft] Initializing Rust bridge...');

    try {
      await initializeRustBridge().timeout(
        _timeout,
        onTimeout: () => throw TimeoutException(
          'Rust bridge initialization exceeded ${_timeout.inSeconds} seconds. '
          'The Android native library may be missing or built for the wrong ABI.',
          _timeout,
        ),
      );
      debugPrint(
        '[Pixel Craft] Rust bridge ready in ${stopwatch.elapsedMilliseconds} ms',
      );
    } catch (error, stackTrace) {
      debugPrint('[Pixel Craft] Rust bridge initialization failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    } finally {
      stopwatch.stop();
    }
  }

  void _retry() {
    setState(() {
      _initialization = _initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initialization,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            !snapshot.hasError) {
          return const HomeScreen();
        }

        if (snapshot.hasError) {
          return Scaffold(
            body: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.memory_rounded,
                          size: 64,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Rust engine could not start',
                          style: Theme.of(context).textTheme.headlineSmall,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        SelectableText(
                          '${snapshot.error}',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: _retry,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        return Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 42,
                  height: 42,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
                const SizedBox(height: 20),
                Text(
                  'Starting Rust image engine…',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
