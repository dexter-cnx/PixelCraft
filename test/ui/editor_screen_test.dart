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

  Future<void> tapTool(WidgetTester tester, String label) async {
    final finder = find.text(label);
    expect(finder, findsOneWidget);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> commitContrastAdjustment(
    WidgetTester tester,
    FakeImageEngine engine,
  ) async {
    await tester.tap(find.text('Contrast'));
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

  testWidgets('loads editor and processes adjust filter only after release', (tester) async {
    final engine = FakeImageEngine();
    await pumpEditor(tester, engine);

    expect(find.text('Editor · Applied'), findsOneWidget);
    expect(find.text('Brightness'), findsOneWidget);
    expect(find.text('Adjust'), findsOneWidget);
    expect(find.text('Film'), findsOneWidget);

    await commitContrastAdjustment(tester, engine);

    expect(engine.beginCalls, 1);
    expect(engine.previewCalls, 1);
    expect(engine.commitCalls, 1);
    expect(find.text('Editor · Draft 1 edits'), findsOneWidget);
    expect(find.byKey(const ValueKey('apply_edits_button')), findsOneWidget);
    expect(find.byKey(const ValueKey('cancel_edits_button')), findsOneWidget);

    await tapTool(tester, 'Details');
    expect(find.textContaining('Rust 12.50 ms'), findsOneWidget);
  });

  testWidgets('creative filters use prewarmed previews and show intensity after selection', (tester) async {
    final engine = FakeImageEngine();
    await pumpEditor(tester, engine);

    expect(engine.filterPreviewGenerationCalls, 1);
    await tapTool(tester, 'Filters');

    expect(engine.filterPreviewGenerationCalls, 1);
    expect(find.byType(Slider), findsNothing);
    expect(find.text('grayscale'), findsOneWidget);
    expect(find.text('vintage'), findsOneWidget);
    expect(find.byType(Image), findsWidgets);

    await tester.tap(find.text('vintage'));
    await tester.pumpAndSettle();

    expect(engine.activeFilter, 'vintage');
    expect(engine.lastValue, 1);
    expect(engine.operations, hasLength(1));
    expect(engine.operations.single['name'], 'vintage');
    expect(find.text('vintage intensity'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
    expect(find.text('Editor · Draft 1 edits'), findsOneWidget);

    await tester.tap(find.text('oceanic'));
    await tester.pumpAndSettle();

    expect(engine.activeFilter, 'oceanic');
    expect(engine.operations, hasLength(1));
    expect(engine.operations.single['name'], 'oceanic');
    expect(engine.filterPreviewGenerationCalls, 1);
    expect(find.text('Editor · Draft 1 edits'), findsOneWidget);
  });

  testWidgets('film profiles use thumbnails and strength slider', (tester) async {
    final engine = FakeImageEngine();
    await pumpEditor(tester, engine);

    expect(engine.filmPreviewGenerationCalls, 1);
    await tapTool(tester, 'Film');

    expect(find.text('Provia Inspired'), findsOneWidget);
    expect(find.text('E100 Inspired'), findsOneWidget);
    expect(find.byType(Slider), findsNothing);

    await tester.tap(find.text('Provia Inspired'));
    await tester.pumpAndSettle();

    expect(engine.activeFilmProfile, 'provia_inspired');
    expect(engine.operations, hasLength(1));
    expect(engine.operations.single['type'], 'film_profile');
    expect(engine.operations.single['id'], 'provia_inspired');
    expect(find.text('Provia Inspired strength'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
    expect(find.text('Editor · Draft 1 edits'), findsOneWidget);
  });

  testWidgets('creative filter intensity processes only when slider is released', (tester) async {
    final engine = FakeImageEngine();
    await pumpEditor(tester, engine);
    await tapTool(tester, 'Filters');
    await tester.tap(find.text('vintage'));
    await tester.pumpAndSettle();

    final slider = find.byType(Slider);
    final restoreCallsBeforeDrag = engine.restoreSessionCalls;
    final gesture = await tester.startGesture(tester.getCenter(slider));
    await gesture.moveBy(const Offset(-50, 0));
    await tester.pump();
    expect(engine.restoreSessionCalls, restoreCallsBeforeDrag);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(engine.restoreSessionCalls, restoreCallsBeforeDrag + 1);
    expect(engine.operations, hasLength(1));
    expect(engine.operations.single['name'], 'vintage');
    expect(engine.operations.single['value'], isNot(1));
    expect(find.text('Editor · Draft 1 edits'), findsOneWidget);
  });

  testWidgets('Apply promotes current draft and resets film selection', (tester) async {
    final engine = FakeImageEngine();
    await pumpEditor(tester, engine);
    await tapTool(tester, 'Film');
    await tester.tap(find.text('Provia Inspired'));
    await tester.pumpAndSettle();

    final applyButton = find.byKey(const ValueKey('apply_edits_button'));
    expect(tester.widget<FilledButton>(applyButton).onPressed, isNotNull);

    await tester.tap(applyButton);
    await tester.pumpAndSettle();

    expect(engine.applyEditsCalls, 1);
    expect(find.text('Editor · Applied'), findsOneWidget);
    expect(find.text('Provia Inspired strength'), findsNothing);
  });

  testWidgets('Cancel discards current draft and returns to checkpoint', (tester) async {
    final engine = FakeImageEngine();
    await pumpEditor(tester, engine);
    await commitContrastAdjustment(tester, engine);

    final cancelButton = find.byKey(const ValueKey('cancel_edits_button'));
    expect(tester.widget<OutlinedButton>(cancelButton).onPressed, isNotNull);

    await tester.tap(cancelButton);
    await tester.pumpAndSettle();

    expect(engine.discardEditsCalls, 1);
    expect(find.text('Editor · Applied'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(cancelButton).onPressed, isNull);
  });

  testWidgets('undo and redo buttons call background engine history', (tester) async {
    final engine = FakeImageEngine();
    await pumpEditor(tester, engine);

    final undoButton = find.widgetWithIcon(IconButton, Icons.undo);
    final redoButton = find.widgetWithIcon(IconButton, Icons.redo);

    expect(tester.widget<IconButton>(undoButton).onPressed, isNull);
    expect(tester.widget<IconButton>(redoButton).onPressed, isNull);

    await commitContrastAdjustment(tester, engine);
    expect(find.text('Editor · Draft 1 edits'), findsOneWidget);
    expect(tester.widget<IconButton>(undoButton).onPressed, isNotNull);

    await tester.tap(undoButton);
    await tester.pumpAndSettle();
    expect(engine.undoCalls, 1);
    expect(find.text('Editor · Applied'), findsOneWidget);
    expect(tester.widget<IconButton>(redoButton).onPressed, isNotNull);

    await tester.tap(redoButton);
    await tester.pumpAndSettle();
    expect(engine.redoCalls, 1);
    expect(find.text('Editor · Draft 1 edits'), findsOneWidget);
  });
}
