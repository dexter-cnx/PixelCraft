import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

enum CameraImageRatio { original, fourThree, threeTwo, square, sixteenNine }

enum CameraCaptureOrientation { portrait, landscape }

extension CameraImageRatioX on CameraImageRatio {
  static const preferenceKey = 'camera.image_ratio';

  String get wireName => switch (this) {
    CameraImageRatio.original => 'original',
    CameraImageRatio.fourThree => '4:3',
    CameraImageRatio.threeTwo => '3:2',
    CameraImageRatio.square => '1:1',
    CameraImageRatio.sixteenNine => '16:9',
  };

  String get label => wireName == 'original' ? 'Original' : wireName;

  double? get landscapeAspectRatio => switch (this) {
    CameraImageRatio.original => null,
    CameraImageRatio.fourThree => 4 / 3,
    CameraImageRatio.threeTwo => 3 / 2,
    CameraImageRatio.square => 1,
    CameraImageRatio.sixteenNine => 16 / 9,
  };

  double? aspectRatioFor(CameraCaptureOrientation orientation) {
    final landscape = landscapeAspectRatio;
    if (landscape == null || landscape == 1) return landscape;
    return orientation == CameraCaptureOrientation.landscape
        ? landscape
        : 1 / landscape;
  }

  static CameraImageRatio parse(String? value) => switch (value) {
    '4:3' => CameraImageRatio.fourThree,
    '3:2' => CameraImageRatio.threeTwo,
    '1:1' => CameraImageRatio.square,
    '16:9' => CameraImageRatio.sixteenNine,
    _ => CameraImageRatio.original,
  };

  Future<void> persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(preferenceKey, wireName);
  }

  static Future<CameraImageRatio> load() async {
    final prefs = await SharedPreferences.getInstance();
    return parse(prefs.getString(preferenceKey));
  }

  NormalizedCrop? cropForJpeg(
    Uint8List jpegBytes, {
    required CameraCaptureOrientation orientation,
  }) {
    final target = aspectRatioFor(orientation);
    if (target == null) return null;
    final dimensions = _readJpegDimensions(jpegBytes);
    if (dimensions == null) {
      throw const FormatException('Unable to read JPEG dimensions for ratio crop');
    }
    final sourceAspect = dimensions.width / dimensions.height;
    if ((sourceAspect - target).abs() < 0.000001) {
      return const NormalizedCrop(x: 0, y: 0, width: 1, height: 1);
    }
    if (sourceAspect > target) {
      final width = target / sourceAspect;
      return NormalizedCrop(
        x: (1 - width) / 2,
        y: 0,
        width: width,
        height: 1,
      );
    }
    final height = sourceAspect / target;
    return NormalizedCrop(
      x: 0,
      y: (1 - height) / 2,
      width: 1,
      height: height,
    );
  }
}

class NormalizedCrop {
  const NormalizedCrop({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final double x;
  final double y;
  final double width;
  final double height;
}

({int width, int height})? _readJpegDimensions(Uint8List bytes) {
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
    return null;
  }

  var offset = 2;
  while (offset + 3 < bytes.length) {
    while (offset < bytes.length && bytes[offset] != 0xFF) {
      offset++;
    }
    while (offset < bytes.length && bytes[offset] == 0xFF) {
      offset++;
    }
    if (offset >= bytes.length) return null;

    final marker = bytes[offset++];
    if (marker == 0xD8 || marker == 0xD9 || marker == 0x01) continue;
    if (offset + 1 >= bytes.length) return null;

    final segmentLength = (bytes[offset] << 8) | bytes[offset + 1];
    if (segmentLength < 2 || offset + segmentLength > bytes.length) return null;

    final isSof = (marker >= 0xC0 && marker <= 0xC3) ||
        (marker >= 0xC5 && marker <= 0xC7) ||
        (marker >= 0xC9 && marker <= 0xCB) ||
        (marker >= 0xCD && marker <= 0xCF);
    if (isSof) {
      if (segmentLength < 7) return null;
      final height = (bytes[offset + 3] << 8) | bytes[offset + 4];
      final width = (bytes[offset + 5] << 8) | bytes[offset + 6];
      if (width <= 0 || height <= 0) return null;
      return (width: width, height: height);
    }

    offset += segmentLength;
  }
  return null;
}
