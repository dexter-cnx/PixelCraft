import 'dart:async';
import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcraft/app/platform_flow_foundation.dart';
import 'package:pixelcraft/camera/camera_capture_pipeline.dart';
import 'package:pixelcraft/camera/camera_capture_save_handoff.dart';
import 'package:pixelcraft/camera/camera_image_ratio.dart';
import 'package:pixelcraft/camera/camera_look_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sharedPreferencesChannel = MethodChannel(
    'plugins.flutter.io/shared_preferences',
  );

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sharedPreferencesChannel, (call) async {
          if (call.method == 'getAll') return <String, Object>{};
          return true;
        });
    await EasyLocalization.ensureInitialized();
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sharedPreferencesChannel, null);
  });

  testWidgets('keeps captured still visible until processing and save finish', (
    tester,
  ) async {
    final renderer = _BlockingRenderer();
    final saver = _FakeSaveService();

    await _pumpLocalized(
      tester,
      _localizedApp(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                key: const ValueKey('open_capture_handoff'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => CameraCaptureSaveHandoff(
                      imagePath: '/tmp/pixelcraft-pf7-test.jpg',
                      look: CameraLookState(),
                      captureRenderer: renderer,
                      mediaSaveService: saver,
                      sourceReader: (_) async => _tinyPngBytes,
                      sourceDeleter: (_) async {},
                      completionDelay: (_) async {},
                    ),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open_capture_handoff')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(renderer.started.isCompleted, isTrue);
    expect(
      find.byKey(const ValueKey('camera_capture_frozen_still')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('open_capture_handoff')).hitTestable(),
      findsNothing,
    );
    expect(saver.bytes, isNull);

    renderer.release.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(saver.bytes, isNotNull);
    expect(find.byKey(const ValueKey('open_capture_handoff')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('camera_capture_frozen_still')),
      findsNothing,
    );
  });
}

Widget _localizedApp(Widget child) => EasyLocalization(
  supportedLocales: const [Locale('en'), Locale('th')],
  path: 'assets/translations',
  fallbackLocale: const Locale('en'),
  startLocale: const Locale('en'),
  useOnlyLangCode: true,
  child: Builder(
    builder: (context) => MaterialApp(
      locale: context.locale,
      supportedLocales: context.supportedLocales,
      localizationsDelegates: context.localizationDelegates,
      home: child,
    ),
  ),
);

Future<void> _pumpLocalized(WidgetTester tester, Widget child) async {
  await tester.runAsync(() async {
    await tester.pumpWidget(child);
    await tester.idle();
  });
  await tester.pump();
  await tester.pumpAndSettle();
}

final Uint8List _tinyPngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

class _BlockingRenderer implements CameraCaptureRenderer {
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<Uint8List> renderJpeg({
    required Uint8List sourceJpeg,
    required CameraLookState look,
    CameraImageRatio imageRatio = CameraImageRatio.original,
    CameraCaptureOrientation captureOrientation = CameraCaptureOrientation.auto,
    double zoomFactor = 1,
    int quality = 95,
  }) async {
    started.complete();
    await release.future;
    return Uint8List.fromList(sourceJpeg);
  }
}

class _FakeSaveService implements MediaSaveService {
  Uint8List? bytes;

  @override
  Future<Uri> saveJpeg({
    required Uint8List bytes,
    String? suggestedName,
  }) async {
    this.bytes = Uint8List.fromList(bytes);
    return Uri.parse('media:/gallery/capture.jpg');
  }
}
