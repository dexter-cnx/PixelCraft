import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcraft/core/editor_session_store.dart';
import 'package:pixelcraft/state/editor_controller.dart';

import '../helpers/fake_image_engine.dart';

void main() {
  group('EditorController', () {
    late Directory tempDirectory;
    late EditorSessionStore sessionStore;

    setUp(() {
      tempDirectory = Directory.systemTemp.createTempSync('pixelcraft-controller-test-');
      sessionStore = EditorSessionStore(rootDirectory: tempDirectory);
    });

    tearDown(() {
      if (tempDirectory.existsSync()) tempDirectory.deleteSync(recursive: true);
    });

    EditorController controllerFor(FakeImageEngine engine) =>
        EditorController(engine, sessionStore);

    Future<void> settlePreview(EditorController controller) async {
      for (var attempt = 0; attempt < 100; attempt++) {
        if (!controller.state.isPreviewProcessing) return;
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      fail('Preview queue did not settle');
    }

    Future<void> settleThumbnails(EditorController controller) async {
      for (var attempt = 0; attempt < 100; attempt++) {
        if (!controller.state.isGeneratingFilterPreviews &&
            !controller.state.isGeneratingFilmPreviews) {
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      fail('Thumbnail prewarm did not settle');
    }

    test('loads image and prewarms filter and film thumbnails', () async {
      final engine = FakeImageEngine();
      final controller = controllerFor(engine);

      await controller.load(Uint8List.fromList([1, 2, 3]));
      await settleThumbnails(controller);

      expect(engine.loadCalls, 1);
      expect(controller.state.previewBytes, testPngBytes);
      expect(controller.state.originalPreviewBytes, testPngBytes);
      expect(controller.state.histogram.length, 768);
      expect(controller.state.cursor, 0);
      expect(controller.state.selectedCreativeFilter, isEmpty);
      expect(controller.state.selectedFilmProfile, isEmpty);
      expect(controller.state.filmProfiles, isNotEmpty);
      expect(engine.filterPreviewGenerationCalls, 1);
      expect(engine.filmPreviewGenerationCalls, 1);
      expect(controller.state.filterPreviews.keys, containsAll(creativeFilters));
      expect(
        controller.state.filmProfilePreviews.keys,
        containsAll(engine.profiles.map((profile) => profile.id)),
      );
      expect(controller.state.error, isNull);
      expect(controller.state.isBusy, isFalse);
    });

    test('reports load errors without throwing', () async {
      final engine = FakeImageEngine()..failLoad = true;
      final controller = controllerFor(engine);

      await controller.load(Uint8List.fromList([1]));

      expect(controller.state.previewBytes, isNull);
      expect(controller.state.error, contains('decode failed'));
      expect(controller.state.isBusy, isFalse);
    });

    test('adjust preview is asynchronous and latest request wins', () async {
      final engine = FakeImageEngine()
        ..previewDelay = const Duration(milliseconds: 8);
      final controller = controllerFor(engine);
      await controller.load(Uint8List.fromList([1]));

      controller.selectFilter('contrast');
      controller.commitFilterValue(1.2);
      controller.commitFilterValue(1.4);
      controller.commitFilterValue(0.85);

      expect(controller.state.isPreviewProcessing, isTrue);
      await settlePreview(controller);

      expect(engine.activeFilter, 'contrast');
      expect(engine.lastValue, 0.85);
      expect(controller.state.value, 0.85);
      expect(controller.state.operationCount, 1);
      expect(controller.state.cursor, 1);
      expect(controller.state.isPreviewProcessing, isFalse);
      expect(engine.commitCalls + engine.replaceFilterCalls, lessThanOrEqualTo(3));
    });

    test('adjust controls remember independent values before Apply', () async {
      final engine = FakeImageEngine();
      final controller = controllerFor(engine);
      await controller.load(Uint8List.fromList([1]));

      controller.selectFilter('brightness');
      controller.commitFilterValue(1.2);
      await settlePreview(controller);

      controller.selectFilter('contrast');
      controller.commitFilterValue(1.3);
      await settlePreview(controller);

      controller.selectFilter('brightness');
      expect(controller.state.value, 1.2);

      controller.selectFilter('contrast');
      expect(controller.state.value, 1.3);
      expect(controller.state.operationCount, 2);
    });

    test('transform does not cancel an in-flight preview result', () async {
      final engine = FakeImageEngine()
        ..previewDelay = const Duration(milliseconds: 20);
      final controller = controllerFor(engine);
      await controller.load(Uint8List.fromList([1]));

      controller.commitFilterValue(1.2);
      expect(controller.state.isPreviewProcessing, isTrue);

      await controller.rotateRight();
      await settlePreview(controller);

      expect(engine.cursor, 1);
      expect(controller.state.cursor, 1);
      expect(controller.state.operationCount, 1);
      expect(controller.state.isPreviewProcessing, isFalse);
    });

    test('opening filters reuses thumbnails prewarmed at image load', () async {
      final engine = FakeImageEngine();
      final controller = controllerFor(engine);
      await controller.load(Uint8List.fromList([1]));
      await settleThumbnails(controller);

      expect(engine.filterPreviewGenerationCalls, 1);
      await controller.selectTool(EditorTool.filters);

      expect(engine.filterPreviewGenerationCalls, 1);
      expect(controller.state.filterPreviews.keys, containsAll(creativeFilters));
    });

    test('changing creative filters replaces the same history operation', () async {
      final engine = FakeImageEngine();
      final controller = controllerFor(engine);
      await controller.load(Uint8List.fromList([1]));
      await settleThumbnails(controller);

      controller.applyCreativeFilter('vintage');
      await settlePreview(controller);
      expect(controller.state.operationCount, 1);

      controller.applyCreativeFilter('oceanic');
      await settlePreview(controller);

      expect(engine.activeFilter, 'oceanic');
      expect(engine.lastValue, 1);
      expect(controller.state.operationCount, 1);
      expect(controller.state.selectedCreativeFilter, 'oceanic');
      expect(engine.operations.single['name'], 'oceanic');
    });

    test('film profile selection and strength use one replaceable draft', () async {
      final engine = FakeImageEngine();
      final controller = controllerFor(engine);
      await controller.load(Uint8List.fromList([1]));
      await settleThumbnails(controller);

      controller.selectFilmProfile('provia_inspired');
      await settlePreview(controller);
      expect(engine.restoreSessionCalls, 1);
      expect(controller.state.operationCount, 1);
      expect(controller.state.selectedFilmProfile, 'provia_inspired');

      controller.updateFilmProfileStrength(0.55);
      await settlePreview(controller);
      expect(engine.restoreSessionCalls, 2);
      expect(engine.activeFilmProfile, 'provia_inspired');
      expect(engine.lastValue, 0.55);
      expect(controller.state.operationCount, 1);
      expect(controller.state.filmProfileStrength, 0.55);
      expect(engine.operations.single['type'], 'film_profile');
      expect(engine.operations.single['strength'], 0.55);
    });

    test('film preview queue also uses latest request wins', () async {
      final engine = FakeImageEngine()
        ..previewDelay = const Duration(milliseconds: 8);
      final controller = controllerFor(engine);
      await controller.load(Uint8List.fromList([1]));
      await settleThumbnails(controller);

      controller.selectFilmProfile('provia_inspired');
      controller.updateFilmProfileStrength(0.8);
      controller.updateFilmProfileStrength(0.35);
      await settlePreview(controller);

      expect(engine.activeFilmProfile, 'provia_inspired');
      expect(engine.lastValue, 0.35);
      expect(controller.state.filmProfileStrength, 0.35);
      expect(controller.state.operationCount, 1);
    });

    test('apply promotes draft and prewarms both thumbnail groups', () async {
      final engine = FakeImageEngine();
      final controller = controllerFor(engine);
      await controller.load(Uint8List.fromList([1]));
      await settleThumbnails(controller);
      final filtersBefore = engine.filterPreviewGenerationCalls;
      final filmBefore = engine.filmPreviewGenerationCalls;

      controller.selectFilmProfile('provia_inspired');
      await settlePreview(controller);
      await controller.applyEdits();
      await settleThumbnails(controller);

      expect(engine.applyEditsCalls, 1);
      expect(controller.state.cursor, 0);
      expect(controller.state.operationCount, 0);
      expect(controller.state.selectedFilmProfile, isEmpty);
      expect(controller.state.originalPreviewBytes, controller.state.previewBytes);
      expect(engine.filterPreviewGenerationCalls, filtersBefore + 1);
      expect(engine.filmPreviewGenerationCalls, filmBefore + 1);
    });

    test('cancel discards draft operations without regenerating thumbnails', () async {
      final engine = FakeImageEngine();
      final controller = controllerFor(engine);
      await controller.load(Uint8List.fromList([1]));
      await settleThumbnails(controller);
      final filterCalls = engine.filterPreviewGenerationCalls;
      final filmCalls = engine.filmPreviewGenerationCalls;

      controller.applyCreativeFilter('vintage');
      await settlePreview(controller);
      await controller.rotateRight();
      expect(controller.state.hasUnappliedEdits, isTrue);

      await controller.cancelEdits();

      expect(engine.discardEditsCalls, 1);
      expect(controller.state.cursor, 0);
      expect(controller.state.operationCount, 0);
      expect(engine.filterPreviewGenerationCalls, filterCalls);
      expect(engine.filmPreviewGenerationCalls, filmCalls);
    });

    test('crop rotate flip and straighten remain draft operations until apply', () async {
      final engine = FakeImageEngine();
      final controller = controllerFor(engine);
      await controller.load(Uint8List.fromList([1]));

      await controller.applyCenteredCrop(1);
      await controller.rotateRight();
      await controller.flipHorizontal();
      await controller.flipVertical();
      await controller.commitStraighten(2.5);

      expect(engine.transformCalls, 5);
      expect(controller.state.operationCount, 5);
      expect(controller.state.cursor, 5);
      expect(controller.state.hasUnappliedEdits, isTrue);
    });

    test('restores an engine recipe into the editor state', () async {
      final engine = FakeImageEngine();
      final controller = controllerFor(engine);

      await controller.restore(Uint8List.fromList([1, 2]), '{"draft":true}');

      expect(engine.restoreSessionCalls, 1);
      expect(controller.state.previewBytes, testPngBytes);
      expect(controller.state.cursor, 1);
      expect(controller.state.canUndo, isTrue);
    });

    test('persists a recoverable recipe after editing', () async {
      final engine = FakeImageEngine();
      final controller = controllerFor(engine);
      await controller.load(Uint8List.fromList([1, 2, 3]));

      controller.commitFilterValue(1.3);
      await settlePreview(controller);
      for (var attempt = 0; attempt < 50; attempt++) {
        final stored = await sessionStore.load();
        if (stored?.recipeJson.contains('"cursor":1') ?? false) break;
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }

      final stored = await sessionStore.load();
      expect(stored, isNotNull);
      expect(stored!.originalBytes, [1, 2, 3]);
      expect(stored.recipeJson, contains('"cursor":1'));
    });

    test('serializes recipe capture so an older save cannot win', () async {
      final engine = _OutOfOrderRecipeEngine();
      final controller = controllerFor(engine);
      await controller.load(Uint8List.fromList([4, 5, 6]));

      controller.commitFilterValue(1.2);
      await settlePreview(controller);

      for (var attempt = 0; attempt < 100; attempt++) {
        final stored = await sessionStore.load();
        if (stored?.recipeJson.contains('"cursor":1') ?? false) break;
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }

      final stored = await sessionStore.load();
      expect(stored, isNotNull);
      expect(stored!.originalBytes, [4, 5, 6]);
      expect(stored.recipeJson, contains('"cursor":1'));
      expect(engine.exportSessionRecipeCalls, greaterThanOrEqualTo(2));
    });

    test('undo and redo move the operation cursor', () async {
      final engine = FakeImageEngine();
      final controller = controllerFor(engine);
      await controller.load(Uint8List.fromList([1]));
      controller.commitFilterValue(1.3);
      await settlePreview(controller);

      await controller.undo();
      expect(engine.undoCalls, 1);
      expect(controller.state.cursor, 0);
      expect(controller.state.canRedo, isTrue);

      await controller.redo();
      expect(engine.redoCalls, 1);
      expect(controller.state.cursor, 1);
    });

    test('exports through the background engine API', () async {
      final engine = FakeImageEngine();
      final controller = controllerFor(engine);
      await controller.load(Uint8List.fromList([1]));

      final bytes = await controller.exportImage(format: 'jpeg', quality: 90);

      expect(bytes, testPngBytes);
      expect(engine.exportCalls, 1);
      expect(controller.state.isExporting, isFalse);
    });
  });
}

class _OutOfOrderRecipeEngine extends FakeImageEngine {
  int _recipeCall = 0;

  @override
  Future<String> exportSessionRecipeInBackground() async {
    exportSessionRecipeCalls++;
    final capturedCursor = cursor;
    final call = _recipeCall++;
    if (call == 0) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    return '{"version":1,"cursor":$capturedCursor}';
  }
}
