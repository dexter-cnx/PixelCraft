import 'dart:convert';

const pixelCraftEditGraphSchemaVersion = 3;

enum EditNodeType {
  adjustment,
  filmProfile,
  crop,
  rotate,
  flip,
  resize,
  overlay,
}

class EditGraphDocument {
  const EditGraphDocument({
    this.schemaVersion = pixelCraftEditGraphSchemaVersion,
    this.nodes = const [],
    this.masks = const [],
    this.overlays = const [],
  });

  final int schemaVersion;
  final List<EditGraphNode> nodes;
  final List<EditMask> masks;
  final List<EditOverlay> overlays;

  String encode() => jsonEncode(toJson());

  Map<String, Object?> toJson() => <String, Object?>{
        'schemaVersion': schemaVersion,
        'document': <String, Object?>{
          'nodes': nodes.map((node) => node.toJson()).toList(growable: false),
          'masks': masks.map((mask) => mask.toJson()).toList(growable: false),
          'overlays': overlays.map((overlay) => overlay.toJson()).toList(growable: false),
        },
      };

  static EditGraphDocument decode(String source) {
    final value = jsonDecode(source);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Edit graph root must be a JSON object.');
    }
    return fromJson(value);
  }

  static EditGraphDocument fromJson(Map<String, dynamic> json) {
    final schemaVersion = json['schemaVersion'];
    if (schemaVersion is! int) {
      throw const FormatException('Edit graph schemaVersion must be an integer.');
    }
    if (schemaVersion != pixelCraftEditGraphSchemaVersion) {
      throw FormatException(
        'Unsupported edit graph schemaVersion $schemaVersion; expected $pixelCraftEditGraphSchemaVersion.',
      );
    }

    final document = json['document'];
    if (document is! Map<String, dynamic>) {
      throw const FormatException('Edit graph document must be an object.');
    }

    final nodes = _jsonObjectList(document['nodes'], 'nodes')
        .map(EditGraphNode.fromJson)
        .toList(growable: false);
    final masks = _jsonObjectList(document['masks'], 'masks')
        .map(EditMask.fromJson)
        .toList(growable: false);
    final overlays = _jsonObjectList(document['overlays'], 'overlays')
        .map(EditOverlay.fromJson)
        .toList(growable: false);

    final maskIds = masks.map((mask) => mask.id).toSet();
    for (final node in nodes) {
      final maskId = node.maskId;
      if (maskId != null && !maskIds.contains(maskId)) {
        throw FormatException('Edit node ${node.id} references missing mask $maskId.');
      }
    }

    _ensureUniqueIds(nodes.map((node) => node.id), 'node');
    _ensureUniqueIds(masks.map((mask) => mask.id), 'mask');
    _ensureUniqueIds(overlays.map((overlay) => overlay.id), 'overlay');

    return EditGraphDocument(
      schemaVersion: schemaVersion,
      nodes: nodes,
      masks: masks,
      overlays: overlays,
    );
  }
}

class EditGraphNode {
  const EditGraphNode({
    required this.id,
    required this.type,
    this.enabled = true,
    this.opacity = 1,
    this.params = const <String, Object?>{},
    this.maskId,
  });

  final String id;
  final EditNodeType type;
  final bool enabled;
  final double opacity;
  final Map<String, Object?> params;
  final String? maskId;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'type': type.name,
        'enabled': enabled,
        'opacity': opacity,
        'params': params,
        'maskId': maskId,
      };

  static EditGraphNode fromJson(Map<String, dynamic> json) {
    final id = _requiredString(json, 'id');
    final typeName = _requiredString(json, 'type');
    final type = EditNodeType.values.where((value) => value.name == typeName).firstOrNull;
    if (type == null) {
      throw FormatException('Unknown edit node type $typeName.');
    }

    final enabled = json['enabled'] ?? true;
    if (enabled is! bool) {
      throw FormatException('Edit node $id enabled must be boolean.');
    }

    final opacity = _number(json['opacity'] ?? 1.0, 'opacity').toDouble();
    if (opacity < 0 || opacity > 1) {
      throw FormatException('Edit node $id opacity must be between 0 and 1.');
    }

    final params = json['params'] ?? const <String, Object?>{};
    if (params is! Map<String, dynamic>) {
      throw FormatException('Edit node $id params must be an object.');
    }

    final maskIdValue = json['maskId'];
    if (maskIdValue != null && maskIdValue is! String) {
      throw FormatException('Edit node $id maskId must be a string or null.');
    }

    return EditGraphNode(
      id: id,
      type: type,
      enabled: enabled,
      opacity: opacity,
      params: Map<String, Object?>.unmodifiable(params),
      maskId: maskIdValue as String?,
    );
  }
}

class EditMask {
  const EditMask({required this.id, required this.type, this.params = const <String, Object?>{}});

  final String id;
  final String type;
  final Map<String, Object?> params;

  Map<String, Object?> toJson() => <String, Object?>{'id': id, 'type': type, 'params': params};

  static EditMask fromJson(Map<String, dynamic> json) {
    final id = _requiredString(json, 'id');
    final type = _requiredString(json, 'type');
    final params = json['params'] ?? const <String, Object?>{};
    if (params is! Map<String, dynamic>) {
      throw FormatException('Edit mask $id params must be an object.');
    }
    return EditMask(id: id, type: type, params: Map<String, Object?>.unmodifiable(params));
  }
}

class EditOverlay {
  const EditOverlay({
    required this.id,
    required this.type,
    this.zIndex = 0,
    this.opacity = 1,
    this.params = const <String, Object?>{},
  });

  final String id;
  final String type;
  final int zIndex;
  final double opacity;
  final Map<String, Object?> params;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'type': type,
        'zIndex': zIndex,
        'opacity': opacity,
        'params': params,
      };

  static EditOverlay fromJson(Map<String, dynamic> json) {
    final id = _requiredString(json, 'id');
    final type = _requiredString(json, 'type');
    final zIndex = json['zIndex'] ?? 0;
    if (zIndex is! int) {
      throw FormatException('Edit overlay $id zIndex must be an integer.');
    }
    final opacity = _number(json['opacity'] ?? 1.0, 'opacity').toDouble();
    if (opacity < 0 || opacity > 1) {
      throw FormatException('Edit overlay $id opacity must be between 0 and 1.');
    }
    final params = json['params'] ?? const <String, Object?>{};
    if (params is! Map<String, dynamic>) {
      throw FormatException('Edit overlay $id params must be an object.');
    }
    return EditOverlay(
      id: id,
      type: type,
      zIndex: zIndex,
      opacity: opacity,
      params: Map<String, Object?>.unmodifiable(params),
    );
  }
}

List<Map<String, dynamic>> _jsonObjectList(Object? value, String field) {
  if (value == null) return const [];
  if (value is! List) {
    throw FormatException('Edit graph $field must be an array.');
  }
  return value.map((entry) {
    if (entry is! Map<String, dynamic>) {
      throw FormatException('Edit graph $field entries must be objects.');
    }
    return entry;
  }).toList(growable: false);
}

String _requiredString(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$field must be a non-empty string.');
  }
  return value;
}

num _number(Object? value, String field) {
  if (value is! num) {
    throw FormatException('$field must be numeric.');
  }
  return value;
}

void _ensureUniqueIds(Iterable<String> ids, String label) {
  final seen = <String>{};
  for (final id in ids) {
    if (!seen.add(id)) {
      throw FormatException('Duplicate $label id $id.');
    }
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    for (final value in this) {
      return value;
    }
    return null;
  }
}
