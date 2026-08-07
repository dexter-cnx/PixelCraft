import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcraft/ui/screens/home_screen.dart';

void main() {
  testWidgets('shows samples and gallery import action', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Pixel Craft'), findsOneWidget);
    expect(find.text('Edit locally. Move fast.'), findsOneWidget);
    expect(find.text('Import from Gallery'), findsOneWidget);
    expect(find.byType(Image), findsNWidgets(4));
  });
}
