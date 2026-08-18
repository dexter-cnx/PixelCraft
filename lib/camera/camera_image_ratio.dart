import 'dart:typed_data';
import 'dart:ui';

import 'package:shared_preferences/shared_preferences.dart';

enum CameraImageRatio { original, fourThree, threeTwo, square, sixteenNine }

/// `auto` is an internal runtime mode only. It is never exposed as a camera
/// setting; it resolves the selected ratio from the current device/view or,
/// for an actual capture, the JPEG's authoritative EXIF orientation.
enum CameraCaptureOrientation { auto, portrait, landscape }

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

  /// UI framing helper. Capture-time auto orientation is resolved separately
  /// from JPEG EXIF so a portrait-locked Flutter surface cannot corrupt the
  /// saved crop when the physical device was held landscape.
  double? get aspectRatio => aspectRatioFor(CameraCaptureOrientation.auto);

  double? aspectRatioFor(CameraCaptureOrientation orientation) {
    final landscape = landscapeAspectRatio;
    if (landscape == null || landscape == 1) return landscape;
    final resolved = orientation == CameraCaptureOrientation.auto
        ? _currentCaptureOrientation()
        : orientation;
    return resolved == CameraCaptureOrientation.landscape
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
    CameraCaptureOrientation orientation = CameraCaptureOrientation.auto,
  }) {
    final info = _readJpegInfo(jpegBytes);
    if (info == null) {
      throw const FormatException('Unable to read JPEG dimensions for ratio crop');
    }

    final swapsAxes = info.exifOrientation >= 5 && info.exifOrientation <= 8;
    final orientedWidth = swapsAxes ? info.height : info.width;
    final orientedHeight = swapsAxes ? info.width : info.height;
    final resolvedOrientation = orientation == CameraCaptureOrientation.auto
        ? (orientedWidth >= orientedHeight
              ? CameraCaptureOrientation.landscape
              : CameraCaptureOrientation.portrait)
        : orientation;
    final target = aspectRatioFor(resolvedOrientation);
    if (target == null) return null;

    // Rust decode normalizes EXIF before replaying edit operations, therefore
    // these normalized crop coordinates are intentionally calculated in the
    // same oriented pixel space rather than raw sensor/SOF dimensions.
    final sourceAspect = orientedWidth / orientedHeight;
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

CameraCaptureOrientation _currentCaptureOrientation() {
  final views = PlatformDispatcher.instance.views;
  if (views.isEmpty) return CameraCaptureOrientation.portrait;
  final size = views.first.physicalSize;
  return size.width > size.height
      ? CameraCaptureOrientation.landscape
      : CameraCaptureOrientation.portrait;
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

class _JpegInfo {
  const _JpegInfo({
    required this.width,
    required this.height,
    required this.exifOrientation,
  });

  final int width;
  final int height;
  final int exifOrientation;
}

_JpegInfo? _readJpegInfo(Uint8List bytes) {
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
    return null;
  }

  int? width;
  int? height;
  var exifOrientation = 1;
  var offset = 2;
  while (offset + 3 < bytes.length) {
    while (offset < bytes.length && bytes[offset] != 0xFF) {
      offset++;
    }
    while (offset < bytes.length && bytes[offset] == 0xFF) {
      offset++;
    }
    if (offset >= bytes.length) break;

    final marker = bytes[offset++];
    if (marker == 0xD8 || marker == 0xD9 || marker == 0x01) continue;
    if (marker == 0xDA) break;
    if (offset + 1 >= bytes.length) break;

    final segmentLength = (bytes[offset] << 8) | bytes[offset + 1];
    if (segmentLength < 2 || offset + segmentLength > bytes.length) break;

    if (marker == 0xE1 && segmentLength >= 10) {
      final payloadStart = offset + 2;
      final payloadEnd = offset + segmentLength;
      exifOrientation = _readExifOrientation(
        bytes,
        payloadStart,
        payloadEnd,
      );
    }

    final isSof = (marker >= 0xC0 && marker <= 0xC3) ||
        (marker >= 0xC5 && marker <= 0xC7) ||
        (marker >= 0xC9 && marker <= 0xCB) ||
        (marker >= 0xCD && marker <= 0xCF);
    if (isSof && segmentLength >= 7) {
      height = (bytes[offset + 3] << 8) | bytes[offset + 4];
      width = (bytes[offset + 5] << 8) | bytes[offset + 6];
    }

    offset += segmentLength;
  }

  if (width == null || height == null || width <= 0 || height <= 0) {
    return null;
  }
  return _JpegInfo(
    width: width,
    height: height,
    exifOrientation: exifOrientation,
  );
}

int _readExifOrientation(Uint8List bytes, int start, int end) {
  if (end - start < 14 ||
      bytes[start] != 0x45 ||
      bytes[start + 1] != 0x78 ||
      bytes[start + 2] != 0x69 ||
      bytes[start + 3] != 0x66 ||
      bytes[start + 4] != 0 ||
      bytes[start + 5] != 0) {
    return 1;
  }

  final tiff = start + 6;
  final littleEndian = bytes[tiff] == 0x49 && bytes[tiff + 1] == 0x49;
  final bigEndian = bytes[tiff] == 0x4D && bytes[tiff + 1] == 0x4D;
  if (!littleEndian && !bigEndian) return 1;

  int u16(int at) {
    if (at < tiff || at + 1 >= end) return 0;
    return littleEndian
        ? bytes[at] | (bytes[at + 1] << 8)
        : (bytes[at] << 8) | bytes[at + 1];
  }

  int u32(int at) {
    if (at < tiff || at + 3 >= end) return 0;
    return littleEndian
        ? bytes[at] |
              (bytes[at + 1] << 8) |
              (bytes[at + 2] << 16) |
              (bytes[at + 3] << 24)
        : (bytes[at] << 24) |
              (bytes[at + 1] << 16) |
              (bytes[at + 2] << 8) |
              bytes[at + 3];
  }

  if (u16(tiff + 2) != 42) return 1;
  final ifd0 = tiff + u32(tiff + 4);
  if (ifd0 < tiff || ifd0 + 2 > end) return 1;
  final count = u16(ifd0);
  for (var index = 0; index < count; index++) {
    final entry = ifd0 + 2 + index * 12;
    if (entry + 12 > end) break;
    if (u16(entry) != 0x0112) continue;
    final type = u16(entry + 2);
    final values = u32(entry + 4);
    if (type != 3 || values < 1) return 1;
    final value = u16(entry + 8);
    return value >= 1 && value <= 8 ? value : 1;
  }
  return 1;
}
