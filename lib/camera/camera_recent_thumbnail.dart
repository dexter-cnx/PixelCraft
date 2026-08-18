import 'dart:typed_data';

import 'package:flutter/foundation.dart';

/// Session-level preview of the most recently processed and saved camera JPEG.
///
/// This deliberately uses the app's own saved output rather than requesting
/// broader Photo Library read access just to decorate the Gallery button.
class CameraRecentThumbnail {
  CameraRecentThumbnail._();

  static final CameraRecentThumbnail instance = CameraRecentThumbnail._();

  final ValueNotifier<Uint8List?> bytes = ValueNotifier<Uint8List?>(null);

  void update(Uint8List jpegBytes) {
    bytes.value = Uint8List.fromList(jpegBytes);
  }
}
