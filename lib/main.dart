import 'dart:async';
import 'dart:ui';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'app/app_routes.dart';
import 'app/platform_flow_foundation.dart';
import 'camera/camera_film_editor_handoff.dart';
import 'core/bridge.dart';
import 'ui/screens/camera_film_preview_screen.dart';
import 'ui/screens/film_profiles_screen.dart';
import 'ui/screens/gpu_editor_preview_lab_screen.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/product_editor_screen.dart';

const _launchGpuEditorLab = bool.fromEnvironment('GPU_EDITOR_LAB');

bool get _isMobilePlatform => !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();

  if (_isMobilePlatform) {
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
  }

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught platform error: $error');
    debugPrintStack(stackTrace: stack);
    return true;
  };

  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('en'), Locale('th')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      useOnlyLangCode: true,
      child: const ProviderScope(child: PixelCraftApp()),
    ),
  );
}

class PixelCraftApp extends ConsumerStatefulWidget {
  const PixelCraftApp({super.key});

  @override
  ConsumerState<PixelCraftApp> createState() => _PixelCraftAppState();
}

class _PixelCraftAppState extends ConsumerState<PixelCraftApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    final platformInitialLocation = AppRoutePaths.initialLocationForIntent(
      ref.read(appRouterProvider).initialIntent(),
    );
    _router = GoRouter(
      initialLocation: kDebugMode && _launchGpuEditorLab
          ? AppRoutePaths.gpuEditorLab
          : platformInitialLocation,
      routes: [
        GoRoute(
          path: AppRoutePaths.camera,
          name: AppRouteNames.camera,
          builder: (_, __) => const RustBootstrapScreen(
            child: CameraFilmPreviewScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutePaths.desktop,
          name: AppRouteNames.desktop,
          builder: (_, __) => const RustBootstrapScreen(
            child: HomeScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutePaths.films,
          name: AppRouteNames.films,
          builder: (_, __) => const RustBootstrapScreen(
            child: FilmProfilesScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutePaths.editor,
          name: AppRouteNames.editor,
          builder: (_, state) {
            final data = state.extra;
            if (data is! EditorRouteData) {
              return const _InvalidEditorRouteScreen();
            }
            final editor = data.hasInitialFilm
                ? CameraFilmEditorHandoff(
                    imagePath: data.imagePath!,
                    profileId: data.initialFilmProfileId!,
                    strength: data.initialFilmStrength,
                  )
                : ProductEditorScreen(
                    imagePath: data.imagePath,
                    imageBytes: data.imageBytes,
                    recoveryRecipe: data.recoveryRecipe,
                  );
            return RustBootstrapScreen(child: editor);
          },
        ),
        GoRoute(
          path: AppRoutePaths.gpuEditorLab,
          name: AppRouteNames.gpuEditorLab,
          builder: (_, __) => const GpuEditorPreviewLabScreen(),
        ),
      ],
      errorBuilder: (_, state) => Scaffold(
        body: Center(child: Text('Route not found: ${state.uri}')),
      ),
    );
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
        debugShowCheckedModeBanner: false,
        title: 'Dextryx Pixels',
        locale: context.locale,
        supportedLocales: context.supportedLocales,
        localizationsDelegates: context.localizationDelegates,
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
        routerConfig: _router,
      );
}

class RustBootstrapScreen extends StatefulWidget {
  const RustBootstrapScreen({super.key, required this.child});

  final Widget child;

  @override
  State<RustBootstrapScreen> createState() => _RustBootstrapScreenState();
}

class _RustBootstrapScreenState extends State<RustBootstrapScreen> {
  static const _timeout = Duration(seconds: 15);
  static Future<void>? _sharedInitialization;

  late Future<void> _initialization;

  @override
  void initState() {
    super.initState();
    _initialization = _sharedInitialization ??= _initialize();
  }

  Future<void> _initialize() async {
    final stopwatch = Stopwatch()..start();
    debugPrint('[Dextryx Pixels] Initializing Rust bridge...');

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
        '[Dextryx Pixels] Rust bridge ready in ${stopwatch.elapsedMilliseconds} ms',
      );
    } catch (error, stackTrace) {
      debugPrint('[Dextryx Pixels] Rust bridge initialization failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      _sharedInitialization = null;
      rethrow;
    } finally {
      stopwatch.stop();
    }
  }

  void _retry() {
    setState(() {
      _sharedInitialization = null;
      _initialization = _sharedInitialization ??= _initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initialization,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            !snapshot.hasError) {
          return widget.child;
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
                          'app.engine_start_failed'.tr(),
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
                          label: Text('app.retry'.tr()),
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
                  'app.starting_engine'.tr(),
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

class _InvalidEditorRouteScreen extends StatelessWidget {
  const _InvalidEditorRouteScreen();

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('The editor route requires a valid source.'),
          ),
        ),
      );
}
