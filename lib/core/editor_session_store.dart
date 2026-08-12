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
  EditorSessionStore({this.rootDirectory});

  static const _generationVersion = 2;
  static const _generationsToKeep = 3;

  final Directory? rootDirectory;
  Future<void> _writeTail = Future.value();
  int _generationCounter = 0;

  Future<Directory> _directory() async {
    final root = rootDirectory ?? await getApplicationSupportDirectory();
    return Directory('${root.path}/pixelcraft-session');
  }

  Future<bool> exists() async => await load() != null;

  Future<StoredEditorSession?> load() async {
    try {
      await _writeTail;
      final directory = await _directory();
      if (!await directory.exists()) return null;
      await _deleteTemporaryFiles(directory);

      final generations = await _generationFiles(directory);
      for (final generation in generations) {
        final restored = await _loadGeneration(directory, generation);
        if (restored != null) return restored;
      }

      // Backward-compatible fallback for sessions written before the
      // generation-manifest format was introduced.
      return _loadLegacySession(directory);
    } catch (_) {
      return null;
    }
  }

  /// Persists one coherent recovery generation.
  ///
  /// Source and recipe payloads are immutable files. The generation manifest
  /// is written last and acts as the commit record that pairs them. If the
  /// process terminates before that final rename, the previous generation
  /// remains the latest complete recovery snapshot and source/recipe cannot be
  /// mixed across images.
  Future<void> save({
    required Uint8List originalBytes,
    required String recipeJson,
  }) {
    if (!_isRecipeEnvelopeValid(recipeJson)) {
      throw const FormatException('Refusing to persist an invalid editor recipe');
    }

    final completer = _writeTail.then((_) async {
      final directory = await _directory();
      await directory.create(recursive: true);
      await _deleteTemporaryFiles(directory);

      final fingerprint = _fingerprint(originalBytes);
      final safeFingerprint = fingerprint.replaceAll(':', '_');
      final sourceName = 'source.$safeFingerprint.bin';
      final source = File('${directory.path}/$sourceName');
      if (!await source.exists()) {
        final sourceTemp = File('${source.path}.tmp');
        await sourceTemp.writeAsBytes(originalBytes, flush: true);
        await sourceTemp.rename(source.path);
      }

      final generationId = _nextGenerationId();
      final recipeName = 'recipe.$generationId.json';
      final recipe = File('${directory.path}/$recipeName');
      final recipeTemp = File('${recipe.path}.tmp');
      await recipeTemp.writeAsString(recipeJson, flush: true);
      await recipeTemp.rename(recipe.path);

      final savedAt = DateTime.now().toUtc();
      final manifestName = 'generation.$generationId.json';
      final manifest = File('${directory.path}/$manifestName');
      final manifestTemp = File('${manifest.path}.tmp');
      await manifestTemp.writeAsString(
        jsonEncode({
          'version': _generationVersion,
          'sourceFile': sourceName,
          'recipeFile': recipeName,
          'sourceFingerprint': fingerprint,
          'savedAt': savedAt.toIso8601String(),
        }),
        flush: true,
      );

      // Publishing the manifest is the commit point for the generation.
      await manifestTemp.rename(manifest.path);
      await _pruneOldGenerations(directory);
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

  Future<List<File>> _generationFiles(Directory directory) async {
    final files = await directory
        .list()
        .where((entity) {
          if (entity is! File) return false;
          final name = entity.uri.pathSegments.last;
          return name.startsWith('generation.') && name.endsWith('.json');
        })
        .cast<File>()
        .toList();
    files.sort((left, right) => right.path.compareTo(left.path));
    return files;
  }

  Future<StoredEditorSession?> _loadGeneration(
    Directory directory,
    File manifest,
  ) async {
    try {
      final decoded = jsonDecode(await manifest.readAsString());
      if (decoded is! Map<String, dynamic> ||
          decoded['version'] != _generationVersion ||
          decoded['sourceFile'] is! String ||
          decoded['recipeFile'] is! String ||
          decoded['sourceFingerprint'] is! String ||
          decoded['savedAt'] is! String) {
        return null;
      }

      final source = File('${directory.path}/${decoded['sourceFile']}');
      final recipe = File('${directory.path}/${decoded['recipeFile']}');
      if (!await source.exists() || !await recipe.exists()) return null;

      final savedAt = DateTime.tryParse(decoded['savedAt'] as String);
      if (savedAt == null) return null;

      final originalBytes = await source.readAsBytes();
      if (_fingerprint(originalBytes) != decoded['sourceFingerprint']) {
        return null;
      }

      final recipeJson = await recipe.readAsString();
      if (!_isRecipeEnvelopeValid(recipeJson)) return null;

      return StoredEditorSession(
        originalBytes: originalBytes,
        recipeJson: recipeJson,
        savedAt: savedAt,
      );
    } catch (_) {
      return null;
    }
  }

  Future<StoredEditorSession?> _loadLegacySession(Directory directory) async {
    try {
      final source = File('${directory.path}/source.bin');
      final recipe = File('${directory.path}/recipe.json');
      if (!await source.exists() || !await recipe.exists()) return null;

      final metadata = File('${directory.path}/metadata.json');
      DateTime savedAt = DateTime.fromMillisecondsSinceEpoch(0);
      if (await metadata.exists()) {
        final decoded = jsonDecode(await metadata.readAsString());
        if (decoded case {'savedAt': final String value}) {
          savedAt = DateTime.tryParse(value) ?? savedAt;
        }
      }

      final recipeJson = await recipe.readAsString();
      if (!_isRecipeEnvelopeValid(recipeJson)) return null;

      return StoredEditorSession(
        originalBytes: await source.readAsBytes(),
        recipeJson: recipeJson,
        savedAt: savedAt,
      );
    } catch (_) {
      return null;
    }
  }

  bool _isRecipeEnvelopeValid(String recipeJson) {
    try {
      final decoded = jsonDecode(recipeJson);
      if (decoded is! Map<String, dynamic>) return false;
      final operations = decoded['operations'];
      final cursor = decoded['cursor'];
      final checkpoint = decoded['checkpoint_cursor'];
      if (operations is! List || cursor is! int || checkpoint is! int) {
        return false;
      }
      if (cursor < 0 || cursor > operations.length) return false;
      if (checkpoint < 0 || checkpoint > cursor) return false;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _pruneOldGenerations(Directory directory) async {
    try {
      await _deleteTemporaryFiles(directory);
      final generations = await _generationFiles(directory);
      if (generations.length <= _generationsToKeep) return;

      final kept = generations.take(_generationsToKeep).toList();
      final referenced = <String>{};
      for (final manifest in kept) {
        final decoded = jsonDecode(await manifest.readAsString());
        if (decoded case {
          'sourceFile': final String sourceFile,
          'recipeFile': final String recipeFile,
        }) {
          referenced
            ..add(sourceFile)
            ..add(recipeFile);
        }
      }

      for (final manifest in generations.skip(_generationsToKeep)) {
        if (await manifest.exists()) await manifest.delete();
      }

      await for (final entity in directory.list()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        final isPayload = name.startsWith('source.') || name.startsWith('recipe.');
        if (isPayload && !referenced.contains(name)) {
          await entity.delete();
        }
      }
    } catch (_) {
      // Cleanup is best-effort. Published generations remain valid if it fails.
    }
  }

  Future<void> _deleteTemporaryFiles(Directory directory) async {
    try {
      await for (final entity in directory.list()) {
        if (entity is! File) continue;
        if (entity.uri.pathSegments.last.endsWith('.tmp')) {
          await entity.delete();
        }
      }
    } catch (_) {
      // Stale temp cleanup is best-effort and must not invalidate recovery.
    }
  }

  String _nextGenerationId() {
    final micros = DateTime.now().microsecondsSinceEpoch.toString().padLeft(20, '0');
    final counter = (_generationCounter++).toString().padLeft(6, '0');
    return '$micros-$counter';
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
