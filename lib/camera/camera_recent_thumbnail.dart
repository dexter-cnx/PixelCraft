import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Preview of the most recent image relevant to the Camera Gallery control.
///
/// On Camera entry this attempts to load the latest accessible system-gallery
/// image. After PixelCraft saves a new processed capture, [update] replaces it
/// immediately with that output.
class CameraRecentThumbnail {
  CameraRecentThumbnail._();

  static final CameraRecentThumbnail instance = CameraRecentThumbnail._();
  static const _channel = MethodChannel('dev.cnxdev.pixelcraft/permissions');

  final ValueNotifier<Uint8List?> bytes = ValueNotifier<Uint8List?>(null);
  Future<void>? _initialLoad;

  Future<void> ensureLoaded() => _initialLoad ??= _loadLatest();

  Future<void> _loadLatest() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return;
    }
    try {
      final latest = await _channel.invokeMethod<Uint8List>(
        'loadLatestGalleryThumbnail',
      );
      if (latest != null && latest.isNotEmpty) {
        bytes.value = Uint8List.fromList(latest);
      }
    } on PlatformException {
      // Permission denied, no accessible images, or platform query failure:
      // retain the normal Gallery fallback icon.
    }
  }

  void update(Uint8List jpegBytes) {
    bytes.value = Uint8List.fromList(jpegBytes);
  }
}
