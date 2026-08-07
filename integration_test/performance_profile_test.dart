import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pixelcraft/core/bridge.dart';
import 'package:pixelcraft/src/rust/api.dart' as rust;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('profiles preview film apply export and RSS', (tester) async {
    await initializeRustBridge();
    final source = (await rootBundle.load('assets/samples/sample_1.png'))
        .buffer
        .asUint8List();

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

    // Keep this test observational rather than setting brittle device-specific
    // performance thresholds. CI/device baselines can consume these metrics.
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
    print('PIXELCRAFT_MEMORY rss_peak_delta=${[
      rssAfterLoad,
      rssAfterThumbnails,
      rssAfterProfile,
      rssEnd,
    ].reduce((a, b) => a > b ? a : b) - rssStart}');
  });
}
