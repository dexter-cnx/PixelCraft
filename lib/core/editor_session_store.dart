import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

class StoredEditorSession {
  const StoredEditorSession({
    required this.originalBytes,
    required this.recipeJson,
    required this.savedAt,
  });

  final Uint8List originalBytes;
  final String recipeJson;
  final DateTime savedAt;
}

class EditorSessionStore {
  EditorSessionStore({Directory? rootDirectory}) : _rootDirectory = rootDirectory;

  final Directory? _rootDirectory;
  Future<void> _writeTail = Future.value();

  Future<Directory> _directory() async {
    final root = _rootDirectory ?? await getApplicationSupportDirectory();
    return Directory('${root.path}/pixelcraft-session');
  }

  Future<bool> exists() async {
    try {
      final directory = await _directory();
      return File('${directory.path}/source.bin').existsSync() &&
          File('${directory.path}/recipe.json').existsSync();
    } catch (_) {
      return false;
    }
  }

  Future<StoredEditorSession?> load() async {
    try {
      final directory = await _directory();
      final source = File('${directory.path}/source.bin');
      final recipe = File('${directory.path}/recipe.json');
      if (!await source.exists() || !await recipe.exists()) return null;

      final originalBytes = await source.readAsBytes();
      final recipeJson = await recipe.readAsString();
      final metadata = File('${directory.path}/metadata.json');
      DateTime savedAt = DateTime.fromMillisecondsSinceEpoch(0);
      if (await metadata.exists()) {
        final decoded = jsonDecode(await metadata.readAsString());
        if (decoded case {'savedAt': final String value}) {
          savedAt = DateTime.tryParse(value) ?? savedAt;
        }
      }
      return StoredEditorSession(
        originalBytes: originalBytes,
        recipeJson: recipeJson,
        savedAt: savedAt,
      );
    } catch (_) {
      return null;
    }
  }

  /// The source image is only rewritten when a different image becomes the
  /// active session. Ordinary edits update only recipe.json + metadata.json.
  Future<void> save({
    required Uint8List originalBytes,
    required String recipeJson,
  }) {
    final completer = _writeTail.then((_) async {
      final directory = await _directory();
      await directory.create(recursive: true);
      final source = File('${directory.path}/source.bin');
      final sourceId = File('${directory.path}/source.id');
      final recipe = File('${directory.path}/recipe.json');
      final metadata = File('${directory.path}/metadata.json');
      final fingerprint = _fingerprint(originalBytes);

      final currentFingerprint =
          await sourceId.exists() ? await sourceId.readAsString() : null;
      if (!await source.exists() || currentFingerprint != fingerprint) {
        final sourceTemp = File('${source.path}.tmp');
        final sourceIdTemp = File('${sourceId.path}.tmp');
        await sourceTemp.writeAsBytes(originalBytes, flush: true);
        await sourceIdTemp.writeAsString(fingerprint, flush: true);
        if (await source.exists()) await source.delete();
        if (await sourceId.exists()) await sourceId.delete();
        await sourceTemp.rename(source.path);
        await sourceIdTemp.rename(sourceId.path);
      }

      final recipeTemp = File('${recipe.path}.tmp');
      final metadataTemp = File('${metadata.path}.tmp');
      await recipeTemp.writeAsString(recipeJson, flush: true);
      await metadataTemp.writeAsString(
        jsonEncode({'savedAt': DateTime.now().toUtc().toIso8601String()}),
        flush: true,
      );

      if (await recipe.exists()) await recipe.delete();
      if (await metadata.exists()) await metadata.delete();
      await recipeTemp.rename(recipe.path);
      await metadataTemp.rename(metadata.path);
    });
    _writeTail = completer.catchError((_) {});
    return completer;
  }

  Future<void> clear() {
    final completer = _writeTail.then((_) async {
      final directory = await _directory();
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });
    _writeTail = completer.catchError((_) {});
    return completer;
  }

  String _fingerprint(Uint8List bytes) {
    const sampleSize = 16;
    final prefix = bytes.take(sampleSize);
    final suffix = bytes.skip(bytes.length > sampleSize ? bytes.length - sampleSize : 0);
    String hex(Iterable<int> values) =>
        values.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    return '${bytes.length}:${hex(prefix)}:${hex(suffix)}';
  }
}
