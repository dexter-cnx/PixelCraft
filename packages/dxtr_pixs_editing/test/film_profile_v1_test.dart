import 'dart:convert';

import 'package:dxtr_pixs_editing/pixelcraft_editing.dart';
import 'package:test/test.dart';

void main() {
  test('FilmProfile V1 round trip clamps and omits neutral parameters', () {
    final profile = FilmProfileV1(
      id: 'summer',
      name: 'Summer Film',
      baseFilmId: 'provia_inspired',
      baseStrength: 0.8,
      parameters: const {
        'exposure': 0.5,
        'contrast': 1.0,
        'temperature': 4.0,
        'grain': 0.25,
      },
      tags: const ['portrait', 'warm'],
    );

    expect(profile.parameters.containsKey('contrast'), isFalse);
    expect(profile.parameters['temperature'], 1.0);

    final restored = FilmProfileV1.decode(profile.encode(pretty: false));
    expect(restored.id, 'summer');
    expect(restored.baseFilmId, 'provia_inspired');
    expect(restored.parameters['exposure'], 0.5);
    expect(restored.parameters['grain'], 0.25);
  });

  test('recipe importer reports exact approximate and unsupported fields', () {
    final report = importRecipeMap(
      const {
        'name': 'Imported',
        'exposure': 0.4,
        'highlightTone': -0.5,
        'mysteryVendorField': 7,
      },
      id: 'imported_1',
    );

    expect(report.profile.parameters['exposure'], 0.4);
    expect(report.profile.parameters['highlights'], -0.5);
    expect(
      report.mappings.any(
        (mapping) =>
            mapping.sourceField == 'exposure' &&
            mapping.kind == FilmProfileMappingKind.exact,
      ),
      isTrue,
    );
    expect(
      report.mappings.any(
        (mapping) =>
            mapping.sourceField == 'highlightTone' &&
            mapping.kind == FilmProfileMappingKind.approximated,
      ),
      isTrue,
    );
    expect(
      report.mappings.any(
        (mapping) =>
            mapping.sourceField == 'mysteryVendorField' &&
            mapping.kind == FilmProfileMappingKind.unsupported,
      ),
      isTrue,
    );
  });

  test('Film Profile materializes active draft and truncates redo tail', () {
    final recipe = jsonEncode({
      'version': 1,
      'preview_max_edge': 1024,
      'operations': [
        {'type': 'filter', 'name': 'brightness', 'value': 1.1},
        {'type': 'filter', 'name': 'contrast', 'value': 1.2},
        {'type': 'filter', 'name': 'saturation', 'value': 1.3},
      ],
      'cursor': 2,
      'checkpoint_cursor': 1,
    });
    final profile = FilmProfileV1(
      id: 'custom',
      name: 'Custom',
      baseFilmId: 'velvia_inspired',
      baseStrength: 0.75,
      parameters: const {
        'contrast': 0.9,
        'temperature': 0.3,
        'grain': 0.2,
      },
    );

    final materialized = jsonDecode(
      applyFilmProfileToSessionRecipe(recipe, profile),
    ) as Map<String, dynamic>;
    final operations = materialized['operations'] as List;

    expect(materialized['checkpoint_cursor'], 1);
    expect(materialized['cursor'], operations.length);
    expect(
      operations.any(
        (operation) =>
            operation['type'] == 'filter' &&
            operation['name'] == 'saturation',
      ),
      isFalse,
    );
    expect(
      operations
          .where(
            (operation) =>
                operation['type'] == 'filter' &&
                operation['name'] == 'contrast',
          )
          .single['value'],
      0.9,
    );
    expect(
      operations.any(
        (operation) =>
            operation['type'] == 'film_profile' &&
            operation['id'] == 'velvia_inspired',
      ),
      isTrue,
    );
  });
}
