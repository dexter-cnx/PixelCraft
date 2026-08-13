import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcraft/ui/widgets/image_preview.dart';

final _tinyPng = Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  ),
);

void main() {
  Future<void> pumpPreview(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 500,
              height: 400,
              child: ImagePreview(bytes: _tinyPng),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('zoom controls expose zoom percentage and Fit resets to 100%',
      (tester) async {
    await pumpPreview(tester);

    expect(find.byKey(const ValueKey('editor_zoom_value')), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('editor_zoom_in')));
    await tester.pump();
    expect(find.text('125%'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('editor_zoom_fit')));
    await tester.pump();
    expect(find.text('100%'), findsOneWidget);
  });

  testWidgets('toolbar zoom preserves the viewport focal point after pan',
      (tester) async {
    await pumpPreview(tester);

    final viewerFinder =
        find.byKey(const ValueKey('editor_image_interactive_viewer'));
    final viewer = tester.widget<InteractiveViewer>(viewerFinder);
    final controller = viewer.transformationController!;

    controller.value = Matrix4.diagonal3Values(1.5, 1.5, 1.0)
      ..setTranslationRaw(40.0, 24.0, 0.0);
    await tester.pump();

    const viewportCenter = Offset(250, 200);
    final focalBefore = controller.toScene(viewportCenter);

    await tester.tap(find.byKey(const ValueKey('editor_zoom_in')));
    await tester.pump();

    final focalAfter = controller.toScene(viewportCenter);
    expect(controller.value.getMaxScaleOnAxis(), closeTo(1.75, 0.001));
    expect(focalAfter.dx, closeTo(focalBefore.dx, 0.001));
    expect(focalAfter.dy, closeTo(focalBefore.dy, 0.001));
    expect(controller.value.storage[12], isNot(closeTo(0.0, 0.001)));
    expect(controller.value.storage[13], isNot(closeTo(0.0, 0.001)));
  });
}
