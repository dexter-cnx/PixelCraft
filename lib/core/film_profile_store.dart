import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'film_profile_v1.dart';

class FilmProfileStore {
  FilmProfileStore({Future<Directory> Function()? directoryProvider})
      : _directoryProvider = directoryProvider ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _directoryProvider;

  Future<File> _file() async {
    final directory = await _directoryProvider();
    final folder = Directory('${directory.path}/pixelcraft_profiles');
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    return File('${folder.path}/profiles_v1.json');
  }

  Future<List<FilmProfileV1>> loadAll() async {
    final file = await _file();
    if (!await file.exists()) return const [];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return const [];
      final result = <FilmProfileV1>[];
      for (final item in decoded) {
        if (item is! Map<String, dynamic>) continue;
        try {
          result.add(FilmProfileV1.decode(jsonEncode(item)));
        } catch (_) {
          // Corrupt individual profiles fail closed instead of breaking the library.
        }
      }
      return List.unmodifiable(result);
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(FilmProfileV1 profile) async {
    if (profile.isBuiltIn) {
      throw StateError('Built-in Film Profiles are immutable; duplicate before editing.');
    }
    final profiles = (await loadAll()).toList();
    final index = profiles.indexWhere((item) => item.id == profile.id);
    if (index >= 0) {
      profiles[index] = profile;
    } else {
      profiles.add(profile);
    }
    await _writeAtomically(profiles);
  }

  Future<void> delete(String id) async {
    final profiles = (await loadAll()).where((item) => item.id != id).toList();
    await _writeAtomically(profiles);
  }

  Future<FilmProfileV1> importJson(String source) async {
    final decoded = FilmProfileV1.decode(source);
    final imported = decoded.copyWith(origin: FilmProfileOrigin.imported);
    await save(imported);
    return imported;
  }

  Future<void> _writeAtomically(List<FilmProfileV1> profiles) async {
    final file = await _file();
    final temp = File('${file.path}.tmp');
    final payload = const JsonEncoder.withIndent('  ')
        .convert(profiles.map((profile) => profile.toJson()).toList());
    await temp.writeAsString(payload, flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await temp.rename(file.path);
  }
}
