import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcraft/core/editor_session_store.dart';
import 'package:pixelcraft/state/editor_controller.dart';
import 'package:pixelcraft/ui/screens/editor_screen.dart';

import '../helpers/fake_image_engine.dart';

void main() {
  testWidgets('editor reads a captured file after navigation', (tester) async {
    final directory = Directory.systemTemp.createTempSync('pixelcraft-camera-test-');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });

    final engine = FakeImageEngine();
    final sessionStore = EditorSessionStore(rootDirectory: directory);
    var requestedPath = '';

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          imageEngineProvider.overrideWithValue(engine),
          editorSessionStoreProvider.overrideWithValue(sessionStore),
          imageFileLoaderProvider.overrideWithValue((path) async {
            requestedPath = path;
            return testPngBytes;
          }),
        ],
        child: const MaterialApp(
          home: EditorScreen(imagePath: '/camera/capture.png'),
        ),
      ),
    );

    expect(find.text('Preparing photo and editing tools…'), findsOneWidget);

    // Advance only the frames needed by the async widget initialization. The
    // real File I/O is intentionally injected above so this widget test stays
    // deterministic and does not block on dart:io inside FakeAsync.
    for (var attempt = 0; attempt < 20; attempt++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (find.text('Preparing photo and editing tools…').evaluate().isEmpty) {
        break;
      }
    }

    expect(requestedPath, '/camera/capture.png');
    expect(engine.backgroundLoadCalls, 1);
    expect(find.text('Editor · Applied'), findsOneWidget);
    expect(find.text('Preparing photo and editing tools…'), findsNothing);
  });
}
