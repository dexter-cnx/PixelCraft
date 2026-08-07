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
