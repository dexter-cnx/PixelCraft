class EditorAdjustmentSpec {
  const EditorAdjustmentSpec({
    required this.id,
    required this.label,
    required this.min,
    required this.max,
    required this.neutral,
    required this.group,
    this.unit = '',
  });

  final String id;
  final String label;
  final double min;
  final double max;
  final double neutral;
  final String group;
  final String unit;
}

const editorAdjustmentSpecs = <EditorAdjustmentSpec>[
  EditorAdjustmentSpec(id: 'exposure', label: 'Exposure', min: -2, max: 2, neutral: 0, group: 'Light', unit: 'EV'),
  EditorAdjustmentSpec(id: 'brightness', label: 'Brightness', min: 0, max: 2, neutral: 1, group: 'Light'),
  EditorAdjustmentSpec(id: 'contrast', label: 'Contrast', min: 0, max: 2, neutral: 1, group: 'Light'),
  EditorAdjustmentSpec(id: 'highlights', label: 'Highlights', min: -1, max: 1, neutral: 0, group: 'Light'),
  EditorAdjustmentSpec(id: 'shadows', label: 'Shadows', min: -1, max: 1, neutral: 0, group: 'Light'),
  EditorAdjustmentSpec(id: 'saturation', label: 'Saturation', min: 0, max: 2, neutral: 1, group: 'Color'),
  EditorAdjustmentSpec(id: 'temperature', label: 'Temperature', min: -1, max: 1, neutral: 0, group: 'Color'),
  EditorAdjustmentSpec(id: 'tint', label: 'Tint', min: -1, max: 1, neutral: 0, group: 'Color'),
  EditorAdjustmentSpec(id: 'vibrance', label: 'Vibrance', min: -1, max: 1, neutral: 0, group: 'Color'),
  EditorAdjustmentSpec(id: 'vignette', label: 'Vignette', min: -1, max: 1, neutral: 0, group: 'Texture'),
  EditorAdjustmentSpec(id: 'grain', label: 'Grain', min: 0, max: 1, neutral: 0, group: 'Texture'),
  EditorAdjustmentSpec(id: 'sharpen', label: 'Sharpness', min: 0, max: 2, neutral: 0, group: 'Detail'),
  EditorAdjustmentSpec(id: 'gaussian_blur', label: 'Gaussian Blur', min: 0, max: 2, neutral: 0, group: 'Detail'),
];

const coreFilters = <String>[
  'exposure',
  'brightness',
  'contrast',
  'highlights',
  'shadows',
  'saturation',
  'temperature',
  'tint',
  'vibrance',
  'vignette',
  'grain',
  'sharpen',
  'gaussian_blur',
];

EditorAdjustmentSpec adjustmentSpec(String id) => editorAdjustmentSpecs.firstWhere(
      (spec) => spec.id == id,
      orElse: () => throw ArgumentError.value(id, 'id', 'Unknown editor adjustment'),
    );

double defaultAdjustmentValue(String id) => adjustmentSpec(id).neutral;
