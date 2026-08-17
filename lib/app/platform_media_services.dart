import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:saver_gallery/saver_gallery.dart';

import 'platform_flow_foundation.dart';

/// Concrete PF adapter for selecting one image from the system gallery.
///
/// The returned descriptor carries source provenance only. It does not create
/// PixelCraft edit semantics or Nixin/DAM identity.
class ImagePickerMediaService implements MediaPickerService {
  ImagePickerMediaService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

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

/// Concrete mobile Gallery adapter for processed JPEG output.
///
/// PF3 feeds this service bytes produced by the authoritative Rust render;
/// this adapter deliberately owns only the platform save operation.
class GalleryMediaSaveService implements MediaSaveService {
  const GalleryMediaSaveService();

  @override
  Future<Uri> saveJpeg({
    required Uint8List bytes,
    String? suggestedName,
  }) async {
    final fileName = suggestedName ??
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

    // SaverGallery does not expose a stable cross-platform asset URI. Return a
    // logical media URI so callers do not incorrectly treat a cache path as the
    // persisted Gallery asset. PF3 can enrich the result contract if required.
    return Uri(
      scheme: 'media',
      path: '/gallery/$fileName',
    );
  }
}

/// Platform permission adapter for the PF camera flow.
///
/// Gallery-write permission is requested at Camera startup so the system
/// permission sheet never interrupts a shutter -> process -> save transaction.
/// Android 10+ reports granted immediately because adding a new MediaStore item
/// with PF3's `skipIfExists: false` path does not require legacy storage access.
class PlatformPermissionService implements PermissionService {
  const PlatformPermissionService();

  static const _channel = MethodChannel('dev.cnxdev.pixelcraft/permissions');

  @override
  Future<PermissionDecision> requestGalleryWrite() =>
      _request('requestGalleryWrite');

  @override
  Future<PermissionDecision> requestCamera() async => PermissionDecision.denied;

  @override
  Future<PermissionDecision> requestGalleryRead() async =>
      PermissionDecision.denied;

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
