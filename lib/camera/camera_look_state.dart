import 'package:dxtr_pixs_editing/pixelcraft_editing.dart' as editing;

/// Camera-facing creative filter entry backed by the existing Rust semantics.
///
/// [gpuAssetId] is only an internal preview asset identifier. The canonical
/// operation id that must be persisted/rendered by Rust remains [id].
class CameraCreativeFilter {
  const CameraCreativeFilter({
    required this.id,
    required this.label,
    this.gpuAssetId,
  });

  final String id;
  final String label;
  final String? gpuAssetId;

  bool get usesCanonicalLut => gpuAssetId != null;
}

const cameraCreativeFilters = <CameraCreativeFilter>[
  CameraCreativeFilter(id: 'grayscale', label: 'Grayscale'),
  CameraCreativeFilter(id: 'invert', label: 'Invert'),
  CameraCreativeFilter(
    id: 'vintage',
    label: 'Vintage',
    gpuAssetId: 'creative_vintage',
  ),
  CameraCreativeFilter(
    id: 'oceanic',
    label: 'Oceanic',
    gpuAssetId: 'creative_oceanic',
  ),
  CameraCreativeFilter(id: 'lofi', label: 'Lo-Fi', gpuAssetId: 'creative_lofi'),
  CameraCreativeFilter(
    id: 'dramatic',
    label: 'Dramatic',
    gpuAssetId: 'creative_dramatic',
  ),
  CameraCreativeFilter(
    id: 'golden',
    label: 'Golden',
    gpuAssetId: 'creative_golden',
  ),
  CameraCreativeFilter(
    id: 'pastel_pink',
    label: 'Pastel Pink',
    gpuAssetId: 'creative_pastel_pink',
  ),
];

/// PF2 realtime camera adjustments with native preview semantics matched to
/// the authoritative Rust editor operations.
const cameraGpuAdjustmentIds = <String>{
  'exposure',
  'temperature',
  'tint',
  'brightness',
  'contrast',
  'saturation',
  'vignette',
};

CameraCreativeFilter cameraCreativeFilter(String id) =>
    cameraCreativeFilters.firstWhere(
      (filter) => filter.id == id,
      orElse: () =>
          throw ArgumentError.value(id, 'id', 'Unknown camera creative filter'),
    );

editing.EditorAdjustmentSpec cameraAdjustmentSpec(String id) {
  if (!cameraGpuAdjustmentIds.contains(id)) {
    throw ArgumentError.value(
      id,
      'id',
      'Adjustment is not enabled for PF2 camera preview',
    );
  }
  return editing.adjustmentSpec(id);
}

/// Transient camera look configuration.
///
/// This is deliberately not a recipe/history authority. PF3 must translate
/// this state into Rust-owned operations when producing the full-resolution
/// JPEG. Native GPU preview may mirror this state but never becomes the source
/// of truth for saved pixels.
class CameraLookState {
  CameraLookState({
    this.filmProfileId = '',
    this.filmStrength = 0,
    this.creativeFilterId = '',
    this.creativeFilterStrength = 0,
    Map<String, double>? adjustments,
  }) : adjustments = Map.unmodifiable(
         adjustments ??
             <String, double>{
               for (final id in cameraGpuAdjustmentIds)
                 id: editing.defaultAdjustmentValue(id),
             },
       );

  final String filmProfileId;
  final double filmStrength;
  final String creativeFilterId;
  final double creativeFilterStrength;
  final Map<String, double> adjustments;

  bool get hasFilm => filmProfileId.isNotEmpty && filmStrength > 0;
  bool get hasCreative =>
      creativeFilterId.isNotEmpty && creativeFilterStrength > 0;

  double adjustmentValue(String id) {
    cameraAdjustmentSpec(id);
    return adjustments[id] ?? editing.defaultAdjustmentValue(id);
  }

  CameraLookState withFilm(String profileId, double strength) =>
      CameraLookState(
        filmProfileId: profileId,
        filmStrength: strength.clamp(0.0, 1.0).toDouble(),
        creativeFilterId: creativeFilterId,
        creativeFilterStrength: creativeFilterStrength,
        adjustments: adjustments,
      );

  CameraLookState clearFilm() => CameraLookState(
    creativeFilterId: creativeFilterId,
    creativeFilterStrength: creativeFilterStrength,
    adjustments: adjustments,
  );

  CameraLookState withCreative(String filterId, double strength) {
    cameraCreativeFilter(filterId);
    return CameraLookState(
      filmProfileId: filmProfileId,
      filmStrength: filmStrength,
      creativeFilterId: filterId,
      creativeFilterStrength: strength.clamp(0.0, 1.0).toDouble(),
      adjustments: adjustments,
    );
  }

  CameraLookState clearCreative() => CameraLookState(
    filmProfileId: filmProfileId,
    filmStrength: filmStrength,
    adjustments: adjustments,
  );

  CameraLookState withAdjustment(String id, double value) {
    final spec = cameraAdjustmentSpec(id);
    final next = Map<String, double>.from(adjustments)
      ..[id] = value.clamp(spec.min, spec.max).toDouble();
    return CameraLookState(
      filmProfileId: filmProfileId,
      filmStrength: filmStrength,
      creativeFilterId: creativeFilterId,
      creativeFilterStrength: creativeFilterStrength,
      adjustments: next,
    );
  }

  CameraLookState resetAdjustment(String id) =>
      withAdjustment(id, editing.defaultAdjustmentValue(id));

  CameraLookState resetAdjustments() => CameraLookState(
    filmProfileId: filmProfileId,
    filmStrength: filmStrength,
    creativeFilterId: creativeFilterId,
    creativeFilterStrength: creativeFilterStrength,
  );
}
