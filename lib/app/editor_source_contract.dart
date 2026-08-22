import 'package:flutter/foundation.dart';

import 'platform_flow_foundation.dart';

/// Format classification for an editor source.
///
/// This deliberately describes source identity separately from current decoder
/// capability. PF4 can preserve a source it cannot edit yet without redesigning
/// the contract when RAW/HEIF support is introduced later.
enum EditorSourceFormat { jpeg, png, heif, raw, unknown }

/// Immutable source identity handed from acquisition into the Product Editor.
///
/// [original] always points at the acquired source. Editing/export code must
/// treat it as read-only and write processed pixels to a different destination.
@immutable
class EditorSource {
  const EditorSource({required this.original, required this.format});

  final MediaSourceDescriptor original;
  final EditorSourceFormat format;

  Uri get uri => original.uri;
  MediaSourceProvenance get provenance => original.provenance;
  String? get mimeType => original.mimeType;
  String? get externalId => original.externalId;

  /// Camera look is transient camera state and must never leak into Gallery,
  /// desktop-open/drop, or future external-edit sources.
  bool get inheritsCameraLook => false;
}

/// Converts acquisition metadata into the format-aware PF4 editor contract.
class EditorSourceFactory {
  const EditorSourceFactory();

  EditorSource fromDescriptor(MediaSourceDescriptor descriptor) {
    return EditorSource(
      original: descriptor,
      format: classifyFormat(descriptor),
    );
  }

  EditorSourceFormat classifyFormat(MediaSourceDescriptor descriptor) {
    final mime = descriptor.mimeType?.trim().toLowerCase();
    if (mime != null && mime.isNotEmpty) {
      if (mime == 'image/jpeg' || mime == 'image/jpg') {
        return EditorSourceFormat.jpeg;
      }
      if (mime == 'image/png') return EditorSourceFormat.png;
      if (mime == 'image/heic' || mime == 'image/heif') {
        return EditorSourceFormat.heif;
      }
      if (_rawMimeTypes.contains(mime)) return EditorSourceFormat.raw;
    }

    final path = descriptor.uri.path.toLowerCase();
    final dot = path.lastIndexOf('.');
    final extension = dot < 0 ? '' : path.substring(dot + 1);
    return switch (extension) {
      'jpg' || 'jpeg' => EditorSourceFormat.jpeg,
      'png' => EditorSourceFormat.png,
      'heic' || 'heif' => EditorSourceFormat.heif,
      'dng' ||
      'arw' ||
      'cr2' ||
      'cr3' ||
      'nef' ||
      'raf' ||
      'orf' => EditorSourceFormat.raw,
      _ => EditorSourceFormat.unknown,
    };
  }

  static const _rawMimeTypes = <String>{
    'image/x-adobe-dng',
    'image/x-sony-arw',
    'image/x-canon-cr2',
    'image/x-canon-cr3',
    'image/x-nikon-nef',
    'image/x-fuji-raf',
    'image/x-olympus-orf',
  };
}

/// PF4.1 acquisition boundary used by Gallery -> Editor flows.
///
/// The picker owns acquisition only; it does not create a managed library copy,
/// mutate source pixels, apply CameraLook, or start an editor render.
class GalleryEditorSourceCoordinator {
  const GalleryEditorSourceCoordinator({
    required MediaPickerService picker,
    EditorSourceFactory factory = const EditorSourceFactory(),
  }) : this._(picker, factory);

  const GalleryEditorSourceCoordinator._(this._picker, this._factory);

  final MediaPickerService _picker;
  final EditorSourceFactory _factory;

  Future<EditorSource?> pickSource() async {
    final descriptor = await _picker.pickImage();
    if (descriptor == null) return null;
    return _factory.fromDescriptor(descriptor);
  }
}
