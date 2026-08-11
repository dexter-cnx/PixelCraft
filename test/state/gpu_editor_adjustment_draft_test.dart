import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcraft/gpu/gpu_editor_adjustment_draft.dart';

void main() {
  group('GpuEditorAdjustmentDraft', () {
    test('composes all active adjustment slots and overrides dragged value', () {
      final draft = GpuEditorAdjustmentDraft.fromRecipeJson(
        '''
        {
          "operations": [
            {"type":"filter","name":"brightness","value":1.20},
            {"type":"filter","name":"contrast","value":1.30},
            {"type":"filter","name":"saturation","value":0.85}
          ],
          "cursor": 3,
          "checkpoint_cursor": 0
        }
        ''',
        transientKey: 'brightness',
        transientValue: 1.25,
      );

      expect(draft.isRepresentable, isTrue);
      expect(
        draft.orderedKeys,
        ['brightness', 'contrast', 'saturation'],
      );
      expect(draft.adjustments.brightness, 1.25);
      expect(draft.adjustments.contrast, 1.30);
      expect(draft.adjustments.saturation, 0.85);
      expect(draft.adjustments.sharpen, 0);
      expect(draft.adjustments.gaussianBlur, 0);
    });

    test('composes sharpen and gaussian blur simultaneously', () {
      final draft = GpuEditorAdjustmentDraft.fromRecipeJson(
        '''
        {
          "operations": [
            {"type":"filter","name":"sharpen","value":1.5},
            {"type":"filter","name":"gaussian_blur","value":2.0}
          ],
          "cursor": 2,
          "checkpoint_cursor": 0
        }
        ''',
      );

      expect(draft.isRepresentable, isTrue);
      expect(draft.adjustments.sharpen, 1.5);
      expect(draft.adjustments.gaussianBlur, 2.0);
      expect(draft.orderedKeys, ['sharpen', 'gaussian_blur']);
    });

    test('only reads active operations after checkpoint', () {
      final draft = GpuEditorAdjustmentDraft.fromRecipeJson(
        '''
        {
          "operations": [
            {"type":"filter","name":"brightness","value":1.4},
            {"type":"filter","name":"contrast","value":0.8}
          ],
          "cursor": 2,
          "checkpoint_cursor": 1
        }
        ''',
      );

      expect(draft.isRepresentable, isTrue);
      expect(draft.adjustments.brightness, 1);
      expect(draft.adjustments.contrast, 0.8);
      expect(draft.orderedKeys, ['contrast']);
    });

    test('fails closed when creative state is active', () {
      final draft = GpuEditorAdjustmentDraft.fromRecipeJson(
        '''
        {
          "operations": [
            {"type":"filter","name":"brightness","value":1.2},
            {"type":"filter","name":"vintage","value":0.6}
          ],
          "cursor": 2,
          "checkpoint_cursor": 0
        }
        ''',
        transientKey: 'brightness',
        transientValue: 1.25,
      );

      expect(draft.isRepresentable, isFalse);
      expect(draft.fallbackReason, contains('unsupported active filter'));
    });

    test('fails closed when transform state is active', () {
      final draft = GpuEditorAdjustmentDraft.fromRecipeJson(
        '''
        {
          "operations": [
            {"type":"filter","name":"brightness","value":1.2},
            {"type":"rotate_degrees","degrees":2.5}
          ],
          "cursor": 2,
          "checkpoint_cursor": 0
        }
        ''',
      );

      expect(draft.isRepresentable, isFalse);
      expect(draft.fallbackReason, contains('unsupported active node'));
    });

    test('fails closed for malformed recipe', () {
      final draft = GpuEditorAdjustmentDraft.fromRecipeJson('{bad json');

      expect(draft.isRepresentable, isFalse);
      expect(draft.fallbackReason, 'invalid recipe json');
    });
  });
}
