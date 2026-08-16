import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcraft/core/workspace_catalog_store.dart';
import 'package:pixelcraft/ui/screens/home_screen.dart';

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 120,
}) async {
  for (var attempt = 0; attempt < maxPumps; attempt++) {
    await tester.pump(const Duration(milliseconds: 16));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for ${finder.describeMatch(Plurality.one)}');
}

class _MemoryWorkspaceCatalogStore extends WorkspaceCatalogStore {
  _MemoryWorkspaceCatalogStore([List<WorkspaceCatalogItem> items = const []])
      : _items = List<WorkspaceCatalogItem>.from(items);

  final List<WorkspaceCatalogItem> _items;

  @override
  Future<List<WorkspaceCatalogItem>> load() async => List.unmodifiable(_items);
}

WorkspaceCatalogItem _item(String name) {
  final timestamp = DateTime.utc(2026, 8, 16, 3);
  return WorkspaceCatalogItem(
    id: 'workspace-$name',
    sourceKind: WorkspaceSourceKind.gallery,
    retention: WorkspaceSourceRetention.externalReference,
    sourcePath: '/does-not-exist/$name',
    availability: WorkspaceSourceAvailability.missing,
    importedAt: timestamp,
    updatedAt: timestamp,
  );
}

void main() {
  testWidgets('shows workspace-first home and import action', (tester) async {
    final catalogStore = _MemoryWorkspaceCatalogStore();
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          recoverLostPickerData: false,
          showGpuDiagnostics: false,
          catalogStoreForTesting: catalogStore,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Dextryx Pixels'), findsOneWidget);
    expect(find.text('Your workspace is empty'), findsOneWidget);
    expect(find.text('Import a photo to start editing.'), findsOneWidget);
    expect(find.text('Import'), findsOneWidget);
    expect(find.byTooltip('More ways to add'), findsOneWidget);

    expect(find.text('Edit locally. Move fast.'), findsNothing);
    expect(find.textContaining('Rust-powered'), findsNothing);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('renders loaded catalog items as real workspace content',
      (tester) async {
    final catalogStore = _MemoryWorkspaceCatalogStore([_item('persisted.png')]);

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          recoverLostPickerData: false,
          showGpuDiagnostics: false,
          catalogStoreForTesting: catalogStore,
        ),
      ),
    );
    await _pumpUntilFound(tester, find.text('persisted.png'));

    expect(find.text('Workspace'), findsOneWidget);
    expect(find.text('persisted.png'), findsOneWidget);
    expect(find.text('Source missing'), findsOneWidget);
    expect(find.text('Your workspace is empty'), findsNothing);
  });

  testWidgets('renders missing source without deleting catalog identity',
      (tester) async {
    final item = _item('missing.png');
    final catalogStore = _MemoryWorkspaceCatalogStore([item]);

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          recoverLostPickerData: false,
          showGpuDiagnostics: false,
          catalogStoreForTesting: catalogStore,
        ),
      ),
    );
    await _pumpUntilFound(tester, find.text('missing.png'));

    expect(find.text('Source missing'), findsOneWidget);
    final saved = (await catalogStore.load()).single;
    expect(saved.id, item.id);
    expect(saved.availability, WorkspaceSourceAvailability.missing);
  });
}
