import 'dart:convert';

const pixelCraftProfileSchema = 'pixelcraft-film-profile';
const pixelCraftProfileSchemaVersion = 1;
const pixelCraftProfileEngineVersion = 1;

enum FilmProfileOrigin { builtIn, user, imported }

class FilmProfileParameterSpec {
  const FilmProfileParameterSpec({
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

  double clamp(double value) => value.clamp(min, max).toDouble();
}

const filmProfileParameterSpecs = <FilmProfileParameterSpec>[
  FilmProfileParameterSpec(
    id: 'exposure',
    label: 'Exposure',
    min: -2,
    max: 2,
    neutral: 0,
    group: 'Tone',
    unit: 'EV',
  ),
  FilmProfileParameterSpec(
    id: 'brightness',
    label: 'Brightness',
    min: 0,
    max: 2,
    neutral: 1,
    group: 'Tone',
  ),
  FilmProfileParameterSpec(
    id: 'contrast',
    label: 'Contrast',
    min: 0,
    max: 2,
    neutral: 1,
    group: 'Tone',
  ),
  FilmProfileParameterSpec(
    id: 'highlights',
    label: 'Highlights',
    min: -1,
    max: 1,
    neutral: 0,
    group: 'Tone',
  ),
  FilmProfileParameterSpec(
    id: 'shadows',
    label: 'Shadows',
    min: -1,
    max: 1,
    neutral: 0,
    group: 'Tone',
  ),
  FilmProfileParameterSpec(
    id: 'saturation',
    label: 'Saturation',
    min: 0,
    max: 2,
    neutral: 1,
    group: 'Color',
  ),
  FilmProfileParameterSpec(
    id: 'temperature',
    label: 'Temperature',
    min: -1,
    max: 1,
    neutral: 0,
    group: 'Color',
  ),
  FilmProfileParameterSpec(
    id: 'tint',
    label: 'Tint',
    min: -1,
    max: 1,
    neutral: 0,
    group: 'Color',
  ),
  FilmProfileParameterSpec(
    id: 'vibrance',
    label: 'Vibrance',
    min: -1,
    max: 1,
    neutral: 0,
    group: 'Color',
  ),
  FilmProfileParameterSpec(
    id: 'vignette',
    label: 'Vignette',
    min: -1,
    max: 1,
    neutral: 0,
    group: 'Texture',
  ),
  FilmProfileParameterSpec(
    id: 'grain',
    label: 'Grain',
    min: 0,
    max: 1,
    neutral: 0,
    group: 'Texture',
  ),
  FilmProfileParameterSpec(
    id: 'sharpen',
    label: 'Sharpness',
    min: 0,
    max: 2,
    neutral: 0,
    group: 'Texture',
  ),
  FilmProfileParameterSpec(
    id: 'gaussian_blur',
    label: 'Gaussian Blur',
    min: 0,
    max: 2,
    neutral: 0,
    group: 'Texture',
  ),
  FilmProfileParameterSpec(
    id: 'curve_shadows',
    label: 'Curve Shadows',
    min: -1,
    max: 1,
    neutral: 0,
    group: 'Curve',
  ),
  FilmProfileParameterSpec(
    id: 'curve_midtones',
    label: 'Curve Midtones',
    min: -1,
    max: 1,
    neutral: 0,
    group: 'Curve',
  ),
  FilmProfileParameterSpec(
    id: 'curve_highlights',
    label: 'Curve Highlights',
    min: -1,
    max: 1,
    neutral: 0,
    group: 'Curve',
  ),
  ..._hslSpecs,
];

const _hslSpecs = <FilmProfileParameterSpec>[
  FilmProfileParameterSpec(id: 'hsl_red_hue', label: 'Red Hue', min: -1, max: 1, neutral: 0, group: 'HSL'),
  FilmProfileParameterSpec(id: 'hsl_red_sat', label: 'Red Saturation', min: -1, max: 1, neutral: 0, group: 'HSL'),
  FilmProfileParameterSpec(id: 'hsl_red_lum', label: 'Red Luminance', min: -1, max: 1, neutral: 0, group: 'HSL'),
  FilmProfileParameterSpec(id: 'hsl_yellow_hue', label: 'Yellow Hue', min: -1, max: 1, neutral: 0, group: 'HSL'),
  FilmProfileParameterSpec(id: 'hsl_yellow_sat', label: 'Yellow Saturation', min: -1, max: 1, neutral: 0, group: 'HSL'),
  FilmProfileParameterSpec(id: 'hsl_yellow_lum', label: 'Yellow Luminance', min: -1, max: 1, neutral: 0, group: 'HSL'),
  FilmProfileParameterSpec(id: 'hsl_green_hue', label: 'Green Hue', min: -1, max: 1, neutral: 0, group: 'HSL'),
  FilmProfileParameterSpec(id: 'hsl_green_sat', label: 'Green Saturation', min: -1, max: 1, neutral: 0, group: 'HSL'),
  FilmProfileParameterSpec(id: 'hsl_green_lum', label: 'Green Luminance', min: -1, max: 1, neutral: 0, group: 'HSL'),
  FilmProfileParameterSpec(id: 'hsl_cyan_hue', label: 'Cyan Hue', min: -1, max: 1, neutral: 0, group: 'HSL'),
  FilmProfileParameterSpec(id: 'hsl_cyan_sat', label: 'Cyan Saturation', min: -1, max: 1, neutral: 0, group: 'HSL'),
  FilmProfileParameterSpec(id: 'hsl_cyan_lum', label: 'Cyan Luminance', min: -1, max: 1, neutral: 0, group: 'HSL'),
  FilmProfileParameterSpec(id: 'hsl_blue_hue', label: 'Blue Hue', min: -1, max: 1, neutral: 0, group: 'HSL'),
  FilmProfileParameterSpec(id: 'hsl_blue_sat', label: 'Blue Saturation', min: -1, max: 1, neutral: 0, group: 'HSL'),
  FilmProfileParameterSpec(id: 'hsl_blue_lum', label: 'Blue Luminance', min: -1, max: 1, neutral: 0, group: 'HSL'),
  FilmProfileParameterSpec(id: 'hsl_magenta_hue', label: 'Magenta Hue', min: -1, max: 1, neutral: 0, group: 'HSL'),
  FilmProfileParameterSpec(id: 'hsl_magenta_sat', label: 'Magenta Saturation', min: -1, max: 1, neutral: 0, group: 'HSL'),
  FilmProfileParameterSpec(id: 'hsl_magenta_lum', label: 'Magenta Luminance', min: -1, max: 1, neutral: 0, group: 'HSL'),
];

FilmProfileParameterSpec? filmProfileParameterSpec(String id) {
  for (final spec in filmProfileParameterSpecs) {
    if (spec.id == id) return spec;
  }
  return null;
}

class FilmProfileV1 {
  FilmProfileV1({
    required this.id,
    required this.name,
    this.description = '',
    this.origin = FilmProfileOrigin.user,
    this.baseFilmId = '',
    this.baseStrength = 1,
    Map<String, double> parameters = const {},
    List<String> tags = const [],
    this.schemaVersion = pixelCraftProfileSchemaVersion,
    this.minEngineVersion = pixelCraftProfileEngineVersion,
  })  : parameters = Map.unmodifiable(_normalizeParameters(parameters)),
        tags = List.unmodifiable(tags.where((tag) => tag.trim().isNotEmpty).map((tag) => tag.trim()));

  final int schemaVersion;
  final int minEngineVersion;
  final String id;
  final String name;
  final String description;
  final FilmProfileOrigin origin;
  final String baseFilmId;
  final double baseStrength;
  final Map<String, double> parameters;
  final List<String> tags;

  bool get isBuiltIn => origin == FilmProfileOrigin.builtIn;

  FilmProfileV1 copyWith({
    String? id,
    String? name,
    String? description,
    FilmProfileOrigin? origin,
    String? baseFilmId,
    double? baseStrength,
    Map<String, double>? parameters,
    List<String>? tags,
  }) =>
      FilmProfileV1(
        id: id ?? this.id,
        name: name ?? this.name,
        description: description ?? this.description,
        origin: origin ?? this.origin,
        baseFilmId: baseFilmId ?? this.baseFilmId,
        baseStrength: baseStrength ?? this.baseStrength,
        parameters: parameters ?? this.parameters,
        tags: tags ?? this.tags,
        schemaVersion: schemaVersion,
        minEngineVersion: minEngineVersion,
      );

  FilmProfileV1 duplicate({required String newId, String? newName}) => copyWith(
        id: newId,
        name: newName ?? '$name Copy',
        origin: FilmProfileOrigin.user,
      );

  Map<String, Object?> toJson() => {
        'schema': pixelCraftProfileSchema,
        'schemaVersion': schemaVersion,
        'minEngineVersion': minEngineVersion,
        'id': id,
        'name': name,
        'description': description,
        'origin': origin.name,
        'baseFilmId': baseFilmId,
        'baseStrength': baseStrength.clamp(0.0, 1.0),
        'parameters': parameters,
        'tags': tags,
      };

  String encode({bool pretty = true}) => pretty
      ? const JsonEncoder.withIndent('  ').convert(toJson())
      : jsonEncode(toJson());

  static FilmProfileV1 decode(String source) {
    final raw = jsonDecode(source);
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Film Profile must be a JSON object');
    }
    if (raw['schema'] != pixelCraftProfileSchema) {
      throw const FormatException('Unsupported Film Profile schema');
    }
    final version = raw['schemaVersion'];
    if (version != pixelCraftProfileSchemaVersion) {
      throw FormatException('Unsupported Film Profile schemaVersion: $version');
    }
    final minEngine = raw['minEngineVersion'];
    if (minEngine is! int || minEngine > pixelCraftProfileEngineVersion) {
      throw FormatException('Film Profile requires engine version $minEngine');
    }
    final id = raw['id'];
    final name = raw['name'];
    if (id is! String || id.trim().isEmpty || name is! String || name.trim().isEmpty) {
      throw const FormatException('Film Profile id and name are required');
    }
    final rawParameters = raw['parameters'];
    final parameters = <String, double>{};
    if (rawParameters is Map) {
      for (final entry in rawParameters.entries) {
        if (entry.key is String && entry.value is num) {
          final key = entry.key as String;
          final spec = filmProfileParameterSpec(key);
          if (spec == null) {
            throw FormatException('Unsupported Film Profile parameter: $key');
          }
          parameters[key] = spec.clamp((entry.value as num).toDouble());
        }
      }
    }
    final rawOrigin = raw['origin'];
    final origin = FilmProfileOrigin.values.where((item) => item.name == rawOrigin).firstOrNull ?? FilmProfileOrigin.imported;
    final rawTags = raw['tags'];
    return FilmProfileV1(
      id: id.trim(),
      name: name.trim(),
      description: raw['description'] is String ? raw['description'] as String : '',
      origin: origin,
      baseFilmId: raw['baseFilmId'] is String ? raw['baseFilmId'] as String : '',
      baseStrength: raw['baseStrength'] is num ? (raw['baseStrength'] as num).toDouble().clamp(0.0, 1.0) : 1,
      parameters: parameters,
      tags: rawTags is List ? rawTags.whereType<String>().toList() : const [],
      schemaVersion: version as int,
      minEngineVersion: minEngine,
    );
  }

  static Map<String, double> _normalizeParameters(Map<String, double> input) {
    final result = <String, double>{};
    for (final entry in input.entries) {
      final spec = filmProfileParameterSpec(entry.key);
      if (spec == null) continue;
      final value = spec.clamp(entry.value);
      if ((value - spec.neutral).abs() > 0.000001) {
        result[entry.key] = value;
      }
    }
    return result;
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

enum FilmProfileMappingKind { exact, approximated, unsupported }

class FilmProfileMapping {
  const FilmProfileMapping({
    required this.sourceField,
    required this.kind,
    this.targetField,
    this.note = '',
  });

  final String sourceField;
  final FilmProfileMappingKind kind;
  final String? targetField;
  final String note;
}

class FilmProfileImportReport {
  const FilmProfileImportReport({required this.profile, required this.mappings});

  final FilmProfileV1 profile;
  final List<FilmProfileMapping> mappings;

  bool get hasUnsupported => mappings.any((item) => item.kind == FilmProfileMappingKind.unsupported);
}

FilmProfileImportReport importRecipeMap(
  Map<String, Object?> recipe, {
  required String id,
  String? name,
}) {
  const exactAliases = <String, String>{
    'exposure': 'exposure',
    'contrast': 'contrast',
    'highlights': 'highlights',
    'shadows': 'shadows',
    'saturation': 'saturation',
    'color': 'saturation',
    'temperature': 'temperature',
    'tint': 'tint',
    'vibrance': 'vibrance',
    'vignette': 'vignette',
    'grain': 'grain',
    'sharpness': 'sharpen',
    'sharpen': 'sharpen',
  };
  const approximateAliases = <String, String>{
    'highlightTone': 'highlights',
    'shadowTone': 'shadows',
    'colorDensity': 'vibrance',
    'wbShiftRed': 'temperature',
    'wbShiftBlue': 'temperature',
  };

  final values = <String, double>{};
  final mappings = <FilmProfileMapping>[];
  var baseFilm = '';

  for (final entry in recipe.entries) {
    final key = entry.key;
    final value = entry.value;
    if (key == 'name' || key == 'description' || key == 'tags') continue;
    if (key == 'baseFilmId' || key == 'baseSimulation') {
      if (value is String) {
        baseFilm = value;
        mappings.add(FilmProfileMapping(sourceField: key, kind: FilmProfileMappingKind.approximated, targetField: 'baseFilmId', note: 'Mapped by profile id/name; vendor processing is not claimed 1:1.'));
      }
      continue;
    }
    final exactTarget = exactAliases[key];
    if (exactTarget != null && value is num) {
      final spec = filmProfileParameterSpec(exactTarget)!;
      values[exactTarget] = spec.clamp(value.toDouble());
      mappings.add(FilmProfileMapping(sourceField: key, kind: FilmProfileMappingKind.exact, targetField: exactTarget));
      continue;
    }
    final approximateTarget = approximateAliases[key];
    if (approximateTarget != null && value is num) {
      final spec = filmProfileParameterSpec(approximateTarget)!;
      values[approximateTarget] = spec.clamp(value.toDouble());
      mappings.add(FilmProfileMapping(sourceField: key, kind: FilmProfileMappingKind.approximated, targetField: approximateTarget, note: 'Semantic approximation; source vendor response curve is not reproduced 1:1.'));
      continue;
    }
    mappings.add(FilmProfileMapping(sourceField: key, kind: FilmProfileMappingKind.unsupported, note: 'Field retained in the import report and not silently discarded.'));
  }

  return FilmProfileImportReport(
    profile: FilmProfileV1(
      id: id,
      name: name ?? (recipe['name'] is String ? recipe['name'] as String : 'Imported Film'),
      description: recipe['description'] is String ? recipe['description'] as String : '',
      origin: FilmProfileOrigin.imported,
      baseFilmId: baseFilm,
      parameters: values,
      tags: recipe['tags'] is List ? (recipe['tags'] as List).whereType<String>().toList() : const [],
    ),
    mappings: List.unmodifiable(mappings),
  );
}
