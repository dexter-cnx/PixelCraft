import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcraft/camera/camera_look_state.dart';

void main() {
  group('CameraLookState', () {
    test('starts neutral without active film or creative filter', () {
      final state = CameraLookState();

      expect(state.hasFilm, isFalse);
      expect(state.hasCreative, isFalse);
      expect(state.adjustmentValue('brightness'), 1);
      expect(state.adjustmentValue('contrast'), 1);
      expect(state.adjustmentValue('saturation'), 1);
    });

    test('keeps Film, Creative Filter and Adjust as independent layers', () {
      final state = CameraLookState()
          .withFilm('velvia_inspired', 0.8)
          .withCreative('golden', 0.65)
          .withAdjustment('contrast', 1.25);

      expect(state.filmProfileId, 'velvia_inspired');
      expect(state.filmStrength, 0.8);
      expect(state.creativeFilterId, 'golden');
      expect(state.creativeFilterStrength, 0.65);
      expect(state.adjustmentValue('contrast'), 1.25);
    });

    test('clamps camera preview values to canonical bounds', () {
      final state = CameraLookState()
          .withFilm('velvia_inspired', 4)
          .withCreative('vintage', -1)
          .withAdjustment('brightness', 99);

      expect(state.filmStrength, 1);
      expect(state.creativeFilterStrength, 0);
      expect(state.adjustmentValue('brightness'), 2);
    });

    test('rejects adjustments without a PF2 GPU parity contract', () {
      expect(
        () => CameraLookState().withAdjustment('unsupported_adjustment', 0.2),
        throwsArgumentError,
      );
    });

    test('maps Rust-generated creative presets to canonical GPU asset ids', () {
      expect(cameraCreativeFilter('vintage').gpuAssetId, 'creative_vintage');
      expect(
        cameraCreativeFilter('pastel_pink').gpuAssetId,
        'creative_pastel_pink',
      );
      expect(cameraCreativeFilter('grayscale').usesCanonicalLut, isFalse);
      expect(cameraCreativeFilter('invert').usesCanonicalLut, isFalse);
    });
  });
}
