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

  Future<void> commitContrastAdjustment(
    WidgetTester tester,
    FakeImageEngine engine,
  ) async {
    await tester.tap(find.text('contrast'));
    await tester.pump();

    final slider = find.byType(Slider);
    expect(slider, findsOneWidget);

    final gesture = await tester.startGesture(tester.getCenter(slider));
    await gesture.moveBy(const Offset(80, 0));
    await tester.pump();

    expect(engine.beginCalls, 0);
    expect(engine.previewCalls, 0);
    expect(engine.commitCalls, 0);

    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('loads editor and processes filter only after release', (tester) async {
    final engine = FakeImageEngine();
    await pumpEditor(tester, engine);

    expect(find.textContaining('Editor · 0/0 edits'), findsOneWidget);
    expect(find.text('brightness'), findsOneWidget);
    expect(find.text('Adjust'), findsOneWidget);

    await commitContrastAdjustment(tester, engine);

    expect(engine.beginCalls, 1);
    expect(engine.previewCalls, 1);
    expect(engine.commitCalls, 1);
    expect(find.textContaining('Editor · 1/1 edits'), findsOneWidget);

    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Rust 12.50 ms'), findsOneWidget);
  });

  testWidgets('creative filter previews apply immediately when tapped', (tester) async {
    final engine = FakeImageEngine();
    await pumpEditor(tester, engine);

    await tester.tap(find.text('Filters'));
    await tester.pumpAndSettle();

    expect(engine.filterPreviewGenerationCalls, 1);
    expect(find.byType(Slider), findsNothing);
    expect(find.text('grayscale'), findsOneWidget);
    expect(find.text('vintage'), findsOneWidget);
    expect(find.byType(Image), findsWidgets);
    expect(engine.commitCalls, 0);

    await tester.tap(find.text('vintage'));
    await tester.pumpAndSettle();

    expect(engine.activeFilter, 'vintage');
    expect(engine.lastValue, 1);
    expect(engine.commitCalls, 1);
    expect(find.textContaining('Editor · 1/1 edits'), findsOneWidget);
  });

  testWidgets('undo and redo buttons call background engine history', (tester) async {
    final engine = FakeImageEngine();
    await pumpEditor(tester, engine);

    final undoButton = find.widgetWithIcon(IconButton, Icons.undo);
    final redoButton = find.widgetWithIcon(IconButton, Icons.redo);

    expect(tester.widget<IconButton>(undoButton).onPressed, isNull);
    expect(tester.widget<IconButton>(redoButton).onPressed, isNull);

    await commitContrastAdjustment(tester, engine);
    expect(find.textContaining('Editor · 1/1 edits'), findsOneWidget);
    expect(tester.widget<IconButton>(undoButton).onPressed, isNotNull);

    await tester.tap(undoButton);
    await tester.pumpAndSettle();
    expect(engine.undoCalls, 1);
    expect(find.textContaining('Editor · 0/1 edits'), findsOneWidget);
    expect(tester.widget<IconButton>(redoButton).onPressed, isNotNull);

    await tester.tap(redoButton);
    await tester.pumpAndSettle();
    expect(engine.redoCalls, 1);
    expect(find.textContaining('Editor · 1/1 edits'), findsOneWidget);
  });
}
