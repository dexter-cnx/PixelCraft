import 'dart:convert';

import 'gpu_editor_preview_bridge.dart';

const gpuCoreAdjustmentKeys = <String>{
  'brightness',
  'contrast',
  'saturation',
  'sharpen',
  'gaussian_blur',
};

const gpuCreativeFilterKeys = <String>{
  'grayscale',
  'invert',
  'vintage',
  'oceanic',
  'lofi',
  'dramatic',
  'golden',
  'pastel_pink',
};

const gpuComputeCreativeKeys = <String>{'grayscale', 'invert'};
const gpuLutCreativeKeys = <String>{
  'vintage',
  'oceanic',
  'lofi',
  'dramatic',
  'golden',
  'pastel_pink',
};

enum GpuEditorDraftKind { adjust, creative, film }

class GpuEditorTransientEdit {
  const GpuEditorTransientEdit({
    required this.kind,
    required this.key,
    required this.value,
  });

  final GpuEditorDraftKind kind;
  final String key;
  final double value;
}

class GpuEditorRenderPlan {
  const GpuEditorRenderPlan({
    required this.adjustments,
    required this.creativeFilterId,
    required this.creativeIntensity,
    required this.filmProfileId,
    required this.filmStrength,
    required this.orderedOperations,
    required this.isRepresentable,
    this.creativeUsesFilmSlot = false,
    this.fallbackReason,
  });

  final GpuEditorAdjustmentState adjustments;
  final String creativeFilterId;
  final double creativeIntensity;
  final String filmProfileId;
  final double filmStrength;
  final List<String> orderedOperations;
  final bool isRepresentable;
  final bool creativeUsesFilmSlot;
  final String? fallbackReason;

  bool get hasCreative => creativeFilterId.isNotEmpty;
  bool get hasFilm => filmProfileId.isNotEmpty;

  factory GpuEditorRenderPlan.fromRecipeJson(
    String recipeJson, {
    GpuEditorTransientEdit? transient,
  }) {
    try {
      final decoded = jsonDecode(recipeJson);
      if (decoded is! Map<String, dynamic>) {
        return const GpuEditorRenderPlan._invalid('invalid recipe root');
      }

      final rawOperations = decoded['operations'];
      final rawCursor = decoded['cursor'];
      final rawCheckpoint = decoded['checkpoint_cursor'];
      if (rawOperations is! List || rawCursor is! int || rawCheckpoint is! int) {
        return const GpuEditorRenderPlan._invalid('invalid recipe bounds');
      }
      if (rawCheckpoint < 0 ||
          rawCursor < rawCheckpoint ||
          rawCursor > rawOperations.length) {
        return const GpuEditorRenderPlan._invalid('invalid recipe cursor range');
      }

      final active = <_PlanNode>[];
      for (final raw in rawOperations.sublist(rawCheckpoint, rawCursor)) {
        final node = _PlanNode.fromRecipeOperation(raw);
        if (node == null) {
          return const GpuEditorRenderPlan._invalid(
            'unsupported active recipe node',
          );
        }
        active.add(node);
      }

      if (transient != null) {
        final transientNode = _PlanNode.fromTransient(transient);
        if (transientNode == null) {
          return GpuEditorRenderPlan._invalid(
            'unsupported transient ${transient.kind.name}:${transient.key}',
          );
        }
        final slot = transientNode.slot;
        final index = active.indexWhere((node) => node.slot == slot);
        if (index >= 0) {
          active[index] = transientNode;
        } else {
          // Rust appends a new replaceable draft slot when no slot exists yet.
          active.add(transientNode);
        }
      }

      final seenSlots = <String>{};
      for (final node in active) {
        if (!seenSlots.add(node.slot)) {
          return GpuEditorRenderPlan._invalid(
            'duplicate active draft slot: ${node.slot}',
          );
        }
      }

      var adjustments = const GpuEditorAdjustmentState();
      _PlanNode? creative;
      _PlanNode? film;
      for (final node in active) {
        if (node.family == _PlanFamily.adjust) {
          adjustments = _withAdjustment(adjustments, node.key, node.value);
        } else if (node.family == _PlanFamily.creative) {
          creative = node;
        } else if (node.family == _PlanFamily.film) {
          film = node;
        }
      }

      final creativeKey = creative?.key ?? '';
      final filmId = film?.key ?? '';
      final creativeUsesFilmSlot = gpuLutCreativeKeys.contains(creativeKey);

      if (creativeUsesFilmSlot && film != null) {
        return const GpuEditorRenderPlan._invalid(
          'creative LUT and Film both require the native LUT slot',
        );
      }

      final actualOrder = active.map((node) => node.nativeToken).toList();
      final nativeOrder = _nativeStageOrder(
        creativeKey: creativeKey,
        hasFilm: film != null,
      );
      if (!_isSubsequence(actualOrder, nativeOrder)) {
        return GpuEditorRenderPlan._invalid(
          'authoritative Rust order cannot be represented by native stages: '
          '${actualOrder.join(' -> ')}',
        );
      }

      return GpuEditorRenderPlan(
        adjustments: adjustments,
        creativeFilterId: creativeKey,
        creativeIntensity: creative?.value ?? 0,
        filmProfileId: filmId,
        filmStrength: film?.value ?? 0,
        orderedOperations: List.unmodifiable(actualOrder),
        isRepresentable: true,
        creativeUsesFilmSlot: creativeUsesFilmSlot,
      );
    } catch (_) {
      return const GpuEditorRenderPlan._invalid('invalid recipe json');
    }
  }

  const GpuEditorRenderPlan._invalid(String reason)
      : adjustments = const GpuEditorAdjustmentState(),
        creativeFilterId = '',
        creativeIntensity = 0,
        filmProfileId = '',
        filmStrength = 0,
        orderedOperations = const [],
        isRepresentable = false,
        creativeUsesFilmSlot = false,
        fallbackReason = reason;
}

enum _PlanFamily { adjust, creative, film }

class _PlanNode {
  const _PlanNode({
    required this.family,
    required this.key,
    required this.value,
  });

  final _PlanFamily family;
  final String key;
  final double value;

  String get slot => switch (family) {
        _PlanFamily.adjust => 'adjust:$key',
        _PlanFamily.creative => 'creative',
        _PlanFamily.film => 'film',
      };

  String get nativeToken {
    if (family == _PlanFamily.adjust) return key;
    if (family == _PlanFamily.film) return 'film';
    return gpuComputeCreativeKeys.contains(key) ? 'creative_compute' : 'creative_lut';
  }

  static _PlanNode? fromRecipeOperation(Object? raw) {
    if (raw is! Map) return null;
    final type = raw['type'];
    if (type == 'filter') {
      final name = raw['name'];
      final value = raw['value'];
      if (name is! String || value is! num) return null;
      if (gpuCoreAdjustmentKeys.contains(name)) {
        return _PlanNode(
          family: _PlanFamily.adjust,
          key: name,
          value: value.toDouble(),
        );
      }
      if (gpuCreativeFilterKeys.contains(name)) {
        return _PlanNode(
          family: _PlanFamily.creative,
          key: name,
          value: value.toDouble(),
        );
      }
      return null;
    }
    if (type == 'film_profile') {
      final id = raw['id'];
      final strength = raw['strength'];
      if (id is! String || id.isEmpty || strength is! num) return null;
      return _PlanNode(
        family: _PlanFamily.film,
        key: id,
        value: strength.toDouble(),
      );
    }
    return null;
  }

  static _PlanNode? fromTransient(GpuEditorTransientEdit edit) {
    switch (edit.kind) {
      case GpuEditorDraftKind.adjust:
        if (!gpuCoreAdjustmentKeys.contains(edit.key)) return null;
        return _PlanNode(
          family: _PlanFamily.adjust,
          key: edit.key,
          value: edit.value,
        );
      case GpuEditorDraftKind.creative:
        if (!gpuCreativeFilterKeys.contains(edit.key)) return null;
        return _PlanNode(
          family: _PlanFamily.creative,
          key: edit.key,
          value: edit.value,
        );
      case GpuEditorDraftKind.film:
        if (edit.key.isEmpty) return null;
        return _PlanNode(
          family: _PlanFamily.film,
          key: edit.key,
          value: edit.value,
        );
    }
  }
}

List<String> _nativeStageOrder({
  required String creativeKey,
  required bool hasFilm,
}) {
  const adjustments = <String>[
    'gaussian_blur',
    'sharpen',
    'brightness',
    'contrast',
    'saturation',
  ];

  if (gpuComputeCreativeKeys.contains(creativeKey)) {
    return <String>[
      'creative_compute',
      ...adjustments,
      if (hasFilm) 'film',
    ];
  }
  if (gpuLutCreativeKeys.contains(creativeKey)) {
    return <String>[...adjustments, 'creative_lut'];
  }
  return <String>[...adjustments, if (hasFilm) 'film'];
}

bool _isSubsequence(List<String> actual, List<String> supportedOrder) {
  var cursor = 0;
  for (final token in actual) {
    while (cursor < supportedOrder.length && supportedOrder[cursor] != token) {
      cursor++;
    }
    if (cursor >= supportedOrder.length) return false;
    cursor++;
  }
  return true;
}

GpuEditorAdjustmentState _withAdjustment(
  GpuEditorAdjustmentState state,
  String key,
  double value,
) =>
    switch (key) {
      'brightness' => state.copyWith(brightness: value),
      'contrast' => state.copyWith(contrast: value),
      'saturation' => state.copyWith(saturation: value),
      'sharpen' => state.copyWith(sharpen: value),
      'gaussian_blur' => state.copyWith(gaussianBlur: value),
      _ => state,
    };
