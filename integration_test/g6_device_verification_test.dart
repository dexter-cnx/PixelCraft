import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pixelcraft/core/bridge.dart';
import 'package:pixelcraft/src/rust/api.dart' as rust;

const String _mode = String.fromEnvironment('G6_MODE', defaultValue: 'reliability');
const int _cycles = int.fromEnvironment('G6_CYCLES', defaultValue: 10);
const int _durationMinutes = int.fromEnvironment('G6_DURATION_MIN', defaultValue: 15);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('G6 consolidated physical-device verification', (tester) async {
    await initializeRustBridge();

    if (_mode == 'thermal') {
      final completed = await _runThermalWorkload();
      // This sentinel is consumed by the shell runner. `flutter drive` can
      // occasionally return success after a physical-device session drops, so
      // the process exit code alone is not sufficient G6 evidence.
      // ignore: avoid_print
      print('PIXELCRAFT_G6_COMPLETE mode=thermal completed_cycles=$completed');
      return;
    }

    expect(_mode, 'reliability');
    expect(_cycles, greaterThan(0));

    await _runNativeSmoke();
    await _runPerformanceProfile();

    var completedCycles = 0;
    for (var cycle = 1; cycle <= _cycles; cycle++) {
      // ignore: avoid_print
      print('PIXELCRAFT_G6_CYCLE start=$cycle total=$_cycles');
      await _runSoakCycle(cycle: cycle);
      completedCycles = cycle;
      // ignore: avoid_print
      print('PIXELCRAFT_G6_CYCLE pass=$cycle total=$_cycles');
    }

    expect(completedCycles, _cycles);
    // Keep this as the final G6 application-side output. The device runner
    // requires it before accepting the session as valid evidence.
    // ignore: avoid_print
    print('PIXELCRAFT_G6_COMPLETE mode=reliability cycles=$completedCycles');
  });
}

Future<Uint8List> _sampleSource() async {
  return (await rootBundle.load('assets/samples/sample_1.png'))
      .buffer
      .asUint8List();
}

Future<void> _runNativeSmoke() async {
  final bytes = Uint8List.fromList(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    ),
  );

  final dimensions = rust.loadImage(bytes: bytes);
  expect(dimensions.$1, 1);
  expect(dimensions.$2, 1);

  final preview = rust.preparePreview(imageBytes: bytes, maxEdge: 1280);
  expect(preview, isNotEmpty);

  final histogram = rust.getHistogram(imageBytes: preview);
  expect(histogram.length, 768);

  final filtered = rust.applyFilterTimed(
    imageBytes: preview,
    filter: 'brightness',
    value: 1.1,
  );
  expect(filtered.bytes, isNotEmpty);
  expect(filtered.elapsedMicros, greaterThanOrEqualTo(BigInt.zero));

  final profiles = rust.filmProfiles();
  expect(profiles, hasLength(6));
  expect(
    profiles.map((profile) => profile.id).toSet(),
    containsAll(<String>{
      'provia_inspired',
      'velvia_inspired',
      'astia_inspired',
      'e100_inspired',
      'ektar_inspired',
      'chrome64_inspired',
    }),
  );

  final profiled = rust.applyFilmProfile(
    id: 'provia_inspired',
    strength: 0.75,
  );
  expect(profiled, isNotEmpty);
  expect(rust.sessionInfo().cursor, 1);

  final recipe = rust.exportSessionRecipe();
  expect(recipe, contains('provia_inspired'));

  final restored = rust.restoreSession(bytes: bytes, recipeJson: recipe);
  expect(restored, isNotEmpty);
  expect(rust.sessionInfo().cursor, 1);

  final exported = rust.exportImage(format: 'png', quality: 100);
  expect(exported, isNotEmpty);

  // ignore: avoid_print
  print('PIXELCRAFT_G6_NATIVE_SMOKE pass=1');
}

Future<void> _runPerformanceProfile() async {
  final source = await _sampleSource();
  final rssStart = ProcessInfo.currentRss;
  final total = Stopwatch()..start();

  final loadWatch = Stopwatch()..start();
  rust.loadImage(bytes: source);
  final preview = rust.preparePreview(imageBytes: source, maxEdge: 1024);
  loadWatch.stop();
  final rssAfterLoad = ProcessInfo.currentRss;

  final thumbnailsWatch = Stopwatch()..start();
  final profiles = rust.filmProfiles();
  final thumbnails = rust.generateFilmProfilePreviews(
    imageBytes: preview,
    profileIds: profiles.map((profile) => profile.id).toList(),
    maxEdge: 160,
  );
  thumbnailsWatch.stop();
  final rssAfterThumbnails = ProcessInfo.currentRss;

  final profileWatch = Stopwatch()..start();
  final profiled = rust.applyFilmProfile(
    id: 'provia_inspired',
    strength: 0.8,
  );
  profileWatch.stop();
  final rssAfterProfile = ProcessInfo.currentRss;

  final applyWatch = Stopwatch()..start();
  final checkpoint = rust.applyEdits();
  applyWatch.stop();

  final exportWatch = Stopwatch()..start();
  final exported = rust.exportImage(format: 'jpeg', quality: 90);
  exportWatch.stop();
  total.stop();
  final rssEnd = ProcessInfo.currentRss;

  expect(preview, isNotEmpty);
  expect(thumbnails.length, profiles.length);
  expect(profiled, isNotEmpty);
  expect(checkpoint, isNotEmpty);
  expect(exported, isNotEmpty);

  final rssPeak = <int>[
    rssAfterLoad,
    rssAfterThumbnails,
    rssAfterProfile,
    rssEnd,
  ].reduce((a, b) => a > b ? a : b);

  // ignore: avoid_print
  print('PIXELCRAFT_PROFILE load_preview_ms=${loadWatch.elapsedMilliseconds}');
  // ignore: avoid_print
  print('PIXELCRAFT_PROFILE film_thumbnails_ms=${thumbnailsWatch.elapsedMilliseconds}');
  // ignore: avoid_print
  print('PIXELCRAFT_PROFILE film_preview_ms=${profileWatch.elapsedMilliseconds}');
  // ignore: avoid_print
  print('PIXELCRAFT_PROFILE apply_checkpoint_ms=${applyWatch.elapsedMilliseconds}');
  // ignore: avoid_print
  print('PIXELCRAFT_PROFILE export_full_ms=${exportWatch.elapsedMilliseconds}');
  // ignore: avoid_print
  print('PIXELCRAFT_PROFILE total_ms=${total.elapsedMilliseconds}');
  // ignore: avoid_print
  print('PIXELCRAFT_MEMORY rss_start=$rssStart');
  // ignore: avoid_print
  print('PIXELCRAFT_MEMORY rss_after_load=$rssAfterLoad');
  // ignore: avoid_print
  print('PIXELCRAFT_MEMORY rss_after_thumbnails=$rssAfterThumbnails');
  // ignore: avoid_print
  print('PIXELCRAFT_MEMORY rss_after_profile=$rssAfterProfile');
  // ignore: avoid_print
  print('PIXELCRAFT_MEMORY rss_end=$rssEnd');
  // ignore: avoid_print
  print('PIXELCRAFT_MEMORY rss_peak_delta=${rssPeak - rssStart}');
}

Future<void> _runSoakCycle({required int cycle}) async {
  final source = await _sampleSource();
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
    expect(rust.commitFilter(), isNotEmpty);
  }

  expect(
    rust.applyFilmProfile(id: 'provia_inspired', strength: 0.75),
    isNotEmpty,
  );
  expect(rust.applyEdits(), isNotEmpty);

  rust.beginFilter(filter: 'contrast');
  rust.updateFilterPreview(filter: 'contrast', value: 0.9);
  rust.commitFilter();
  expect(rust.undo(), isNotEmpty);
  expect(rust.redo(), isNotEmpty);

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

  // ignore: avoid_print
  print('PIXELCRAFT_G6_SOAK cycle=$cycle total_ms=${total.elapsedMilliseconds}');
  // ignore: avoid_print
  print('PIXELCRAFT_G6_SOAK cycle=$cycle rss_start=$rssStart');
  // ignore: avoid_print
  print('PIXELCRAFT_G6_SOAK cycle=$cycle rss_end=$rssEnd');
  // ignore: avoid_print
  print('PIXELCRAFT_G6_SOAK cycle=$cycle rss_delta=${rssEnd - rssStart}');
  // ignore: avoid_print
  print('PIXELCRAFT_G6_SOAK cycle=$cycle recipe_bytes=${recipe.length}');
  // ignore: avoid_print
  print('PIXELCRAFT_G6_SOAK cycle=$cycle export_jpeg_bytes=${jpeg.length}');
  // ignore: avoid_print
  print('PIXELCRAFT_G6_SOAK cycle=$cycle export_png_bytes=${png.length}');
  // ignore: avoid_print
  print('PIXELCRAFT_G6_SOAK cycle=$cycle export_webp_bytes=${webp.length}');
}

Future<int> _runThermalWorkload() async {
  expect(_durationMinutes, greaterThan(0));
  final deadline = DateTime.now().add(Duration(minutes: _durationMinutes));
  var cycle = 0;

  // Keep one app process alive for the full observation window. Re-running
  // `flutter test` would uninstall/reinstall the test app each cycle and make
  // both lifecycle and thermal evidence invalid.
  while (DateTime.now().isBefore(deadline)) {
    cycle++;
    // ignore: avoid_print
    print('PIXELCRAFT_G6_THERMAL cycle=$cycle start=${DateTime.now().toUtc().toIso8601String()}');
    await _runPerformanceProfile();
    // ignore: avoid_print
    print('PIXELCRAFT_G6_THERMAL cycle=$cycle pass=${DateTime.now().toUtc().toIso8601String()}');
  }

  // ignore: avoid_print
  print('PIXELCRAFT_G6_THERMAL completed_cycles=$cycle');
  return cycle;
}
