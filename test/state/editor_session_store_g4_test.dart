import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcraft/core/editor_session_store.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('pixelcraft-session-test-');
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  String recipe({int cursor = 1, int checkpoint = 0}) => jsonEncode({
        'version': 1,
        'operations': [
          {'type': 'filter', 'name': 'brightness', 'value': 1.2},
        ],
        'cursor': cursor,
        'checkpoint_cursor': checkpoint,
      });

  test('round trips a validated recovery generation', () async {
    final store = EditorSessionStore(rootDirectory: root);
    final source = Uint8List.fromList(List<int>.generate(64, (index) => index));

    await store.save(originalBytes: source, recipeJson: recipe());
    final restored = await store.load();

    expect(restored, isNotNull);
    expect(restored!.originalBytes, orderedEquals(source));
    expect(restored.recipeJson, recipe());
  });

  test('refuses to persist invalid recipe bounds', () async {
    final store = EditorSessionStore(rootDirectory: root);
    final source = Uint8List.fromList([1, 2, 3]);

    expect(
      () => store.save(
        originalBytes: source,
        recipeJson: recipe(cursor: 3),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('falls back when newest source payload no longer matches manifest', () async {
    final store = EditorSessionStore(rootDirectory: root);
    final sourceA = Uint8List.fromList(List<int>.filled(40, 7));
    final sourceB = Uint8List.fromList(List<int>.filled(40, 9));

    await store.save(originalBytes: sourceA, recipeJson: recipe());
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await store.save(originalBytes: sourceB, recipeJson: recipe());

    final sessionDirectory = Directory('${root.path}/pixelcraft-session');
    final manifests = await sessionDirectory
        .list()
        .where((entity) =>
            entity is File && entity.path.contains('/generation.'))
        .cast<File>()
        .toList();
    manifests.sort((left, right) => right.path.compareTo(left.path));
    final newestManifest =
        jsonDecode(await manifests.first.readAsString()) as Map<String, dynamic>;
    final newestSource =
        File('${sessionDirectory.path}/${newestManifest['sourceFile']}');
    await newestSource.writeAsBytes(List<int>.filled(40, 1), flush: true);

    final restored = await store.load();

    expect(restored, isNotNull);
    expect(restored!.originalBytes, orderedEquals(sourceA));
  });
}
