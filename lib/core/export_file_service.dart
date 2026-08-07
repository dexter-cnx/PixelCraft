import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:share_plus/share_plus.dart';

class ExportedFile {
  const ExportedFile({
    required this.path,
    required this.format,
    required this.fileName,
    required this.savedToGallery,
    this.galleryError,
  });

  final String path;
  final String format;
  final String fileName;
  final bool savedToGallery;
  final String? galleryError;
}

class ExportFileService {
  const ExportFileService();

  Future<ExportedFile> save(Uint8List bytes, {required String format}) async {
    final directory = await getApplicationDocumentsDirectory();
    final exportDirectory = Directory('${directory.path}/PixelCraft Exports');
    await exportDirectory.create(recursive: true);

    final normalized = format.toLowerCase() == 'jpg' ? 'jpeg' : format.toLowerCase();
    final extension = normalized == 'jpeg' ? 'jpg' : normalized;
    final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
    final fileName = 'pixelcraft-$timestamp.$extension';
    final file = File('${exportDirectory.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);

    var savedToGallery = false;
    String? galleryError;
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        final result = await SaverGallery.saveImage(
          bytes,
          quality: 100,
          fileName: fileName,
          androidRelativePath: 'Pictures/PixelCraft',
          skipIfExists: false,
        );
        savedToGallery = result.isSuccess;
        galleryError = result.errorMessage;
      } catch (error) {
        galleryError = '$error';
      }
    }

    return ExportedFile(
      path: file.path,
      format: normalized,
      fileName: fileName,
      savedToGallery: savedToGallery,
      galleryError: galleryError,
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
        text: 'Edited with PixelCraft',
      ),
    );
  }
}
