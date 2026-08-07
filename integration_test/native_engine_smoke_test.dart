import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pixelcraft/core/bridge.dart';
import 'package:pixelcraft/src/rust/api.dart' as rust;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native Rust engine loads filters film and restores recipe', (tester) async {
    await initializeRustBridge();

    final bytes = Uint8List.fromList(base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    ));

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
    final profileIds = profiles.map((profile) => profile.id).toSet();
    expect(
      profileIds,
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
  });
}
