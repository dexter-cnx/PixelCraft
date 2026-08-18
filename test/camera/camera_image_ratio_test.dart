import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcraft/camera/camera_image_ratio.dart';

void main() {
  test('camera image ratio labels and persistence wire values are stable', () {
    expect(CameraImageRatio.original.label, 'Original');
    expect(CameraImageRatio.fourThree.wireName, '4:3');
    expect(CameraImageRatio.threeTwo.wireName, '3:2');
    expect(CameraImageRatio.square.wireName, '1:1');
    expect(CameraImageRatio.sixteenNine.wireName, '16:9');
    expect(CameraImageRatioX.parse('16:9'), CameraImageRatio.sixteenNine);
    expect(CameraImageRatioX.parse('unknown'), CameraImageRatio.original);
  });

  test('Original ratio does not request an authoritative crop', () {
    expect(CameraImageRatio.original.aspectRatio, isNull);
  });

  test('ratio labels resolve automatically for portrait and landscape capture', () {
    for (final landscape in [
      CameraCaptureOrientation.landscapeLeft,
      CameraCaptureOrientation.landscapeRight,
    ]) {
      expect(
        CameraImageRatio.fourThree.aspectRatioFor(landscape),
        closeTo(4 / 3, 0.000001),
      );
      expect(
        CameraImageRatio.threeTwo.aspectRatioFor(landscape),
        closeTo(3 / 2, 0.000001),
      );
      expect(
        CameraImageRatio.sixteenNine.aspectRatioFor(landscape),
        closeTo(16 / 9, 0.000001),
      );
      expect(CameraImageRatio.square.aspectRatioFor(landscape), 1);
    }

    for (final portrait in [
      CameraCaptureOrientation.portrait,
      CameraCaptureOrientation.portraitUpsideDown,
    ]) {
      expect(
        CameraImageRatio.fourThree.aspectRatioFor(portrait),
        closeTo(3 / 4, 0.000001),
      );
      expect(
        CameraImageRatio.threeTwo.aspectRatioFor(portrait),
        closeTo(2 / 3, 0.000001),
      );
      expect(
        CameraImageRatio.sixteenNine.aspectRatioFor(portrait),
        closeTo(9 / 16, 0.000001),
      );
      expect(CameraImageRatio.square.aspectRatioFor(portrait), 1);
    }
  });

  test('directional capture orientation maps to Rust quarter turns', () {
    expect(CameraCaptureOrientation.portrait.clockwiseQuarterTurns, 0);
    expect(CameraCaptureOrientation.landscapeLeft.clockwiseQuarterTurns, 1);
    expect(CameraCaptureOrientation.portraitUpsideDown.clockwiseQuarterTurns, 2);
    expect(CameraCaptureOrientation.landscapeRight.clockwiseQuarterTurns, 3);
  });
}
