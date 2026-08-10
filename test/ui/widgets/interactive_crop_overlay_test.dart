import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcraft/ui/widgets/interactive_crop_overlay.dart';

void main() {
  group('CropDraft.centeredForAspect', () {
    test('creates a centered 1:1 crop', () {
      final draft = CropDraft.centeredForAspect(1);

      expect(draft.x, closeTo(0, 1e-9));
      expect(draft.y, closeTo(0, 1e-9));
      expect(draft.width, closeTo(1, 1e-9));
      expect(draft.height, closeTo(1, 1e-9));
      expect(draft.aspectRatio, 1);
    });

    test('creates a centered landscape crop', () {
      final draft = CropDraft.centeredForAspect(16 / 9);

      expect(draft.x, closeTo(0, 1e-9));
      expect(draft.y, closeTo((1 - 9 / 16) / 2, 1e-9));
      expect(draft.width, closeTo(1, 1e-9));
      expect(draft.height, closeTo(9 / 16, 1e-9));
    });

    test('creates a centered portrait crop', () {
      final draft = CropDraft.centeredForAspect(9 / 16);

      expect(draft.x, closeTo((1 - 9 / 16) / 2, 1e-9));
      expect(draft.y, closeTo(0, 1e-9));
      expect(draft.width, closeTo(9 / 16, 1e-9));
      expect(draft.height, closeTo(1, 1e-9));
    });
  });

  testWidgets('dragging the crop frame updates normalized coordinates', (tester) async {
    var draft = const CropDraft(x: 0.2, y: 0.2, width: 0.5, height: 0.5);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox.square(
              dimension: 300,
              child: StatefulBuilder(
                builder: (context, setState) => InteractiveCropOverlay(
                  draft: draft,
                  onChanged: (value) {
                    draft = value;
                    setState(() {});
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final overlay = find.byType(InteractiveCropOverlay);
    final origin = tester.getTopLeft(overlay);
    final cropCenter = origin + const Offset(0.45 * 300, 0.45 * 300);

    await tester.dragFrom(cropCenter, const Offset(30, 15));
    await tester.pump();

    expect(draft.x, closeTo(0.30, 0.02));
    expect(draft.y, closeTo(0.25, 0.02));
    expect(draft.width, closeTo(0.5, 1e-6));
    expect(draft.height, closeTo(0.5, 1e-6));
    expect(draft.x + draft.width, lessThanOrEqualTo(1));
    expect(draft.y + draft.height, lessThanOrEqualTo(1));
  });

  testWidgets('moving a crop frame clamps it to image bounds', (tester) async {
    var draft = const CropDraft(x: 0.4, y: 0.4, width: 0.5, height: 0.5);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox.square(
            dimension: 300,
            child: StatefulBuilder(
              builder: (context, setState) => InteractiveCropOverlay(
                draft: draft,
                onChanged: (value) {
                  draft = value;
                  setState(() {});
                },
              ),
            ),
          ),
        ),
      ),
    );

    await tester.dragFrom(const Offset(195, 195), const Offset(500, 500));
    await tester.pump();

    expect(draft.x, closeTo(0.5, 1e-6));
    expect(draft.y, closeTo(0.5, 1e-6));
    expect(draft.x + draft.width, closeTo(1, 1e-6));
    expect(draft.y + draft.height, closeTo(1, 1e-6));
  });
}
