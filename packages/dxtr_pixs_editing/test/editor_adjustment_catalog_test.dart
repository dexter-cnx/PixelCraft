import 'package:dxtr_pixs_editing/pixelcraft_editing.dart';
import 'package:test/test.dart';

void main() {
  test('semantic adjustment catalog preserves neutral values', () {
    expect(defaultAdjustmentValue('brightness'), 1);
    expect(defaultAdjustmentValue('contrast'), 1);
    expect(defaultAdjustmentValue('exposure'), 0);
    expect(defaultAdjustmentValue('sharpen'), 0);
    expect(defaultAdjustmentValue('gaussian_blur'), 0);
  });

  test('semantic adjustment catalog is backend agnostic', () {
    final brightness = adjustmentSpec('brightness');

    expect(brightness.id, 'brightness');
    expect(brightness.min, 0);
    expect(brightness.max, 2);
    expect(brightness.neutral, 1);
    expect(brightness.group, 'Light');
  });

  test('unknown adjustment ids fail explicitly', () {
    expect(
      () => adjustmentSpec('unknown-adjustment'),
      throwsA(isA<ArgumentError>()),
    );
  });
}
