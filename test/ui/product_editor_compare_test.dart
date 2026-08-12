import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcraft/state/editor_controller.dart';
import 'package:pixelcraft/ui/screens/product_editor_screen.dart';

import '../helpers/fake_image_engine.dart';

void main() {
  testWidgets('Compare button toggles original without changing edit semantics',
      (tester) async {
    final engine = FakeImageEngine();
    final container = ProviderContainer(
      overrides: [imageEngineProvider.overrideWithValue(engine)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: ProductEditorScreen(imageBytes: testPngBytes),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final compareButton =
        find.byKey(const ValueKey('editor_compare_button'));
    expect(compareButton, findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Before'), findsOneWidget);
    expect(container.read(editorProvider).showOriginal, isFalse);
    expect(engine.operations, isEmpty);

    await tester.tap(compareButton);
    await tester.pump();

    expect(container.read(editorProvider).showOriginal, isTrue);
    expect(find.widgetWithText(FilledButton, 'Edited'), findsOneWidget);
    expect(engine.operations, isEmpty);

    await tester.tap(compareButton);
    await tester.pump();

    expect(container.read(editorProvider).showOriginal, isFalse);
    expect(find.widgetWithText(FilledButton, 'Before'), findsOneWidget);
    expect(engine.operations, isEmpty);
  });
}
