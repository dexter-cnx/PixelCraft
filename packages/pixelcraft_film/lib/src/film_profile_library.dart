import 'package:pixelcraft_editing/pixelcraft_editing.dart';

import 'film_profile_import_service.dart';
import 'film_profile_repository.dart';

class FilmProfileLibrary {
  FilmProfileLibrary(
    this._repository, {
    FilmProfileImportService importService = const FilmProfileImportService(),
  }) : _importService = importService;

  final FilmProfileRepository _repository;
  final FilmProfileImportService _importService;

  Future<List<FilmProfileV1>> loadAll() => _repository.loadAll();

  Future<void> save(FilmProfileV1 profile) {
    if (profile.isBuiltIn) {
      throw StateError(
        'Built-in Film Profiles are immutable; duplicate before editing.',
      );
    }
    return _repository.save(profile);
  }

  Future<void> delete(String id) => _repository.delete(id);

  Future<FilmProfileV1> duplicate(
    FilmProfileV1 source, {
    required String newId,
    String? newName,
  }) async {
    final duplicate = source.duplicate(newId: newId, newName: newName);
    await save(duplicate);
    return duplicate;
  }

  Future<FilmProfileImportResult> importSource(
    String source, {
    required String importedId,
    String? importedName,
  }) async {
    final result = _importService.parse(
      source,
      importedId: importedId,
      importedName: importedName,
    );
    await save(result.profile);
    return result;
  }
}
