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
    final file = File('${directory.path}/capture.png');
    await file.writeAsBytes(testPngBytes, flush: true);

    final engine = FakeImageEngine();
    final sessionStore = EditorSessionStore(rootDirectory: directory);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          imageEngineProvider.overrideWithValue(engine),
          editorSessionStoreProvider.overrideWithValue(sessionStore),
        ],
        child: MaterialApp(home: EditorScreen(imagePath: file.path)),
      ),
    );

    expect(find.text('Preparing photo…'), findsOneWidget);

    // Do not use pumpAndSettle while the preparing UI contains an indeterminate
    // CircularProgressIndicator. It continuously schedules animation frames and
    // can keep pumpAndSettle alive for minutes even though file I/O and editor
    // initialization have already completed. Poll the actual completion state
    // with a bounded timeout instead.
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (find.text('Preparing photo…').evaluate().isNotEmpty) {
      if (DateTime.now().isAfter(deadline)) {
        fail('Captured file did not finish loading within 2 seconds');
      }
      await tester.pump(const Duration(milliseconds: 16));
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }

    expect(engine.backgroundLoadCalls, 1);
    expect(find.textContaining('Editor · 0/0 edits'), findsOneWidget);
    expect(find.text('Preparing photo…'), findsNothing);
  });
}
