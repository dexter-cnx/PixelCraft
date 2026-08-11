import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcraft/state/editor_recipe_summary.dart';

void main() {
  String recipe({
    required List<Map<String, dynamic>> operations,
    required int cursor,
    required int checkpoint,
  }) => jsonEncode({
        'version': 1,
        'operations': operations,
        'cursor': cursor,
        'checkpoint_cursor': checkpoint,
      });

  test('summary separates applied checkpoint from active draft', () {
    final json = recipe(
      operations: [
        {'type': 'filter', 'name': 'brightness', 'value': 1.1},
        {'type': 'filter', 'name': 'contrast', 'value': 1.2},
        {'type': 'film_profile', 'id': 'velvia_inspired', 'strength': 0.8},
      ],
      cursor: 3,
      checkpoint: 1,
    );

    final summary = EditorRecipeSummary.fromRecipeJson(json);

    expect(summary.isAdjustmentChanged('brightness'), isFalse);
    expect(summary.adjustmentValue('contrast'), 1.2);
    expect(summary.isAdjustmentChanged('contrast'), isTrue);
    expect(summary.filmProfile, 'velvia_inspired');
    expect(summary.filmStrength, 0.8);
    expect(summary.history, hasLength(3));
    expect(summary.history.first.isApplied, isTrue);
    expect(summary.history.last.isApplied, isFalse);
  });

  test('reset current adjustment removes only its active draft slot', () {
    final json = recipe(
      operations: [
        {'type': 'filter', 'name': 'brightness', 'value': 1.2},
        {'type': 'filter', 'name': 'contrast', 'value': 1.3},
        {'type': 'film_profile', 'id': 'velvia_inspired', 'strength': 0.7},
      ],
      cursor: 3,
      checkpoint: 0,
    );

    final rewritten = EditorRecipeSummary.resetDraftAdjustment(
      json,
      'brightness',
    );
    final summary = EditorRecipeSummary.fromRecipeJson(rewritten);

    expect(summary.isAdjustmentChanged('brightness'), isFalse);
    expect(summary.isAdjustmentChanged('contrast'), isTrue);
    expect(summary.filmProfile, 'velvia_inspired');
    expect(summary.cursor, 2);
  });

  test('reset adjust preserves creative and film draft slots', () {
    final json = recipe(
      operations: [
        {'type': 'filter', 'name': 'brightness', 'value': 1.2},
        {'type': 'filter', 'name': 'contrast', 'value': 0.9},
        {'type': 'filter', 'name': 'vintage', 'value': 0.6},
        {'type': 'film_profile', 'id': 'astia_inspired', 'strength': 0.5},
      ],
      cursor: 4,
      checkpoint: 0,
    );

    final rewritten = EditorRecipeSummary.resetDraftAdjustments(json);
    final summary = EditorRecipeSummary.fromRecipeJson(rewritten);

    expect(summary.hasAdjustChanges, isFalse);
    expect(summary.creativeFilter, 'vintage');
    expect(summary.creativeIntensity, 0.6);
    expect(summary.filmProfile, 'astia_inspired');
    expect(summary.cursor, 2);
  });

  test('reset never removes applied checkpoint operations', () {
    final json = recipe(
      operations: [
        {'type': 'filter', 'name': 'brightness', 'value': 1.2},
        {'type': 'filter', 'name': 'brightness', 'value': 0.8},
      ],
      cursor: 2,
      checkpoint: 1,
    );

    final rewritten = EditorRecipeSummary.resetDraftAdjustments(json);
    final decoded = jsonDecode(rewritten) as Map<String, dynamic>;

    expect(decoded['checkpoint_cursor'], 1);
    expect(decoded['cursor'], 1);
    expect((decoded['operations'] as List).first['value'], 1.2);
  });
}
