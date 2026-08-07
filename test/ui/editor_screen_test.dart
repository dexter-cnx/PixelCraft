import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcraft/state/editor_controller.dart';
import 'package:pixelcraft/ui/screens/editor_screen.dart';

import '../helpers/fake_image_engine.dart';

void main() {
  Future<void> pumpEditor(WidgetTester tester, FakeImageEngine engine) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [imageEngineProvider.overrideWithValue(engine)],
        child: MaterialApp(home: EditorScreen(imageBytes: testPngBytes)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> commitContrastAdjustment(WidgetTester tester) async {
    await tester.tap(find.text('contrast'));
    await tester.pump();

    final slider = find.byType(Slider);
    expect(slider, findsOneWidget);

    final gesture = await tester.startGesture(tester.getCenter(slider));
    await gesture.moveBy(const Offset(80, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();
  }

  testWidgets('loads editor and performs filter transaction', (tester) async {
    final engine = FakeImageEngine();
    await pumpEditor(tester, engine);

    expect(find.textContaining('Editor · 0/0 edits'), findsOneWidget);
    expect(find.text('brightness'), findsOneWidget);
    expect(find.text('Rust 0.00 ms'), findsOneWidget);

    await commitContrastAdjustment(tester);

    expect(engine.beginCalls, 1);
    expect(engine.previewCalls, greaterThanOrEqualTo(1));
    expect(engine.commitCalls, 1);
    expect(find.textContaining('Editor · 1/1 edits'), findsOneWidget);
    expect(find.textContaining('Rust 12.50 ms'), findsOneWidget);
  });

  testWidgets('undo and redo buttons call engine history', (tester) async {
    final engine = FakeImageEngine();
    await pumpEditor(tester, engine);

    // Undo is intentionally disabled until there is a committed operation.
    expect(tester.widget<IconButton>(find.byTooltip('Undo')).onPressed, isNull);
    expect(tester.widget<IconButton>(find.byTooltip('Redo')).onPressed, isNull);

    await commitContrastAdjustment(tester);
    expect(find.textContaining('Editor · 1/1 edits'), findsOneWidget);

    await tester.tap(find.byTooltip('Undo'));
    await tester.pump();
    expect(engine.undoCalls, 1);
    expect(find.textContaining('Editor · 0/1 edits'), findsOneWidget);

    await tester.tap(find.byTooltip('Redo'));
    await tester.pump();
    expect(engine.redoCalls, 1);
    expect(find.textContaining('Editor · 1/1 edits'), findsOneWidget);
  });
}
