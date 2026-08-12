import 'package:pixelcraft_editing/pixelcraft_editing.dart' as editing;

class EditorAdjustmentSpec {
  const EditorAdjustmentSpec({
    required this.semantics,
    required this.gpuPreview,
  });

  final editing.EditorAdjustmentSpec semantics;
  final bool gpuPreview;

  String get id => semantics.id;
  String get label => semantics.label;
  double get min => semantics.min;
  double get max => semantics.max;
  double get neutral => semantics.neutral;
  String get group => semantics.group;
  String get unit => semantics.unit;
}

const _gpuPreviewAdjustmentIds = <String>{
  'brightness',
  'contrast',
  'saturation',
  'sharpen',
  'gaussian_blur',
};

final editorAdjustmentSpecs = editing.editorAdjustmentSpecs
    .map(
      (spec) => EditorAdjustmentSpec(
        semantics: spec,
        gpuPreview: _gpuPreviewAdjustmentIds.contains(spec.id),
      ),
    )
    .toList(growable: false);

const coreFilters = editing.coreFilters;

double defaultAdjustmentValue(String id) => editing.defaultAdjustmentValue(id);

EditorAdjustmentSpec adjustmentSpec(String id) => editorAdjustmentSpecs.firstWhere(
      (spec) => spec.id == id,
      orElse: () => throw ArgumentError.value(id, 'id', 'Unknown editor adjustment'),
    );
