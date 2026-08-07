import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
    await tester.pumpWidget(
      ProviderScope(
        overrides: [imageEngineProvider.overrideWithValue(engine)],
        child: MaterialApp(home: EditorScreen(imagePath: file.path)),
      ),
    );

    expect(find.text('Preparing photo…'), findsOneWidget);
    await tester.pumpAndSettle();

    expect(engine.backgroundLoadCalls, 1);
    expect(find.textContaining('Editor · 0/0 edits'), findsOneWidget);
    expect(find.text('Preparing photo…'), findsNothing);
  });
}
