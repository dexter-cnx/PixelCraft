import 'dart:convert';

import 'gpu_editor_preview_bridge.dart';

const gpuAdjustFilterKeys = <String>{
  'brightness',
  'contrast',
  'saturation',
  'sharpen',
  'gaussian_blur',
};

class GpuEditorAdjustmentDraft {
  const GpuEditorAdjustmentDraft({
    required this.adjustments,
    required this.orderedKeys,
    required this.isRepresentable,
    this.fallbackReason,
  });

  final GpuEditorAdjustmentState adjustments;
  final List<String> orderedKeys;
  final bool isRepresentable;
  final String? fallbackReason;

  GpuEditorAdjustmentState withTransient(String key, double value) {
    if (!isRepresentable || !gpuAdjustFilterKeys.contains(key)) {
      return adjustments;
    }
    return _withAdjustment(adjustments, key, value);
  }

  factory GpuEditorAdjustmentDraft.fromRecipeJson(
    String recipeJson, {
    String? transientKey,
    double? transientValue,
  }) {
    try {
      final decoded = jsonDecode(recipeJson);
      if (decoded is! Map<String, dynamic>) {
        return const GpuEditorAdjustmentDraft._invalid('invalid recipe root');
      }

      final rawOperations = decoded['operations'];
      final rawCursor = decoded['cursor'];
      final rawCheckpoint = decoded['checkpoint_cursor'];
      if (rawOperations is! List ||
          rawCursor is! int ||
          rawCheckpoint is! int) {
        return const GpuEditorAdjustmentDraft._invalid('invalid recipe bounds');
      }

      final start = rawCheckpoint.clamp(0, rawOperations.length).toInt();
      final end = rawCursor.clamp(start, rawOperations.length).toInt();
      var adjustments = const GpuEditorAdjustmentState();
      final orderedKeys = <String>[];

      for (final operation in rawOperations.sublist(start, end)) {
        if (operation is! Map) {
          return const GpuEditorAdjustmentDraft._invalid(
            'unsupported active recipe node',
          );
        }

        if (operation['type'] != 'filter') {
          return GpuEditorAdjustmentDraft._invalid(
            'unsupported active node: ${operation['type']}',
          );
        }

        final name = operation['name'];
        final value = operation['value'];
        if (name is! String || value is! num || !gpuAdjustFilterKeys.contains(name)) {
          return GpuEditorAdjustmentDraft._invalid(
            'unsupported active filter: $name',
          );
        }

        orderedKeys.add(name);
        adjustments = _withAdjustment(
          adjustments,
          name,
          value.toDouble(),
        );
      }

      if (transientKey != null) {
        if (!gpuAdjustFilterKeys.contains(transientKey) || transientValue == null) {
          return GpuEditorAdjustmentDraft._invalid(
            'invalid transient adjustment: $transientKey',
          );
        }
        adjustments = _withAdjustment(
          adjustments,
          transientKey,
          transientValue,
        );
      }

      return GpuEditorAdjustmentDraft(
        adjustments: adjustments,
        orderedKeys: List.unmodifiable(orderedKeys),
        isRepresentable: true,
      );
    } catch (_) {
      return const GpuEditorAdjustmentDraft._invalid('invalid recipe json');
    }
  }

  const GpuEditorAdjustmentDraft._invalid(String reason)
      : adjustments = const GpuEditorAdjustmentState(),
        orderedKeys = const [],
        isRepresentable = false,
        fallbackReason = reason;
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
