import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class ExportedFile {
  const ExportedFile({required this.path, required this.format});

  final String path;
  final String format;
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
    final file = File('${exportDirectory.path}/pixelcraft-$timestamp.$extension');
    await file.writeAsBytes(bytes, flush: true);
    return ExportedFile(path: file.path, format: normalized);
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
