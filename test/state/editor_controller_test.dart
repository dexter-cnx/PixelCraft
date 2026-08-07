import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcraft/state/editor_controller.dart';

import '../helpers/fake_image_engine.dart';

void main() {
  group('EditorController', () {
    test('loads image, original preview and histogram', () async {
      final engine = FakeImageEngine();
      final controller = EditorController(engine);

      await controller.load(Uint8List.fromList([1, 2, 3]));

      expect(engine.loadCalls, 1);
      expect(controller.state.previewBytes, testPngBytes);
      expect(controller.state.originalPreviewBytes, testPngBytes);
      expect(controller.state.histogram.length, 768);
      expect(controller.state.cursor, 0);
      expect(controller.state.canUndo, isFalse);
      expect(controller.state.error, isNull);
      expect(controller.state.isBusy, isFalse);
    });

    test('reports load errors without throwing', () async {
      final engine = FakeImageEngine()..failLoad = true;
      final controller = EditorController(engine);

      await controller.load(Uint8List.fromList([1]));

      expect(controller.state.previewBytes, isNull);
      expect(controller.state.error, contains('decode failed'));
      expect(controller.state.isBusy, isFalse);
    });

    test('one released slider value creates one committed operation', () async {
      final engine = FakeImageEngine();
      final controller = EditorController(engine);
      await controller.load(Uint8List.fromList([1]));

      controller.selectFilter('contrast');
      await controller.commitFilterValue(1.4);

      expect(engine.beginCalls, 1);
      expect(engine.previewCalls, 1);
      expect(engine.commitCalls, 1);
      expect(engine.activeFilter, 'contrast');
      expect(engine.lastValue, 1.4);
      expect(controller.state.operationCount, 1);
      expect(controller.state.cursor, 1);
      expect(controller.state.canUndo, isTrue);
      expect(controller.state.processingMs, 12.5);
      expect(controller.state.isBusy, isFalse);
    });

    test('crop rotate flip and straighten are committed operations', () async {
      final engine = FakeImageEngine();
      final controller = EditorController(engine);
      await controller.load(Uint8List.fromList([1]));

      await controller.applyCenteredCrop(1);
      await controller.rotateRight();
      await controller.flipHorizontal();
      await controller.flipVertical();
      await controller.commitStraighten(2.5);

      expect(engine.transformCalls, 5);
      expect(controller.state.operationCount, 5);
      expect(controller.state.cursor, 5);
      expect(controller.state.canUndo, isTrue);
      expect(controller.state.straightenDegrees, 0);
    });

    test('tool selection is reflected in state', () {
      final controller = EditorController(FakeImageEngine());
      controller.selectTool(EditorTool.rotate);
      expect(controller.state.selectedTool, EditorTool.rotate);
    });

    test('undo and redo move the operation cursor in background', () async {
      final engine = FakeImageEngine();
      final controller = EditorController(engine);
      await controller.load(Uint8List.fromList([1]));
      await controller.commitFilterValue(1.3);

      await controller.undo();
      expect(engine.undoCalls, 1);
      expect(controller.state.cursor, 0);
      expect(controller.state.canRedo, isTrue);

      await controller.redo();
      expect(engine.redoCalls, 1);
      expect(controller.state.cursor, 1);
      expect(controller.state.histogram, engine.bins);
    });

    test('before-after toggles the visible preview', () async {
      final edited = Uint8List.fromList([9]);
      final engine = FakeImageEngine(output: edited);
      final controller = EditorController(engine);
      await controller.load(Uint8List.fromList([1]));

      controller.setShowOriginal(true);
      expect(controller.state.showOriginal, isTrue);
      expect(controller.state.visiblePreview, controller.state.originalPreviewBytes);

      controller.setShowOriginal(false);
      expect(controller.state.visiblePreview, controller.state.previewBytes);
    });

    test('exports through the background engine API', () async {
      final engine = FakeImageEngine();
      final controller = EditorController(engine);
      await controller.load(Uint8List.fromList([1]));

      final bytes = await controller.exportImage(format: 'jpeg', quality: 90);

      expect(bytes, testPngBytes);
      expect(engine.exportCalls, 1);
      expect(controller.state.isExporting, isFalse);
    });

    test('creative filter range helper is correct', () {
      expect(isCreativeFilter('vintage'), isTrue);
      expect(isCreativeFilter('brightness'), isFalse);
    });
  });
}
