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

  testWidgets('keeps captured still visible until transaction finishes', (
    tester,
  ) async {
    final transaction = _BlockingCaptureTransaction();

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
                      transaction: transaction,
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

    expect(transaction.started.isCompleted, isTrue);
    expect(
      find.byKey(const ValueKey('camera_capture_frozen_still')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('open_capture_handoff')).hitTestable(),
      findsNothing,
    );
    expect(transaction.finished, isFalse);
    expect(transaction.cleanedUp, isFalse);

    transaction.release.complete();
    await tester.pump();

    expect(transaction.finished, isTrue);
    expect(
      find.byKey(const ValueKey('camera_capture_frozen_still')),
      findsOneWidget,
    );

    // Once processing has completed the progress indicator is gone, so it is
    // safe to settle the 900 ms success hold plus the route pop animation.
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('open_capture_handoff')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('camera_capture_frozen_still')),
      findsNothing,
    );
    expect(transaction.cleanedUp, isTrue);
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

final _tinyPngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

class _BlockingCaptureTransaction implements CameraCaptureHandoffTransaction {
  final started = Completer<void>();
  final release = Completer<void>();
  bool finished = false;
  bool cleanedUp = false;

  @override
  Future<CameraCaptureResult> execute({
    required String imagePath,
    required CameraLookState look,
    required CameraImageRatio imageRatio,
    required CameraCaptureOrientation captureOrientation,
    required double zoomFactor,
    void Function(ProcessingJobPhase phase)? onPhase,
  }) async {
    onPhase?.call(ProcessingJobPhase.processing);
    started.complete();
    await release.future;
    onPhase?.call(ProcessingJobPhase.saving);
    finished = true;
    return CameraCaptureResult(
      savedUri: Uri.parse('media:/gallery/capture.jpg'),
      jpegBytes: _tinyPngBytes,
    );
  }

  @override
  Future<void> cleanupSource(String imagePath) async {
    cleanedUp = true;
  }
}
