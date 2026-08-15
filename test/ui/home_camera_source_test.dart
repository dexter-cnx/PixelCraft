import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pixelcraft/ui/screens/home_screen.dart';

void main() {
  Future<XFile?> recordPick(
    List<ImageSource> sources, {
    required ImageSource source,
    required CameraDevice preferredCameraDevice,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    required bool requestFullMetadata,
  }) async {
    sources.add(source);
    return null;
  }

  testWidgets('primary Import opens gallery directly without source menu',
      (tester) async {
    final sources = <ImageSource>[];

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: HomeScreen(
          recoverLostPickerData: false,
          showGpuDiagnostics: false,
          pickImageForTesting: ({
            required source,
            required preferredCameraDevice,
            maxWidth,
            maxHeight,
            imageQuality,
            required requestFullMetadata,
          }) =>
              recordPick(
            sources,
            source: source,
            preferredCameraDevice: preferredCameraDevice,
            maxWidth: maxWidth,
            maxHeight: maxHeight,
            imageQuality: imageQuality,
            requestFullMetadata: requestFullMetadata,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();

    expect(sources, [ImageSource.gallery]);
    expect(find.text('Film Camera'), findsNothing);
    expect(find.text('Take Photo'), findsNothing);
    expect(find.text('Choose from gallery'), findsNothing);
  });

  testWidgets('secondary acquisition exposes Film Camera and system camera',
      (tester) async {
    final sources = <ImageSource>[];

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: HomeScreen(
          recoverLostPickerData: false,
          showGpuDiagnostics: false,
          pickImageForTesting: ({
            required source,
            required preferredCameraDevice,
            maxWidth,
            maxHeight,
            imageQuality,
            required requestFullMetadata,
          }) =>
              recordPick(
            sources,
            source: source,
            preferredCameraDevice: preferredCameraDevice,
            maxWidth: maxWidth,
            maxHeight: maxHeight,
            imageQuality: imageQuality,
            requestFullMetadata: requestFullMetadata,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('More ways to add'));
    await tester.pumpAndSettle();

    expect(find.text('Film Camera'), findsOneWidget);
    expect(find.text('Take Photo'), findsOneWidget);
    expect(find.text('Choose from gallery'), findsNothing);

    await tester.tap(find.text('Take Photo'));
    await tester.pumpAndSettle();

    expect(sources, [ImageSource.camera]);
    expect(find.byTooltip('Films'), findsOneWidget);
  });
}
