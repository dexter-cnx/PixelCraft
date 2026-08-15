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

  Future<void> setSurface(
    WidgetTester tester,
    Size size, {
    double devicePixelRatio = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = devicePixelRatio;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> setPhoneSurface(WidgetTester tester) =>
      setSurface(tester, const Size(390, 844));

  Future<void> setTabletSurface(WidgetTester tester) =>
      setSurface(tester, const Size(1180, 820));

  Future<void> tapTool(WidgetTester tester, String label) async {
    final finder = find.text(label);
    expect(finder, findsOneWidget);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  ThemeData lightTheme() => ThemeData(
        useMaterial3: true,
        platform: TargetPlatform.android,
        colorSchemeSeed: const Color(0xFF7259E7),
        scaffoldBackgroundColor: const Color(0xFFF8F7FC),
      );

  ThemeData darkTheme() => ThemeData(
        useMaterial3: true,
        platform: TargetPlatform.android,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF9D8CFF),
      );

  Widget editorHarness(
    FakeImageEngine engine, {
    ThemeMode themeMode = ThemeMode.light,
  }) =>
      ProviderScope(
        overrides: [
          imageEngineProvider.overrideWithValue(engine),
          // Existing full-editor goldens intentionally remain stable and focus
          // on the editor shell/tool states. Zoom has dedicated widget coverage.
          editorZoomControlsVisibleProvider.overrideWithValue(false),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: lightTheme(),
          darkTheme: darkTheme(),
          themeMode: themeMode,
          home: EditorScreen(imageBytes: testPngBytes),
        ),
      );

  testWidgets('home screen structural regression - phone', (tester) async {
    await setPhoneSurface(tester);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: lightTheme(),
        home: const HomeScreen(
          recoverLostPickerData: false,
          showGpuDiagnostics: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Dextryx Pixels'), findsOneWidget);
    expect(find.text('Edit locally. Move fast.'), findsOneWidget);
    expect(find.text('Add Photo'), findsOneWidget);
    expect(find.byTooltip('Films'), findsOneWidget);
    expect(find.byTooltip('GPU Diagnostics'), findsNothing);
    for (final sample in const [
      'sample_1.png',
      'sample_2.png',
      'sample_3.png',
      'sample_4.png',
    ]) {
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Hero && widget.tag == sample,
        ),
        findsOneWidget,
      );
    }
    expect(find.byType(FloatingActionButton), findsOneWidget);
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

  testWidgets('editor screen golden - tablet', (tester) async {
    await setTabletSurface(tester);
    await tester.pumpWidget(editorHarness(FakeImageEngine()));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/editor_tablet.png'),
    );
  });

  testWidgets('editor screen golden - dark phone', (tester) async {
    await setPhoneSurface(tester);
    TestWidgetsFlutterBinding.instance.platformDispatcher
        .platformBrightnessTestValue = Brightness.dark;
    await tester.pumpWidget(
      editorHarness(FakeImageEngine(), themeMode: ThemeMode.dark),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/editor_dark_phone.png'),
    );
  });

  testWidgets('editor screen golden - accessibility text scale', (tester) async {
    await setPhoneSurface(tester);
    TestWidgetsFlutterBinding.instance.platformDispatcher
        .textScaleFactorTestValue = 1.5;
    await tester.pumpWidget(editorHarness(FakeImageEngine()));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/editor_accessibility_phone.png'),
    );
  });

  testWidgets('film profiles golden - phone', (tester) async {
    await setPhoneSurface(tester);
    await tester.pumpWidget(editorHarness(FakeImageEngine()));
    await tester.pumpAndSettle();

    await tapTool(tester, 'Film');

    expect(find.text('Provia Inspired'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/editor_film_phone.png'),
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
    await tester.pump(const Duration(milliseconds: 550));

    expect(find.text('Before'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/editor_before_phone.png'),
    );
    await gesture.up();
  });
}
