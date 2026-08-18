import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:saver_gallery/saver_gallery.dart';

import 'platform_flow_foundation.dart';

class ImagePickerMediaService implements MediaPickerService {
  ImagePickerMediaService({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<MediaSourceDescriptor?> pickImage() async {
    final image = await _picker.pickImage(source: ImageSource.gallery);
    if (image == null) return null;
    return MediaSourceDescriptor(
      uri: Uri.file(image.path),
      provenance: MediaSourceProvenance.gallery,
      mimeType: image.mimeType,
    );
  }
}

class GalleryMediaSaveService implements MediaSaveService {
  const GalleryMediaSaveService();

  @override
  Future<Uri> saveJpeg({
    required Uint8List bytes,
    String? suggestedName,
  }) async {
    final fileName =
        suggestedName ??
        'dxtr-pixs-${DateTime.now().toUtc().toIso8601String().replaceAll(':', '-')}.jpg';
    final result = await SaverGallery.saveImage(
      bytes,
      quality: 100,
      fileName: fileName,
      androidRelativePath: 'Pictures/Dxtr Pixs',
      skipIfExists: false,
    );
    if (!result.isSuccess) {
      throw StateError(result.errorMessage ?? 'Gallery save failed');
    }
    return Uri(scheme: 'media', path: '/gallery/$fileName');
  }
}

class PlatformPermissionService implements PermissionService {
  const PlatformPermissionService();

  static const _channel = MethodChannel('dev.cnxdev.pixelcraft/permissions');

  @override
  Future<PermissionDecision> requestCamera() => _request('requestCamera');

  @override
  Future<PermissionDecision> requestGalleryWrite() =>
      _request('requestGalleryWrite');

  @override
  Future<PermissionDecision> requestGalleryRead() =>
      _request('requestGalleryRead');

  Future<PermissionDecision> _request(String method) async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return PermissionDecision.denied;
    }
    final value = await _channel.invokeMethod<String>(method);
    return switch (value) {
      'granted' => PermissionDecision.granted,
      'restricted' => PermissionDecision.restricted,
      _ => PermissionDecision.denied,
    };
  }
}

final mediaPickerServiceProvider = Provider<MediaPickerService>(
  (ref) => ImagePickerMediaService(),
);

final mediaSaveServiceProvider = Provider<MediaSaveService>(
  (ref) => const GalleryMediaSaveService(),
);

final permissionServiceProvider = Provider<PermissionService>(
  (ref) => const PlatformPermissionService(),
);
