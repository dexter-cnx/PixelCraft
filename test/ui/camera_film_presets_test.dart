import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcraft/camera/camera_film_presets.dart';

void main() {
  test('Film Camera exposes original plus all six Film Profile Pack v2 ids', () {
    expect(
      cameraFilmPresets.map((preset) => preset.id),
      <String>[
        '',
        'provia_inspired',
        'velvia_inspired',
        'astia_inspired',
        'e100_inspired',
        'ektar_inspired',
        'chrome64_inspired',
      ],
    );
  });

  test('zero preview strength resolves to the identity matrix', () {
    final preset = cameraFilmPresets[2];

    expect(
      interpolateColorMatrix(preset.matrix, 0),
      identityColorMatrix,
    );
  });

  test('full preview strength resolves to the preset matrix', () {
    final preset = cameraFilmPresets[2];

    expect(
      interpolateColorMatrix(preset.matrix, 1),
      preset.matrix,
    );
  });
}
