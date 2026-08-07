import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcraft/ui/screens/home_screen.dart';

void main() {
  testWidgets('Add Photo offers camera and gallery sources', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: const HomeScreen(recoverLostPickerData: false),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Add Photo'), findsOneWidget);
    await tester.tap(find.text('Add Photo'));
    await tester.pumpAndSettle();

    expect(find.text('Take a photo'), findsOneWidget);
    expect(find.text('Fast capture, optimized for editing'), findsOneWidget);
    expect(find.text('Choose from gallery'), findsOneWidget);
    expect(find.text('Open an existing image on this device'), findsOneWidget);
  });
}
