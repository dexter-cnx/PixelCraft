import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pixelcraft/core/bridge.dart';
import 'package:pixelcraft/src/rust/api.dart' as rust;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native Rust engine loads, filters and builds histogram', (tester) async {
    await initializeRustBridge();

    final bytes = Uint8List.fromList(base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAFElEQVR4nGP8z8AARAwMjDAGAAQYAQHLR3GQAAAAAElFTkSuQmCC',
    ));

    final dimensions = rust.loadImage(bytes: bytes);
    expect(dimensions.$1, 2);
    expect(dimensions.$2, 2);

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
  });
}
