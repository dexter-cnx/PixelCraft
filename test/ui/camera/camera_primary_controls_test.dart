import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcraft/ui/camera/camera_primary_controls.dart';

void main() {
  testWidgets('renders Gallery / Shutter / Controls hierarchy', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Align(
            alignment: Alignment.bottomCenter,
            child: CameraPrimaryControls(
              selectedTool: CameraPrimaryTool.film,
              onToolSelected: (_) {},
              onGalleryPressed: () {},
              onShutterPressed: () {},
              onControlsPressed: () {},
              galleryLabel: 'Gallery',
              filmLabel: 'Film',
              filterLabel: 'Filter',
              adjustLabel: 'Adjust',
              controlsLabel: 'Controls',
              shutterSemanticLabel: 'Take photo',
            ),
          ),
        ),
      ),
    );

    expect(find.text('Gallery'), findsOneWidget);
    expect(find.text('Controls'), findsOneWidget);
    expect(find.text('Film'), findsOneWidget);
    expect(find.text('Filter'), findsOneWidget);
    expect(find.text('Adjust'), findsOneWidget);
    expect(find.byKey(const Key('camera-shutter')), findsOneWidget);
    expect(find.bySemanticsLabel('Take photo'), findsOneWidget);
  });

  testWidgets('dispatches tool and primary action callbacks', (tester) async {
    CameraPrimaryTool? selected;
    var galleryPressed = false;
    var shutterPressed = false;
    var controlsPressed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Align(
            alignment: Alignment.bottomCenter,
            child: CameraPrimaryControls(
              selectedTool: CameraPrimaryTool.film,
              onToolSelected: (value) => selected = value,
              onGalleryPressed: () => galleryPressed = true,
              onShutterPressed: () => shutterPressed = true,
              onControlsPressed: () => controlsPressed = true,
              galleryLabel: 'Gallery',
              filmLabel: 'Film',
              filterLabel: 'Filter',
              adjustLabel: 'Adjust',
              controlsLabel: 'Controls',
              shutterSemanticLabel: 'Take photo',
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Filter'));
    await tester.pump();
    expect(selected, CameraPrimaryTool.filter);

    await tester.tap(find.text('Gallery'));
    await tester.tap(find.byKey(const Key('camera-shutter')));
    await tester.tap(find.text('Controls'));
    expect(galleryPressed, isTrue);
    expect(shutterPressed, isTrue);
    expect(controlsPressed, isTrue);
  });

  testWidgets('disables primary actions while capturing', (tester) async {
    var called = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Align(
            alignment: Alignment.bottomCenter,
            child: CameraPrimaryControls(
              selectedTool: CameraPrimaryTool.film,
              onToolSelected: (_) {},
              onGalleryPressed: () => called = true,
              onShutterPressed: () => called = true,
              onControlsPressed: () => called = true,
              galleryLabel: 'Gallery',
              filmLabel: 'Film',
              filterLabel: 'Filter',
              adjustLabel: 'Adjust',
              controlsLabel: 'Controls',
              shutterSemanticLabel: 'Take photo',
              isCapturing: true,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Gallery'));
    await tester.tap(find.byKey(const Key('camera-shutter')));
    await tester.tap(find.text('Controls'));
    expect(called, isFalse);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
