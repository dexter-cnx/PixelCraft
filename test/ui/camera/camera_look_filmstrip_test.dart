import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcraft/ui/camera/camera_look_filmstrip.dart';

void main() {
  testWidgets('renders preview bytes and dispatches selection', (tester) async {
    final previewBytes = Uint8List.fromList(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ),
    );
    String? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CameraLookFilmstrip(
            items: [
              CameraLookFilmstripItem(
                id: 'original',
                label: 'Original',
                index: 0,
                previewBytes: previewBytes,
              ),
              const CameraLookFilmstripItem(
                id: 'film-a',
                label: 'Film A',
                index: 1,
              ),
            ],
            selectedId: 'original',
            onSelected: (id) => selected = id,
          ),
        ),
      ),
    );

    expect(find.byType(Image), findsOneWidget);
    await tester.tap(find.text('Film A'));
    expect(selected, 'film-a');
  });

  testWidgets('shows loading fallback while previews are generated', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CameraLookFilmstrip(
            items: const [
              CameraLookFilmstripItem(
                id: 'film-a',
                label: 'Film A',
                index: 0,
              ),
            ],
            selectedId: 'film-a',
            isLoadingPreviews: true,
            onSelected: (_) {},
          ),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
