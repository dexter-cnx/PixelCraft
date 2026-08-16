import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcraft/core/workspace_catalog_store.dart';
import 'package:pixelcraft/ui/screens/home_screen.dart';

import '../helpers/fake_image_engine.dart';

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
    final source = File('${root.path}/persisted.png');
    await source.writeAsBytes(testPngBytes, flush: true);
    await catalogStore.add(
      sourceKind: WorkspaceSourceKind.gallery,
      retention: WorkspaceSourceRetention.externalReference,
      sourcePath: source.path,
      availability: WorkspaceSourceAvailability.available,
      now: DateTime.utc(2026, 8, 16, 3),
    );

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

    expect(find.text('Workspace'), findsOneWidget);
    expect(find.text('persisted.png'), findsOneWidget);
    expect(find.text('gallery'), findsOneWidget);
    expect(find.text('Your workspace is empty'), findsNothing);
  });

  testWidgets('marks a missing source without deleting catalog identity',
      (tester) async {
    final item = await catalogStore.add(
      sourceKind: WorkspaceSourceKind.gallery,
      retention: WorkspaceSourceRetention.externalReference,
      sourcePath: '${root.path}/missing.png',
      availability: WorkspaceSourceAvailability.available,
      now: DateTime.utc(2026, 8, 16, 3),
    );

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

    await tester.tap(find.text('missing.png'));
    await tester.pumpAndSettle();

    expect(find.text('This source file is no longer available.'), findsOneWidget);
    final saved = (await catalogStore.load()).single;
    expect(saved.id, item.id);
    expect(saved.availability, WorkspaceSourceAvailability.missing);
    expect(find.text('Source missing'), findsOneWidget);
  });
}
