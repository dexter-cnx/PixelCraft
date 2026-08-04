import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcraft/ui/screens/home_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('PixelCraft home screen smoke test', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: const Color(0xFF7259E7),
        ),
        home: const HomeScreen(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('PixelCraft'), findsOneWidget);
    expect(find.text('Edit locally. Move fast.'), findsOneWidget);
    expect(find.text('Import from Gallery'), findsOneWidget);
    expect(find.byType(GridView), findsNothing);
    expect(find.byType(CustomScrollView), findsOneWidget);
  });
}
