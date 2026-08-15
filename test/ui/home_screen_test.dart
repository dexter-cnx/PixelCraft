import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcraft/ui/screens/home_screen.dart';

void main() {
  testWidgets('shows workspace-first home and import action', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: HomeScreen(
          recoverLostPickerData: false,
          showGpuDiagnostics: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Dextryx Pixels'), findsOneWidget);
    expect(find.text('Your workspace is empty'), findsOneWidget);
    expect(find.text('Import a photo to start editing.'), findsOneWidget);
    expect(find.text('Import'), findsOneWidget);
    expect(find.byTooltip('More ways to add'), findsOneWidget);

    expect(find.text('Edit locally. Move fast.'), findsNothing);
    expect(find.textContaining('Rust-powered'), findsNothing);
    expect(find.byType(Image), findsNothing);
  });
}
