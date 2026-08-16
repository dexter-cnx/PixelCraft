import 'dart:io';

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

void main() {
  late Directory root;
  late WorkspaceCatalogStore catalogStore;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('pixelcraft-home-workspace-');
    catalogStore = WorkspaceCatalogStore(rootDirectory: root);
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  testWidgets('shows workspace-first home and import action', (tester) async {
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

  testWidgets('renders persisted catalog items as real workspace content',
      (tester) async {
    await tester.runAsync(() async {
      await catalogStore.add(
        sourceKind: WorkspaceSourceKind.gallery,
        retention: WorkspaceSourceRetention.externalReference,
        sourcePath: '${root.path}/persisted.png',
        availability: WorkspaceSourceAvailability.missing,
        now: DateTime.utc(2026, 8, 16, 3),
      );
    });

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

  testWidgets('preserves missing source catalog identity when open fails',
      (tester) async {
    late WorkspaceCatalogItem item;
    await tester.runAsync(() async {
      item = await catalogStore.add(
        sourceKind: WorkspaceSourceKind.gallery,
        retention: WorkspaceSourceRetention.externalReference,
        sourcePath: '${root.path}/missing.png',
        availability: WorkspaceSourceAvailability.missing,
        now: DateTime.utc(2026, 8, 16, 3),
      );
    });

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

    await tester.tap(find.text('missing.png'));
    await _pumpUntilFound(
      tester,
      find.text('This source file is no longer available.'),
    );

    late WorkspaceCatalogItem saved;
    await tester.runAsync(() async {
      saved = (await catalogStore.load()).single;
    });
    expect(saved.id, item.id);
    expect(saved.availability, WorkspaceSourceAvailability.missing);
    expect(find.text('Source missing'), findsOneWidget);
  });
}
