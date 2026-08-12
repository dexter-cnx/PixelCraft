import 'dart:convert';

import 'editor_controller.dart';

class EditorHistoryEntry {
  const EditorHistoryEntry({
    required this.index,
    required this.label,
    required this.isApplied,
  });

  final int index;
  final String label;
  final bool isApplied;
}

class EditorRecipeSummary {
  const EditorRecipeSummary({
    this.adjustments = const {},
    this.creativeFilter = '',
    this.creativeIntensity = 1,
    this.filmProfile = '',
    this.filmStrength = 1,
    this.history = const [],
    this.cursor = 0,
    this.checkpointCursor = 0,
  });

  final Map<String, double> adjustments;
  final String creativeFilter;
  final double creativeIntensity;
  final String filmProfile;
  final double filmStrength;
  final List<EditorHistoryEntry> history;
  final int cursor;
  final int checkpointCursor;

  bool get hasAdjustChanges => adjustments.entries.any(
        (entry) => !isNeutralAdjustment(entry.key, entry.value),
      );
  bool get hasCreativeChange => creativeFilter.isNotEmpty;
  bool get hasFilmChange => filmProfile.isNotEmpty;
  bool get hasDraft => cursor > checkpointCursor;

  double adjustmentValue(String filter) =>
      adjustments[filter] ?? defaultAdjustmentValue(filter);

  bool isAdjustmentChanged(String filter) =>
      !isNeutralAdjustment(filter, adjustmentValue(filter));

  static bool isNeutralAdjustment(String filter, double value) =>
      (value - defaultAdjustmentValue(filter)).abs() < 0.000001;

  factory EditorRecipeSummary.fromRecipeJson(String recipeJson) {
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
    final adjustments = <String, double>{};
    var creative = '';
    var creativeIntensity = 1.0;
    var film = '';
    var filmStrength = 1.0;
    final history = <EditorHistoryEntry>[];

    for (var index = 0; index < cursor; index++) {
      final operation = rawOperations[index];
      if (operation is! Map) continue;
      final applied = index < checkpoint;
      history.add(
        EditorHistoryEntry(
          index: index,
          label: _operationLabel(operation),
          isApplied: applied,
        ),
      );
      if (applied) continue;

      final type = operation['type'];
      if (type == 'filter') {
        final name = operation['name'];
        final value = operation['value'];
        if (name is! String || value is! num) continue;
        if (coreFilters.contains(name)) {
          adjustments[name] = value.toDouble();
        } else if (creativeFilters.contains(name)) {
          creative = name;
          creativeIntensity = value.toDouble();
        }
      } else if (type == 'film_profile') {
        final id = operation['id'];
        final strength = operation['strength'];
        if (id is String && strength is num) {
          film = id;
          filmStrength = strength.toDouble();
        }
      }
    }

    return EditorRecipeSummary(
      adjustments: Map.unmodifiable(adjustments),
      creativeFilter: creative,
      creativeIntensity: creativeIntensity,
      filmProfile: film,
      filmStrength: filmStrength,
      history: List.unmodifiable(history),
      cursor: cursor,
      checkpointCursor: checkpoint,
    );
  }

  static String resetDraftAdjustment(String recipeJson, String filter) =>
      _rewriteDraft(
        recipeJson,
        remove: (operation) => operation['type'] == 'filter' &&
            operation['name'] == filter,
      );

  static String resetDraftAdjustments(String recipeJson) => _rewriteDraft(
        recipeJson,
        remove: (operation) => operation['type'] == 'filter' &&
            coreFilters.contains(operation['name']),
      );

  static String resetDraftCreative(String recipeJson) => _rewriteDraft(
        recipeJson,
        remove: (operation) => operation['type'] == 'filter' &&
            creativeFilters.contains(operation['name']),
      );

  static String resetDraftFilm(String recipeJson) => _rewriteDraft(
        recipeJson,
        remove: (operation) => operation['type'] == 'film_profile',
      );

  static String _rewriteDraft(
    String recipeJson, {
    required bool Function(Map operation) remove,
  }) {
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
    final draft = <dynamic>[];
    for (final operation
        in rawOperations.skip(checkpoint).take(cursor - checkpoint)) {
      if (operation is Map && remove(operation)) continue;
      draft.add(operation);
    }

    // Reset is a new semantic branch. Like any edit after Undo, it must drop
    // a stale redo tail rather than allow Redo to resurrect operations that
    // were intentionally reset from the current draft.
    decoded['operations'] = <dynamic>[...applied, ...draft];
    decoded['cursor'] = applied.length + draft.length;
    decoded['checkpoint_cursor'] = checkpoint;
    return jsonEncode(decoded);
  }

  static String _operationLabel(Map operation) {
    final type = operation['type'];
    switch (type) {
      case 'filter':
        final name = '${operation['name'] ?? 'Filter'}'.replaceAll('_', ' ');
        final value = operation['value'];
        return value is num
            ? '${_title(name)}  ${value.toStringAsFixed(2)}'
            : _title(name);
      case 'film_profile':
        final id = '${operation['id'] ?? 'Film'}'.replaceAll('_', ' ');
        final strength = operation['strength'];
        return strength is num
            ? '${_title(id)}  ${(strength * 100).round()}%'
            : _title(id);
      case 'crop':
        return 'Crop';
      case 'rotate90':
        return 'Rotate 90°';
      case 'rotate_degrees':
        final degrees = operation['degrees'];
        return degrees is num
            ? 'Straighten ${degrees.toStringAsFixed(1)}°'
            : 'Straighten';
      case 'flip_horizontal':
        return 'Flip horizontal';
      case 'flip_vertical':
        return 'Flip vertical';
      case 'resize':
        return 'Resize';
      default:
        return _title('${type ?? 'Edit'}'.replaceAll('_', ' '));
    }
  }

  static String _title(String value) {
    if (value.isEmpty) return value;
    return '${value[0].toUpperCase()}${value.substring(1)}';
  }
}
