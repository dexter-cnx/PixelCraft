import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcraft/core/editor_session_store.dart';
import 'package:pixelcraft/core/film_profile_v1.dart';

void main() {
  group('G6.5 recovery failure injection', () {
    late Directory root;
    late EditorSessionStore store;

    String recipe({required int cursor, int checkpoint = 0}) => jsonEncode({
          'version': 1,
          'preview_max_edge': 1024,
          'operations': List.generate(
            cursor,
            (index) => {
              'type': 'filter',
              'name': 'brightness',
              'value': 1.0 + index / 10,
            },
          ),
          'cursor': cursor,
          'checkpoint_cursor': checkpoint,
        });

    setUp(() {
      root = Directory.systemTemp.createTempSync('pixelcraft-g6-failure-');
      store = EditorSessionStore(rootDirectory: root);
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    List<File> manifests() {
      final directory = Directory('${root.path}/pixelcraft-session');
      return directory
          .listSync()
          .whereType<File>()
          .where((file) => file.uri.pathSegments.last.startsWith('generation.'))
          .toList()
        ..sort((left, right) => right.path.compareTo(left.path));
    }

    test('corrupt newest manifest falls back to previous coherent generation', () async {
      await store.save(
        originalBytes: Uint8List.fromList([1, 2, 3]),
        recipeJson: recipe(cursor: 1),
      );
      await store.save(
        originalBytes: Uint8List.fromList([9, 8, 7]),
        recipeJson: recipe(cursor: 2),
      );

      final generations = manifests();
      expect(generations.length, greaterThanOrEqualTo(2));
      await generations.first.writeAsString('{ definitely-not-json');

      final restored = await store.load();
      expect(restored, isNotNull);
      expect(restored!.originalBytes, [1, 2, 3]);
      expect(jsonDecode(restored.recipeJson)['cursor'], 1);
    });

    test('source fingerprint mismatch rejects newest generation and falls back', () async {
      await store.save(
        originalBytes: Uint8List.fromList([1, 1, 1]),
        recipeJson: recipe(cursor: 1),
      );
      await store.save(
        originalBytes: Uint8List.fromList([2, 2, 2, 2]),
        recipeJson: recipe(cursor: 2),
      );

      final latest = jsonDecode(await manifests().first.readAsString()) as Map<String, dynamic>;
      final directory = Directory('${root.path}/pixelcraft-session');
      final source = File('${directory.path}/${latest['sourceFile']}');
      await source.writeAsBytes([99, 98, 97, 96], flush: true);

      final restored = await store.load();
      expect(restored, isNotNull);
      expect(restored!.originalBytes, [1, 1, 1]);
      expect(jsonDecode(restored.recipeJson)['cursor'], 1);
    });

    test('invalid recipe bounds are rejected before persistence', () async {
      final invalidCursor = jsonEncode({
        'operations': <Object?>[],
        'cursor': 1,
        'checkpoint_cursor': 0,
      });
      final invalidCheckpoint = jsonEncode({
        'operations': <Object?>[{'type': 'filter'}],
        'cursor': 1,
        'checkpoint_cursor': 2,
      });

      await expectLater(
        Future<void>.sync(
          () => store.save(
            originalBytes: Uint8List.fromList([1]),
            recipeJson: invalidCursor,
          ),
        ),
        throwsFormatException,
      );
      await expectLater(
        Future<void>.sync(
          () => store.save(
            originalBytes: Uint8List.fromList([1]),
            recipeJson: invalidCheckpoint,
          ),
        ),
        throwsFormatException,
      );
      expect(await store.load(), isNull);
    });
  });

  group('G6.5 Film Profile failure injection', () {
    test('corrupt JSON is rejected explicitly', () {
      expect(() => FilmProfileV1.decode('{oops'), throwsFormatException);
    });

    test('unsupported schema version and future engine are rejected', () {
      final base = <String, Object?>{
        'schema': pixelCraftProfileSchema,
        'schemaVersion': pixelCraftProfileSchemaVersion,
        'minEngineVersion': pixelCraftProfileEngineVersion,
        'id': 'g6-profile',
        'name': 'G6 Profile',
        'origin': 'imported',
        'baseFilmId': '',
        'baseStrength': 1.0,
        'parameters': <String, double>{},
        'tags': <String>[],
      };

      expect(
        () => FilmProfileV1.decode(jsonEncode({...base, 'schemaVersion': 999})),
        throwsFormatException,
      );
      expect(
        () => FilmProfileV1.decode(jsonEncode({...base, 'minEngineVersion': 999})),
        throwsFormatException,
      );
    });

    test('unknown profile parameter is rejected instead of silently dropped', () {
      final profile = {
        'schema': pixelCraftProfileSchema,
        'schemaVersion': pixelCraftProfileSchemaVersion,
        'minEngineVersion': pixelCraftProfileEngineVersion,
        'id': 'g6-profile',
        'name': 'G6 Profile',
        'parameters': {'mystery_parameter': 0.5},
      };

      expect(
        () => FilmProfileV1.decode(jsonEncode(profile)),
        throwsFormatException,
      );
    });

    test('generic importer reports unsupported fields explicitly', () {
      final report = importRecipeMap(
        const {
          'exposure': 0.25,
          'highlightTone': -0.4,
          'vendorSecretSauce': 42,
        },
        id: 'g6-import',
      );

      expect(report.hasUnsupported, isTrue);
      expect(
        report.mappings.any(
          (mapping) =>
              mapping.sourceField == 'vendorSecretSauce' &&
              mapping.kind == FilmProfileMappingKind.unsupported,
        ),
        isTrue,
      );
      expect(
        report.mappings.any(
          (mapping) =>
              mapping.sourceField == 'highlightTone' &&
              mapping.kind == FilmProfileMappingKind.approximated,
        ),
        isTrue,
      );
    });
  });
}
