import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcraft/state/editor_controller.dart';

import '../helpers/fake_image_engine.dart';

void main() {
  group('EditorController', () {
    test('loads image, preview and histogram', () async {
      final engine = FakeImageEngine();
      final controller = EditorController(engine);

      await controller.load(Uint8List.fromList([1, 2, 3]));

      expect(engine.loadCalls, 1);
      expect(controller.state.previewBytes, testPngBytes);
      expect(controller.state.histogram.length, 768);
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

    test('uses one begin-preview-commit transaction', () async {
      final engine = FakeImageEngine();
      final controller = EditorController(engine);
      await controller.load(Uint8List.fromList([1]));

      controller.selectFilter('contrast');
      controller.beginAdjustment(1);
      controller.previewValue(1.4);
      controller.commitAdjustment(1.4);

      expect(engine.beginCalls, 1);
      expect(engine.previewCalls, 1);
      expect(engine.commitCalls, 1);
      expect(engine.activeFilter, 'contrast');
      expect(engine.lastValue, 1.4);
      expect(controller.state.processingMs, 12.5);
      expect(controller.state.isAdjusting, isFalse);
    });

    test('undo and redo refresh histogram', () async {
      final engine = FakeImageEngine();
      final controller = EditorController(engine);
      await controller.load(Uint8List.fromList([1]));

      controller.undo();
      controller.redo();

      expect(engine.undoCalls, 1);
      expect(engine.redoCalls, 1);
      expect(controller.state.histogram, engine.bins);
    });

    test('creative filter range helper is correct', () {
      expect(isCreativeFilter('vintage'), isTrue);
      expect(isCreativeFilter('brightness'), isFalse);
    });
  });
}
