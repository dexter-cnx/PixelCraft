import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcraft/state/editor_adjustment_catalog.dart';

void main() {
  test('core adjustment ids are unique and all resolve to a spec', () {
    expect(coreFilters.toSet().length, coreFilters.length);
    for (final id in coreFilters) {
      expect(adjustmentSpec(id).id, id);
    }
  });

  test('G5 tone color and finish contracts expose correct neutral values', () {
    expect(adjustmentSpec('exposure').neutral, 0);
    expect(adjustmentSpec('exposure').min, -2);
    expect(adjustmentSpec('exposure').max, 2);
    expect(adjustmentSpec('highlights').neutral, 0);
    expect(adjustmentSpec('shadows').neutral, 0);
    expect(adjustmentSpec('temperature').neutral, 0);
    expect(adjustmentSpec('tint').neutral, 0);
    expect(adjustmentSpec('vibrance').neutral, 0);
    expect(adjustmentSpec('vignette').neutral, 0);
    expect(adjustmentSpec('grain').neutral, 0);
  });

  test('legacy core neutral values stay aligned with Rust semantics', () {
    expect(adjustmentSpec('brightness').neutral, 1);
    expect(adjustmentSpec('contrast').neutral, 1);
    expect(adjustmentSpec('saturation').neutral, 1);
    expect(adjustmentSpec('gaussian_blur').neutral, 0);
    expect(adjustmentSpec('sharpen').neutral, 0);
  });
}
