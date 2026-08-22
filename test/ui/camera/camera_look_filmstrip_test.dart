import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcraft/camera/camera_recent_thumbnail.dart';
import 'package:pixelcraft/ui/camera/camera_look_filmstrip.dart';

void main() {
  late Uint8List previewBytes;

  setUp(() {
    previewBytes = Uint8List.fromList(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ),
    );
    CameraRecentThumbnail.instance.update(previewBytes);
  });

  testWidgets('renders preview bytes and dispatches selection', (tester) async {
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

    expect(find.byType(Image), findsNWidgets(2));
    await tester.tap(find.text('Film A'));
    expect(selected, 'film-a');
  });

  testWidgets('applies film fallback and loading indicator', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CameraLookFilmstrip(
            items: const [
              CameraLookFilmstripItem(
                id: 'provia_inspired',
                label: 'Provia',
                index: 0,
              ),
            ],
            selectedId: 'provia_inspired',
            isLoadingPreviews: true,
            onSelected: (_) {},
          ),
        ),
      ),
    );

    expect(find.byType(ColorFiltered), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
