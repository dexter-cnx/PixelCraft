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
}
