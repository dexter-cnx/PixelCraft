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
  testWidgets('zoom controls expose zoom percentage and Fit resets to 100%',
      (tester) async {
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

    expect(find.byKey(const ValueKey('editor_zoom_percent')), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('editor_zoom_in')));
    await tester.pump();
    expect(find.text('125%'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('editor_zoom_fit')));
    await tester.pump();
    expect(find.text('100%'), findsOneWidget);
  });
}
