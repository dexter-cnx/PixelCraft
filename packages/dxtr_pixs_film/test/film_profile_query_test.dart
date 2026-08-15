import 'package:dxtr_pixs_editing/pixelcraft_editing.dart';
import 'package:dxtr_pixs_film/pixelcraft_film.dart';
import 'package:test/test.dart';

void main() {
  final profiles = [
    FilmProfileV1(
      id: 'portrait_soft',
      name: 'Portrait Soft',
      description: 'Gentle skin tones',
      origin: FilmProfileOrigin.user,
      baseFilmId: 'astia_inspired',
      tags: const ['portrait', 'soft'],
    ),
    FilmProfileV1(
      id: 'travel_import',
      name: 'Travel Chrome',
      description: 'Imported travel recipe',
      origin: FilmProfileOrigin.imported,
      baseFilmId: 'chrome64_inspired',
      tags: const ['travel'],
    ),
  ];

  test('empty query preserves repository order', () {
    expect(const FilmProfileQuery().apply(profiles), profiles);
  });

  test('matches name description base Film and tags case-insensitively', () {
    expect(FilmProfileQuery(text: 'portrait').apply(profiles), [profiles.first]);
    expect(FilmProfileQuery(text: 'SKIN').apply(profiles), [profiles.first]);
    expect(FilmProfileQuery(text: 'chrome64').apply(profiles), [profiles.last]);
    expect(FilmProfileQuery(text: 'TRAVEL').apply(profiles), [profiles.last]);
  });

  test('filters by selected origins and combines with text query', () {
    final imported = FilmProfileQuery(
      text: 'travel',
      origins: const {FilmProfileOrigin.imported},
    ).apply(profiles);
    expect(imported, [profiles.last]);

    final noMatch = FilmProfileQuery(
      text: 'travel',
      origins: const {FilmProfileOrigin.user},
    ).apply(profiles);
    expect(noMatch, isEmpty);
  });
}
