import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcraft/state/editor_controller.dart';
import 'package:pixelcraft/ui/screens/editor_screen.dart';

import '../helpers/fake_image_engine.dart';

void main() {
  testWidgets('loads editor and performs filter transaction', (tester) async {
    final engine = FakeImageEngine();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [imageEngineProvider.overrideWithValue(engine)],
        child: MaterialApp(home: EditorScreen(imageBytes: testPngBytes)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Editor'), findsOneWidget);
    expect(find.text('brightness'), findsOneWidget);
    expect(find.text('Rust 0.00 ms'), findsOneWidget);

    await tester.tap(find.text('contrast'));
    await tester.pump();

    final slider = find.byType(Slider);
    expect(slider, findsOneWidget);

    final center = tester.getCenter(slider);
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(80, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(engine.beginCalls, 1);
    expect(engine.previewCalls, greaterThanOrEqualTo(1));
    expect(engine.commitCalls, 1);
    expect(find.textContaining('Rust 12.50 ms'), findsOneWidget);
  });

  testWidgets('undo and redo buttons call engine history', (tester) async {
    final engine = FakeImageEngine();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [imageEngineProvider.overrideWithValue(engine)],
        child: MaterialApp(home: EditorScreen(imageBytes: testPngBytes)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Undo'));
    await tester.tap(find.byTooltip('Redo'));
    await tester.pump();

    expect(engine.undoCalls, 1);
    expect(engine.redoCalls, 1);
  });
}
