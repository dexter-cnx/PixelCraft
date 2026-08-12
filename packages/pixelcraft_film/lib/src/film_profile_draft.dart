import 'package:pixelcraft_editing/pixelcraft_editing.dart';

/// Pure-Dart draft state used while creating or editing a reusable Film Profile.
///
/// This type owns product-level composition/default/reset behavior only. It does
/// not process pixels and does not make the resulting profile authoritative
/// image state; applying the resulting [FilmProfileV1] still flows through the
/// Rust recipe/commit path.
class FilmProfileDraft {
  FilmProfileDraft({
    this.existingId,
    this.name = 'My Film',
    this.description = '',
    this.baseFilmId = '',
    this.baseStrength = 1,
    Map<String, double>? parameters,
    List<String> tags = const [],
  })  : parameters = Map.unmodifiable(
          parameters ??
              {
                for (final spec in filmProfileParameterSpecs)
                  spec.id: spec.neutral,
              },
        ),
        tags = List.unmodifiable(tags);

  factory FilmProfileDraft.fromProfile(FilmProfileV1? profile) {
    if (profile == null) return FilmProfileDraft();
    return FilmProfileDraft(
      existingId: profile.id,
      name: profile.name,
      description: profile.description,
      baseFilmId: profile.baseFilmId,
      baseStrength: profile.baseStrength,
      parameters: {
        for (final spec in filmProfileParameterSpecs)
          spec.id: profile.parameters[spec.id] ?? spec.neutral,
      },
      tags: profile.tags,
    );
  }

  final String? existingId;
  final String name;
  final String description;
  final String baseFilmId;
  final double baseStrength;
  final Map<String, double> parameters;
  final List<String> tags;

  FilmProfileDraft copyWith({
    String? name,
    String? description,
    String? baseFilmId,
    double? baseStrength,
    Map<String, double>? parameters,
    List<String>? tags,
  }) {
    return FilmProfileDraft(
      existingId: existingId,
      name: name ?? this.name,
      description: description ?? this.description,
      baseFilmId: baseFilmId ?? this.baseFilmId,
      baseStrength: baseStrength ?? this.baseStrength,
      parameters: parameters ?? this.parameters,
      tags: tags ?? this.tags,
    );
  }

  double parameterValue(String id) {
    final spec = filmProfileParameterSpec(id);
    if (spec == null) {
      throw ArgumentError.value(id, 'id', 'Unknown Film Profile parameter');
    }
    return parameters[id] ?? spec.neutral;
  }

  FilmProfileDraft withParameter(String id, double value) {
    final spec = filmProfileParameterSpec(id);
    if (spec == null) {
      throw ArgumentError.value(id, 'id', 'Unknown Film Profile parameter');
    }
    return copyWith(
      parameters: {
        ...parameters,
        id: spec.clamp(value),
      },
    );
  }

  FilmProfileDraft resetParameter(String id) {
    final spec = filmProfileParameterSpec(id);
    if (spec == null) {
      throw ArgumentError.value(id, 'id', 'Unknown Film Profile parameter');
    }
    return withParameter(id, spec.neutral);
  }

  FilmProfileV1 toProfile({required String newId}) {
    final trimmedName = name.trim();
    return FilmProfileV1(
      id: existingId ?? newId,
      name: trimmedName.isEmpty ? 'Untitled Film' : trimmedName,
      description: description.trim(),
      origin: FilmProfileOrigin.user,
      baseFilmId: baseFilmId,
      baseStrength: baseStrength,
      parameters: parameters,
      tags: tags,
    );
  }

  static List<String> parseTags(String source) {
    return source
        .split(',')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList(growable: false);
  }
}
