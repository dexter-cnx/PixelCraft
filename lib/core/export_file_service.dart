import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:share_plus/share_plus.dart';

typedef ExportDirectoryProvider = Future<Directory> Function();
typedef GalleryImageSaver =
    Future<GallerySaveResult> Function(Uint8List bytes, String fileName);

class GallerySaveResult {
  const GallerySaveResult({required this.isSuccess, this.errorMessage});

  final bool isSuccess;
  final String? errorMessage;
}

class ExportedFile {
  const ExportedFile({
    required this.path,
    required this.format,
    required this.fileName,
    required this.savedToGallery,
    required this.gallerySaveAttempts,
    this.galleryError,
  });

  final String path;
  final String format;
  final String fileName;
  final bool savedToGallery;
  final int gallerySaveAttempts;
  final String? galleryError;

  ExportedFile copyWithGalleryResult({
    required bool savedToGallery,
    required int additionalAttempts,
    String? galleryError,
  }) => ExportedFile(
    path: path,
    format: format,
    fileName: fileName,
    savedToGallery: savedToGallery,
    gallerySaveAttempts: gallerySaveAttempts + additionalAttempts,
    galleryError: galleryError,
  );
}

class ExportFileService {
  const ExportFileService({
    ExportDirectoryProvider? directoryProvider,
    GalleryImageSaver? gallerySaver,
    bool? isMobilePlatform,
  }) : this._(directoryProvider, gallerySaver, isMobilePlatform);

  const ExportFileService._(
    this._directoryProvider,
    this._gallerySaver,
    this._isMobilePlatform,
  );

  final ExportDirectoryProvider? _directoryProvider;
  final GalleryImageSaver? _gallerySaver;
  final bool? _isMobilePlatform;

  bool get _shouldSaveToGallery =>
      _isMobilePlatform ?? (Platform.isAndroid || Platform.isIOS);

  Future<ExportedFile> save(Uint8List bytes, {required String format}) async {
    final directory =
        await (_directoryProvider?.call() ??
            getApplicationDocumentsDirectory());
    final exportDirectory = Directory('${directory.path}/PixelCraft Exports');
    await exportDirectory.create(recursive: true);

    final normalized = format.toLowerCase() == 'jpg'
        ? 'jpeg'
        : format.toLowerCase();
    final extension = normalized == 'jpeg' ? 'jpg' : normalized;
    final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(
      ':',
      '-',
    );
    final fileName = 'pixelcraft-$timestamp.$extension';
    final file = File('${exportDirectory.path}/$fileName');

    // The app-owned backup is committed first. Gallery integration is a
    // secondary destination and must never be able to destroy the only export.
    await file.writeAsBytes(bytes, flush: true);

    var galleryResult = const _GalleryAttemptResult(saved: false, attempts: 0);
    if (_shouldSaveToGallery) {
      galleryResult = await _saveGalleryWithRetry(bytes, fileName);
    }

    return ExportedFile(
      path: file.path,
      format: normalized,
      fileName: fileName,
      savedToGallery: galleryResult.saved,
      gallerySaveAttempts: galleryResult.attempts,
      galleryError: galleryResult.error,
    );
  }

  /// Retries Gallery persistence from the already committed app backup.
  ///
  /// This never re-renders or mutates the original editor source. It only reads
  /// the exported backup and retries the secondary Gallery destination.
  Future<ExportedFile> retryGallerySave(ExportedFile file) async {
    if (file.savedToGallery || !_shouldSaveToGallery) return file;

    final bytes = await File(file.path).readAsBytes();
    final result = await _saveGalleryWithRetry(bytes, file.fileName);
    return file.copyWithGalleryResult(
      savedToGallery: result.saved,
      additionalAttempts: result.attempts,
      galleryError: result.error,
    );
  }

  Future<_GalleryAttemptResult> _saveGalleryWithRetry(
    Uint8List bytes,
    String fileName,
  ) async {
    String? lastError;
    for (var attempt = 1; attempt <= 2; attempt++) {
      try {
        final result =
            await (_gallerySaver?.call(bytes, fileName) ??
                _defaultGallerySaver(bytes, fileName));
        if (result.isSuccess) {
          return _GalleryAttemptResult(saved: true, attempts: attempt);
        }
        lastError = result.errorMessage;
      } catch (error) {
        lastError = '$error';
      }
    }

    return _GalleryAttemptResult(saved: false, attempts: 2, error: lastError);
  }

  Future<GallerySaveResult> _defaultGallerySaver(
    Uint8List bytes,
    String fileName,
  ) async {
    final result = await SaverGallery.saveImage(
      bytes,
      quality: 100,
      fileName: fileName,
      androidRelativePath: 'Pictures/PixelCraft',
      skipIfExists: false,
    );
    return GallerySaveResult(
      isSuccess: result.isSuccess,
      errorMessage: result.errorMessage,
    );
  }

  Future<void> share(ExportedFile file) async {
    final mime = switch (file.format) {
      'jpeg' => 'image/jpeg',
      'webp' => 'image/webp',
      _ => 'image/png',
    };
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: mime)],
        text: 'Edited with Dextryx Pixels',
      ),
    );
  }
}

class _GalleryAttemptResult {
  const _GalleryAttemptResult({
    required this.saved,
    required this.attempts,
    this.error,
  });

  final bool saved;
  final int attempts;
  final String? error;
}
