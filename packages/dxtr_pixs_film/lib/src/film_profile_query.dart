import 'package:dxtr_pixs_editing/pixelcraft_editing.dart';

/// Pure-Dart filtering for Film Profile library/search UIs.
///
/// An empty [origins] set means all origins. Text matching is case-insensitive
/// across user-facing metadata only and preserves repository order.
class FilmProfileQuery {
  const FilmProfileQuery({
    this.text = '',
    this.origins = const <FilmProfileOrigin>{},
  });

  final String text;
  final Set<FilmProfileOrigin> origins;

  bool matches(FilmProfileV1 profile) {
    if (origins.isNotEmpty && !origins.contains(profile.origin)) return false;

    final needle = text.trim().toLowerCase();
    if (needle.isEmpty) return true;

    final fields = <String>[
      profile.name,
      profile.description,
      profile.baseFilmId.replaceAll('_', ' '),
      ...profile.tags,
    ];
    return fields.any((field) => field.toLowerCase().contains(needle));
  }

  List<FilmProfileV1> apply(Iterable<FilmProfileV1> profiles) =>
      List<FilmProfileV1>.unmodifiable(profiles.where(matches));
}
