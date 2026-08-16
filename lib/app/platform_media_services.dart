import 'dart:typed_data';

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
/// PF3 will feed this service bytes produced by the authoritative Rust render;
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

final mediaPickerServiceProvider = Provider<MediaPickerService>(
  (ref) => ImagePickerMediaService(),
);

final mediaSaveServiceProvider = Provider<MediaSaveService>(
  (ref) => const GalleryMediaSaveService(),
);
