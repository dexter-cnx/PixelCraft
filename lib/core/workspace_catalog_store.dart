import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

enum WorkspaceSourceKind {
  gallery,
  systemCamera,
  filmCamera,
}

enum WorkspaceSourceRetention {
  externalReference,
  managedCopy,
}

enum WorkspaceSourceAvailability {
  unknown,
  available,
  missing,
}

class WorkspaceCatalogItem {
  const WorkspaceCatalogItem({
    required this.id,
    required this.sourceKind,
    required this.retention,
    required this.sourcePath,
    required this.availability,
    required this.importedAt,
    required this.updatedAt,
    this.lastOpenedAt,
  });

  final String id;
  final WorkspaceSourceKind sourceKind;
  final WorkspaceSourceRetention retention;
  final String sourcePath;
  final WorkspaceSourceAvailability availability;
  final DateTime importedAt;
  final DateTime updatedAt;
  final DateTime? lastOpenedAt;

  WorkspaceCatalogItem copyWith({
    WorkspaceSourceAvailability? availability,
    DateTime? updatedAt,
    DateTime? lastOpenedAt,
  }) {
    return WorkspaceCatalogItem(
      id: id,
      sourceKind: sourceKind,
      retention: retention,
      sourcePath: sourcePath,
      availability: availability ?? this.availability,
      importedAt: importedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'sourceKind': sourceKind.name,
        'retention': retention.name,
        'sourcePath': sourcePath,
        'availability': availability.name,
        'importedAt': importedAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        if (lastOpenedAt != null)
          'lastOpenedAt': lastOpenedAt!.toUtc().toIso8601String(),
      };

  static WorkspaceCatalogItem? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;

    final id = value['id'];
    final sourceKind = _enumByName(WorkspaceSourceKind.values, value['sourceKind']);
    final retention =
        _enumByName(WorkspaceSourceRetention.values, value['retention']);
    final sourcePath = value['sourcePath'];
    final availability = _enumByName(
      WorkspaceSourceAvailability.values,
      value['availability'],
    );
    final importedAt = _date(value['importedAt']);
    final updatedAt = _date(value['updatedAt']);
    final lastOpenedAt = value['lastOpenedAt'] == null
        ? null
        : _date(value['lastOpenedAt']);

    if (id is! String ||
        id.isEmpty ||
        sourceKind == null ||
        retention == null ||
        sourcePath is! String ||
        sourcePath.isEmpty ||
        availability == null ||
        importedAt == null ||
        updatedAt == null ||
        (value['lastOpenedAt'] != null && lastOpenedAt == null)) {
      return null;
    }

    return WorkspaceCatalogItem(
      id: id,
      sourceKind: sourceKind,
      retention: retention,
      sourcePath: sourcePath,
      availability: availability,
      importedAt: importedAt,
      updatedAt: updatedAt,
      lastOpenedAt: lastOpenedAt,
    );
  }

  static T? _enumByName<T extends Enum>(List<T> values, Object? name) {
    if (name is! String) return null;
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  static DateTime? _date(Object? value) {
    if (value is! String) return null;
    return DateTime.tryParse(value)?.toUtc();
  }
}

class WorkspaceCatalogStore {
  WorkspaceCatalogStore({this.rootDirectory});

  static const _schemaVersion = 1;
  static final Map<String, Future<void>> _sharedWriteTails = {};

  final Directory? rootDirectory;

  Future<Directory> _directory() async {
    final root = rootDirectory ?? await getApplicationSupportDirectory();
    return Directory('${root.path}/pixelcraft-workspace');
  }

  Future<File> _manifestFile() async {
    final directory = await _directory();
    return File('${directory.path}/catalog.json');
  }

  Future<List<WorkspaceCatalogItem>> load() async {
    try {
      final directory = await _directory();
      final key = directory.absolute.path;
      await (_sharedWriteTails[key] ?? Future<void>.value());
      return await _loadUnlocked(strict: false);
    } catch (_) {
      return const [];
    }
  }

  Future<WorkspaceCatalogItem> add({
    required WorkspaceSourceKind sourceKind,
    required WorkspaceSourceRetention retention,
    required String sourcePath,
    WorkspaceSourceAvailability availability =
        WorkspaceSourceAvailability.unknown,
    DateTime? now,
  }) {
    if (sourcePath.trim().isEmpty) {
      throw const FormatException('Workspace source path must not be empty');
    }

    final timestamp = (now ?? DateTime.now()).toUtc();
    return _enqueueWrite(() async {
      final items = await _loadUnlocked(strict: true);
      final item = WorkspaceCatalogItem(
        id: _nextAvailableId(timestamp, items),
        sourceKind: sourceKind,
        retention: retention,
        sourcePath: sourcePath,
        availability: availability,
        importedAt: timestamp,
        updatedAt: timestamp,
      );
      await _writeUnlocked([item, ...items]);
      return item;
    });
  }

  Future<void> upsert(WorkspaceCatalogItem item) {
    return _enqueueWrite(() async {
      final items = await _loadUnlocked(strict: true);
      final next = [
        item,
        ...items.where((candidate) => candidate.id != item.id),
      ];
      await _writeUnlocked(next);
    });
  }

  Future<void> markAvailability(
    String id,
    WorkspaceSourceAvailability availability, {
    DateTime? now,
  }) {
    return _enqueueWrite(() async {
      final items = await _loadUnlocked(strict: true);
      final timestamp = (now ?? DateTime.now()).toUtc();
      final next = items
          .map(
            (item) => item.id == id
                ? item.copyWith(
                    availability: availability,
                    updatedAt: timestamp,
                  )
                : item,
          )
          .toList();
      await _writeUnlocked(next);
    });
  }

  Future<void> markOpened(String id, {DateTime? now}) {
    return _enqueueWrite(() async {
      final items = await _loadUnlocked(strict: true);
      final timestamp = (now ?? DateTime.now()).toUtc();
      final next = items
          .map(
            (item) => item.id == id
                ? item.copyWith(
                    updatedAt: timestamp,
                    lastOpenedAt: timestamp,
                  )
                : item,
          )
          .toList();
      await _writeUnlocked(next);
    });
  }

  Future<void> remove(String id) {
    return _enqueueWrite(() async {
      final items = await _loadUnlocked(strict: true);
      await _writeUnlocked(
        items.where((item) => item.id != id).toList(),
      );
    });
  }

  Future<void> clear() {
    return _enqueueWrite(() async {
      final directory = await _directory();
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });
  }

  Future<T> _enqueueWrite<T>(Future<T> Function() operation) async {
    final directory = await _directory();
    final key = directory.absolute.path;
    final previous = _sharedWriteTails[key] ?? Future<void>.value();
    final current = previous.catchError((_) {}).then((_) => operation());
    final tail = current.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    _sharedWriteTails[key] = tail;

    try {
      return await current;
    } finally {
      if (identical(_sharedWriteTails[key], tail)) {
        _sharedWriteTails.remove(key);
      }
    }
  }

  Future<List<WorkspaceCatalogItem>> _loadUnlocked({
    required bool strict,
  }) async {
    final file = await _manifestFile();
    final backup = File('${file.path}.bak');

    if (!await file.exists()) {
      if (!await backup.exists()) return const [];
      return _decodeManifest(backup);
    }

    try {
      return await _decodeManifest(file);
    } catch (_) {
      if (strict) rethrow;
      if (!await backup.exists()) return const [];
      try {
        return await _decodeManifest(backup);
      } catch (_) {
        return const [];
      }
    }
  }

  Future<List<WorkspaceCatalogItem>> _decodeManifest(File file) async {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic> ||
        decoded['version'] != _schemaVersion ||
        decoded['items'] is! List) {
      throw const FormatException('Unsupported workspace catalog manifest');
    }

    final items = <WorkspaceCatalogItem>[];
    for (final raw in decoded['items'] as List<dynamic>) {
      final item = WorkspaceCatalogItem.fromJson(raw);
      if (item == null) {
        throw const FormatException('Invalid workspace catalog item');
      }
      items.add(item);
    }
    items.sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return items;
  }

  Future<void> _writeUnlocked(List<WorkspaceCatalogItem> items) async {
    final directory = await _directory();
    await directory.create(recursive: true);

    final file = File('${directory.path}/catalog.json');
    final temp = File('${file.path}.tmp');
    final backup = File('${file.path}.bak');

    if (await temp.exists()) await temp.delete();
    await temp.writeAsString(
      jsonEncode({
        'version': _schemaVersion,
        'items': items.map((item) => item.toJson()).toList(),
      }),
      flush: true,
    );

    if (await file.exists()) {
      if (await backup.exists()) await backup.delete();
      await file.rename(backup.path);
    }

    try {
      await temp.rename(file.path);
      if (await backup.exists()) await backup.delete();
    } catch (_) {
      if (!await file.exists() && await backup.exists()) {
        await backup.rename(file.path);
      }
      rethrow;
    }
  }

  String _nextAvailableId(
    DateTime timestamp,
    List<WorkspaceCatalogItem> items,
  ) {
    final micros = timestamp.microsecondsSinceEpoch.toString().padLeft(20, '0');
    final prefix = 'workspace-$micros';
    final existing = items.map((item) => item.id).toSet();
    var counter = 0;
    while (true) {
      final suffix = counter.toString().padLeft(6, '0');
      final candidate = '$prefix-$suffix';
      if (!existing.contains(candidate)) return candidate;
      counter += 1;
    }
  }
}
