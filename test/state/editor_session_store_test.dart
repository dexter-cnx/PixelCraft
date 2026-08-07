import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcraft/core/editor_session_store.dart';

void main() {
  group('EditorSessionStore', () {
    late Directory root;
    late EditorSessionStore store;

    setUp(() {
      root = Directory.systemTemp.createTempSync('pixelcraft-session-store-');
      store = EditorSessionStore(rootDirectory: root);
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    test('saves and restores original bytes plus recipe', () async {
      await store.save(
        originalBytes: Uint8List.fromList([1, 2, 3, 4]),
        recipeJson: '{"version":1,"operations":[]}',
      );

      expect(await store.exists(), isTrue);
      final restored = await store.load();
      expect(restored, isNotNull);
      expect(restored!.originalBytes, [1, 2, 3, 4]);
      expect(restored.recipeJson, contains('operations'));
      expect(restored.savedAt.millisecondsSinceEpoch, greaterThan(0));
    });

    test('newer writes replace the previous recoverable session', () async {
      await store.save(
        originalBytes: Uint8List.fromList([1]),
        recipeJson: '{"version":1,"cursor":0}',
      );
      await store.save(
        originalBytes: Uint8List.fromList([9, 8]),
        recipeJson: '{"version":1,"cursor":2}',
      );

      final restored = await store.load();
      expect(restored!.originalBytes, [9, 8]);
      expect(restored.recipeJson, contains('"cursor":2'));
    });

    test('ignores payloads that were never published by a generation manifest', () async {
      await store.save(
        originalBytes: Uint8List.fromList([1, 2]),
        recipeJson: '{"version":1,"cursor":1}',
      );

      final directory = Directory('${root.path}/pixelcraft-session');
      await File('${directory.path}/source.orphan.bin').writeAsBytes([9, 9, 9]);
      await File('${directory.path}/recipe.orphan.json')
          .writeAsString('{"version":1,"cursor":99}');

      final restored = await store.load();
      expect(restored, isNotNull);
      expect(restored!.originalBytes, [1, 2]);
      expect(restored.recipeJson, contains('"cursor":1'));
    });

    test('falls back to the previous coherent generation if latest payload is missing', () async {
      await store.save(
        originalBytes: Uint8List.fromList([1]),
        recipeJson: '{"version":1,"cursor":1}',
      );
      await store.save(
        originalBytes: Uint8List.fromList([2]),
        recipeJson: '{"version":1,"cursor":2}',
      );

      final directory = Directory('${root.path}/pixelcraft-session');
      final manifests = directory
          .listSync()
          .whereType<File>()
          .where((file) => file.uri.pathSegments.last.startsWith('generation.'))
          .toList()
        ..sort((left, right) => right.path.compareTo(left.path));
      final latestManifest = await manifests.first.readAsString();
      final recipeMatch = RegExp(r'"recipeFile":"([^"]+)"').firstMatch(latestManifest);
      expect(recipeMatch, isNotNull);
      await File('${directory.path}/${recipeMatch!.group(1)}').delete();

      final restored = await store.load();
      expect(restored, isNotNull);
      expect(restored!.originalBytes, [1]);
      expect(restored.recipeJson, contains('"cursor":1'));
    });

    test('clear removes the recovery payload', () async {
      await store.save(
        originalBytes: Uint8List.fromList([1]),
        recipeJson: '{"version":1}',
      );
      await store.clear();

      expect(await store.exists(), isFalse);
      expect(await store.load(), isNull);
    });
  });
}
