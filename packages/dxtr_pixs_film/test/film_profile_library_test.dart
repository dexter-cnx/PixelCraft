import 'package:dxtr_pixs_editing/pixelcraft_editing.dart';
import 'package:dxtr_pixs_film/pixelcraft_film.dart';
import 'package:test/test.dart';

class _MemoryRepository implements FilmProfileRepository {
  final Map<String, FilmProfileV1> items = {};

  @override
  Future<void> delete(String id) async {
    items.remove(id);
  }

  @override
  Future<List<FilmProfileV1>> loadAll() async => List.unmodifiable(items.values);

  @override
  Future<void> save(FilmProfileV1 profile) async {
    items[profile.id] = profile;
  }
}

void main() {
  test('duplicates a built-in profile as a user profile', () async {
    final repository = _MemoryRepository();
    final library = FilmProfileLibrary(repository);
    final source = FilmProfileV1(
      id: 'builtin',
      name: 'Built In',
      origin: FilmProfileOrigin.builtIn,
    );

    final duplicate = await library.duplicate(source, newId: 'user_1');

    expect(duplicate.id, 'user_1');
    expect(duplicate.origin, FilmProfileOrigin.user);
    expect(repository.items['user_1'], same(duplicate));
  });

  test('rejects direct mutation of built-in profiles', () async {
    final library = FilmProfileLibrary(_MemoryRepository());
    final source = FilmProfileV1(
      id: 'builtin',
      name: 'Built In',
      origin: FilmProfileOrigin.builtIn,
    );

    expect(() => library.save(source), throwsStateError);
  });

  test('imports PixelCraft profile JSON as imported origin', () async {
    final repository = _MemoryRepository();
    final library = FilmProfileLibrary(repository);
    final source = FilmProfileV1(id: 'shared', name: 'Shared Film').encode();

    final result = await library.importSource(
      source,
      importedId: 'unused_for_native_profile',
    );

    expect(result.sourceKind, FilmProfileImportSourceKind.pixelcraftProfile);
    expect(result.report, isNull);
    expect(result.profile.origin, FilmProfileOrigin.imported);
    expect(repository.items['shared']?.origin, FilmProfileOrigin.imported);
  });

  test('generic recipe import preserves mapping report', () async {
    final repository = _MemoryRepository();
    final library = FilmProfileLibrary(repository);

    final result = await library.importSource(
      '{"name":"Recipe","exposure":1.0,"unknownVendorField":7}',
      importedId: 'imported_1',
    );

    expect(result.sourceKind, FilmProfileImportSourceKind.genericRecipe);
    expect(result.profile.id, 'imported_1');
    expect(result.report, isNotNull);
    expect(result.report!.hasUnsupported, isTrue);
    expect(repository.items.containsKey('imported_1'), isTrue);
  });
}
