import 'dart:convert';

import 'film_profile_v1.dart';

/// Materializes a reusable [FilmProfileV1] into the active Rust session draft.
///
/// The session recipe remains the source of truth for committed semantics. This
/// helper only rewrites the draft portion of the JSON recipe and the caller must
/// restore the resulting recipe through the Rust engine before presenting it.
String applyFilmProfileToSessionRecipe(
  String recipeJson,
  FilmProfileV1 profile,
) {
  final decoded = jsonDecode(recipeJson);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Editor recipe must be a JSON object');
  }
  final rawOperations = decoded['operations'];
  final rawCursor = decoded['cursor'];
  final rawCheckpoint = decoded['checkpoint_cursor'];
  if (rawOperations is! List || rawCursor is! int || rawCheckpoint is! int) {
    throw const FormatException('Editor recipe has invalid bounds');
  }

  final cursor = rawCursor.clamp(0, rawOperations.length).toInt();
  final checkpoint = rawCheckpoint.clamp(0, cursor).toInt();
  final applied = List<dynamic>.from(rawOperations.take(checkpoint));
  final draft = List<dynamic>.from(
    rawOperations.skip(checkpoint).take(cursor - checkpoint),
  );

  void upsertFilter(String name, double value) {
    final index = draft.indexWhere(
      (operation) => operation is Map &&
          operation['type'] == 'filter' &&
          operation['name'] == name,
    );
    final replacement = <String, dynamic>{
      'type': 'filter',
      'name': name,
      'value': value,
    };
    if (index >= 0) {
      draft[index] = replacement;
    } else {
      draft.add(replacement);
    }
  }

  if (profile.baseFilmId.isNotEmpty) {
    final filmIndex = draft.indexWhere(
      (operation) => operation is Map && operation['type'] == 'film_profile',
    );
    final film = <String, dynamic>{
      'type': 'film_profile',
      'id': profile.baseFilmId,
      'strength': profile.baseStrength.clamp(0.0, 1.0).toDouble(),
    };
    if (filmIndex >= 0) {
      draft[filmIndex] = film;
    } else {
      draft.add(film);
    }
  }

  for (final entry in profile.parameters.entries) {
    final spec = filmProfileParameterSpec(entry.key);
    if (spec == null) {
      throw FormatException('Unsupported Film Profile parameter: ${entry.key}');
    }
    upsertFilter(entry.key, spec.clamp(entry.value));
  }

  decoded['operations'] = <dynamic>[...applied, ...draft];
  decoded['cursor'] = applied.length + draft.length;
  decoded['checkpoint_cursor'] = checkpoint;
  return jsonEncode(decoded);
}
