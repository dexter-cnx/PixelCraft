import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcraft/ui/screens/home_screen.dart';

void main() {
  testWidgets('shows Dextryx Pixels home content and import action', (
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
    expect(find.text('Edit locally. Move fast.'), findsOneWidget);
    expect(find.text('Import'), findsOneWidget);
    expect(find.byTooltip('More ways to add'), findsOneWidget);
    expect(find.byType(Image), findsNWidgets(4));
  });
}
