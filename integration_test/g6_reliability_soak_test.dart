import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pixelcraft/core/bridge.dart';
import 'package:pixelcraft/src/rust/api.dart' as rust;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('G6 representative edit apply undo redo export cycle', (tester) async {
    await initializeRustBridge();
    final source = (await rootBundle.load('assets/samples/sample_1.png'))
        .buffer
        .asUint8List();

    final rssStart = ProcessInfo.currentRss;
    final total = Stopwatch()..start();

    rust.loadImage(bytes: source);
    final preview = rust.preparePreview(imageBytes: source, maxEdge: 1024);
    expect(preview, isNotEmpty);

    for (final adjustment in <(String, double)>[
      ('exposure', 0.25),
      ('highlights', -0.2),
      ('temperature', 0.15),
      ('grain', 0.12),
      ('curve_midtones', 0.1),
      ('hsl_blue_sat', -0.1),
      ('gaussian_blur', 0.2),
    ]) {
      rust.beginFilter(filter: adjustment.$1);
      final draft = rust.updateFilterPreview(
        filter: adjustment.$1,
        value: adjustment.$2,
      );
      expect(draft.bytes, isNotEmpty);
      final committed = rust.commitFilter();
      expect(committed, isNotEmpty);
    }

    final film = rust.applyFilmProfile(id: 'provia_inspired', strength: 0.75);
    expect(film, isNotEmpty);

    final checkpoint = rust.applyEdits();
    expect(checkpoint, isNotEmpty);

    // Add one draft after the checkpoint so Undo/Redo exercise real history.
    rust.beginFilter(filter: 'contrast');
    rust.updateFilterPreview(filter: 'contrast', value: 0.9);
    rust.commitFilter();

    final undone = rust.undo();
    expect(undone, isNotEmpty);
    final redone = rust.redo();
    expect(redone, isNotEmpty);

    final recipe = rust.exportSessionRecipe();
    expect(recipe, contains('operations'));

    final jpeg = rust.exportImage(format: 'jpeg', quality: 90);
    final png = rust.exportImage(format: 'png', quality: 100);
    final webp = rust.exportImage(format: 'webp', quality: 90);
    expect(jpeg, isNotEmpty);
    expect(png, isNotEmpty);
    expect(webp, isNotEmpty);

    total.stop();
    final rssEnd = ProcessInfo.currentRss;

    // Observational output only. Device-specific thresholds belong in recorded
    // G6 evidence, not in a cross-device integration assertion.
    // ignore: avoid_print
    print('PIXELCRAFT_G6_SOAK total_ms=${total.elapsedMilliseconds}');
    // ignore: avoid_print
    print('PIXELCRAFT_G6_SOAK rss_start=$rssStart');
    // ignore: avoid_print
    print('PIXELCRAFT_G6_SOAK rss_end=$rssEnd');
    // ignore: avoid_print
    print('PIXELCRAFT_G6_SOAK rss_delta=${rssEnd - rssStart}');
    // ignore: avoid_print
    print('PIXELCRAFT_G6_SOAK recipe_bytes=${recipe.length}');
    // ignore: avoid_print
    print('PIXELCRAFT_G6_SOAK export_jpeg_bytes=${jpeg.length}');
    // ignore: avoid_print
    print('PIXELCRAFT_G6_SOAK export_png_bytes=${png.length}');
    // ignore: avoid_print
    print('PIXELCRAFT_G6_SOAK export_webp_bytes=${webp.length}');
  });
}
