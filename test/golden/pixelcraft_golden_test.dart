import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcraft/state/editor_controller.dart';
import 'package:pixelcraft/ui/screens/editor_screen.dart';
import 'package:pixelcraft/ui/screens/home_screen.dart';
import 'package:pixelcraft/ui/widgets/image_preview.dart';

import '../helpers/fake_image_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    final binding = TestWidgetsFlutterBinding.instance;
    binding.platformDispatcher.textScaleFactorTestValue = 1.0;
    binding.platformDispatcher.platformBrightnessTestValue = Brightness.light;
  });

  tearDown(() {
    final binding = TestWidgetsFlutterBinding.instance;
    binding.platformDispatcher.clearTextScaleFactorTestValue();
    binding.platformDispatcher.clearPlatformBrightnessTestValue();
  });

  Future<void> setPhoneSurface(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget editorHarness(FakeImageEngine engine) => ProviderScope(
        overrides: [imageEngineProvider.overrideWithValue(engine)],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            colorSchemeSeed: const Color(0xFF7259E7),
            scaffoldBackgroundColor: const Color(0xFFF8F7FC),
          ),
          home: EditorScreen(imageBytes: testPngBytes),
        ),
      );

  testWidgets('home screen golden - phone', (tester) async {
    await setPhoneSurface(tester);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: const Color(0xFF7259E7),
          scaffoldBackgroundColor: const Color(0xFFF8F7FC),
        ),
        home: const HomeScreen(),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/home_phone.png'),
    );
  });

  testWidgets('editor screen golden - phone', (tester) async {
    await setPhoneSurface(tester);
    await tester.pumpWidget(editorHarness(FakeImageEngine()));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/editor_phone.png'),
    );
  });

  testWidgets('export dialog golden - phone', (tester) async {
    await setPhoneSurface(tester);
    await tester.pumpWidget(editorHarness(FakeImageEngine()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Export'));
    await tester.pumpAndSettle();

    expect(find.text('Export full resolution'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/export_dialog_phone.png'),
    );
  });

  testWidgets('before comparison golden - phone', (tester) async {
    await setPhoneSurface(tester);
    await tester.pumpWidget(editorHarness(FakeImageEngine()));
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ImagePreview)),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));

    expect(find.text('Original'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/editor_before_phone.png'),
    );
    await gesture.up();
  });
}
