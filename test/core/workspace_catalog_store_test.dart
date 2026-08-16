import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcraft/core/workspace_catalog_store.dart';

void main() {
  late Directory root;
  late WorkspaceCatalogStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('pixelcraft-workspace-test-');
    store = WorkspaceCatalogStore(rootDirectory: root);
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('persists catalog items with stable identity and source metadata', () async {
    final importedAt = DateTime.utc(2026, 8, 16, 1, 2, 3);
    final item = await store.add(
      sourceKind: WorkspaceSourceKind.gallery,
      retention: WorkspaceSourceRetention.externalReference,
      sourcePath: '/photos/source.jpg',
      availability: WorkspaceSourceAvailability.available,
      now: importedAt,
    );

    final reloaded = WorkspaceCatalogStore(rootDirectory: root);
    final items = await reloaded.load();

    expect(items, hasLength(1));
    expect(items.single.id, item.id);
    expect(items.single.sourceKind, WorkspaceSourceKind.gallery);
    expect(
      items.single.retention,
      WorkspaceSourceRetention.externalReference,
    );
    expect(items.single.sourcePath, '/photos/source.jpg');
    expect(
      items.single.availability,
      WorkspaceSourceAvailability.available,
    );
    expect(items.single.importedAt, importedAt);
    expect(items.single.updatedAt, importedAt);
    expect(items.single.lastOpenedAt, isNull);
  });

  test('loads newest updated item first', () async {
    final first = await store.add(
      sourceKind: WorkspaceSourceKind.gallery,
      retention: WorkspaceSourceRetention.externalReference,
      sourcePath: '/photos/first.jpg',
      now: DateTime.utc(2026, 8, 16, 1),
    );
    final second = await store.add(
      sourceKind: WorkspaceSourceKind.systemCamera,
      retention: WorkspaceSourceRetention.managedCopy,
      sourcePath: '/managed/second.jpg',
      now: DateTime.utc(2026, 8, 16, 2),
    );

    expect((await store.load()).map((item) => item.id), [second.id, first.id]);
  });

  test('tracks source availability without deleting catalog identity', () async {
    final item = await store.add(
      sourceKind: WorkspaceSourceKind.gallery,
      retention: WorkspaceSourceRetention.externalReference,
      sourcePath: '/photos/movable.jpg',
      availability: WorkspaceSourceAvailability.available,
      now: DateTime.utc(2026, 8, 16, 1),
    );

    await store.markAvailability(
      item.id,
      WorkspaceSourceAvailability.missing,
      now: DateTime.utc(2026, 8, 16, 3),
    );

    final saved = (await store.load()).single;
    expect(saved.id, item.id);
    expect(saved.sourcePath, item.sourcePath);
    expect(saved.availability, WorkspaceSourceAvailability.missing);
    expect(saved.updatedAt, DateTime.utc(2026, 8, 16, 3));
  });

  test('tracks last opened time as catalog metadata only', () async {
    final item = await store.add(
      sourceKind: WorkspaceSourceKind.filmCamera,
      retention: WorkspaceSourceRetention.managedCopy,
      sourcePath: '/managed/film.jpg',
      now: DateTime.utc(2026, 8, 16, 1),
    );
    final openedAt = DateTime.utc(2026, 8, 16, 4);

    await store.markOpened(item.id, now: openedAt);

    final saved = (await store.load()).single;
    expect(saved.lastOpenedAt, openedAt);
    expect(saved.updatedAt, openedAt);
  });

  test('remove deletes one catalog identity and preserves others', () async {
    final first = await store.add(
      sourceKind: WorkspaceSourceKind.gallery,
      retention: WorkspaceSourceRetention.externalReference,
      sourcePath: '/photos/first.jpg',
    );
    final second = await store.add(
      sourceKind: WorkspaceSourceKind.gallery,
      retention: WorkspaceSourceRetention.externalReference,
      sourcePath: '/photos/second.jpg',
    );

    await store.remove(first.id);

    final items = await store.load();
    expect(items, hasLength(1));
    expect(items.single.id, second.id);
  });

  test('serializes concurrent writes instead of dropping entries', () async {
    await Future.wait([
      store.add(
        sourceKind: WorkspaceSourceKind.gallery,
        retention: WorkspaceSourceRetention.externalReference,
        sourcePath: '/photos/a.jpg',
      ),
      store.add(
        sourceKind: WorkspaceSourceKind.gallery,
        retention: WorkspaceSourceRetention.externalReference,
        sourcePath: '/photos/b.jpg',
      ),
      store.add(
        sourceKind: WorkspaceSourceKind.systemCamera,
        retention: WorkspaceSourceRetention.managedCopy,
        sourcePath: '/managed/c.jpg',
      ),
    ]);

    expect(await store.load(), hasLength(3));
  });

  test('rejects empty source paths', () async {
    expect(
      () => store.add(
        sourceKind: WorkspaceSourceKind.gallery,
        retention: WorkspaceSourceRetention.externalReference,
        sourcePath: '   ',
      ),
      throwsFormatException,
    );
  });

  test('invalid manifest fails closed to an empty catalog', () async {
    final directory = Directory('${root.path}/pixelcraft-workspace');
    await directory.create(recursive: true);
    await File('${directory.path}/catalog.json').writeAsString('{broken');

    expect(await store.load(), isEmpty);
  });
}
