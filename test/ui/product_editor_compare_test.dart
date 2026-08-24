import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcraft/state/editor_controller.dart';
import 'package:pixelcraft/ui/screens/product_editor_screen.dart';

import '../helpers/fake_image_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(EasyLocalization.ensureInitialized);

  Widget localizedApp(Widget child) => EasyLocalization(
    supportedLocales: const [Locale('en'), Locale('th')],
    path: 'assets/translations',
    fallbackLocale: const Locale('en'),
    startLocale: const Locale('en'),
    useOnlyLangCode: true,
    child: Builder(
      builder: (context) => MaterialApp(
        locale: context.locale,
        supportedLocales: context.supportedLocales,
        localizationsDelegates: context.localizationDelegates,
        home: child,
      ),
    ),
  );

  testWidgets(
    'Compare button toggles original without changing edit semantics',
    (tester) async {
      final engine = FakeImageEngine();
      final container = ProviderContainer(
        overrides: [imageEngineProvider.overrideWithValue(engine)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: localizedApp(ProductEditorScreen(imageBytes: testPngBytes)),
        ),
      );
      await tester.pumpAndSettle();

      final compareButton = find.byKey(const ValueKey('editor_compare_button'));
      expect(compareButton, findsOneWidget);
      expect(
        find.descendant(of: compareButton, matching: find.text('Before')),
        findsOneWidget,
      );
      expect(container.read(editorProvider).showOriginal, isFalse);
      expect(engine.operations, isEmpty);

      await tester.tap(compareButton);
      await tester.pump();

      expect(container.read(editorProvider).showOriginal, isTrue);
      expect(
        find.descendant(of: compareButton, matching: find.text('Edited')),
        findsOneWidget,
      );
      expect(engine.operations, isEmpty);

      await tester.tap(compareButton);
      await tester.pump();

      expect(container.read(editorProvider).showOriginal, isFalse);
      expect(
        find.descendant(of: compareButton, matching: find.text('Before')),
        findsOneWidget,
      );
      expect(engine.operations, isEmpty);
    },
  );

  testWidgets('new product editor session resets a previous Before state', (
    tester,
  ) async {
    final engine = FakeImageEngine();
    final container = ProviderContainer(
      overrides: [imageEngineProvider.overrideWithValue(engine)],
    );
    addTearDown(container.dispose);

    Widget editor() => UncontrolledProviderScope(
      container: container,
      child: localizedApp(ProductEditorScreen(imageBytes: testPngBytes)),
    );

    await tester.pumpWidget(editor());
    await tester.pumpAndSettle();

    final compareButton = find.byKey(const ValueKey('editor_compare_button'));
    await tester.tap(compareButton);
    await tester.pump();
    expect(container.read(editorProvider).showOriginal, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(container.read(editorProvider).showOriginal, isTrue);

    await tester.pumpWidget(editor());
    await tester.pumpAndSettle();

    expect(container.read(editorProvider).showOriginal, isFalse);
    expect(
      find.descendant(of: compareButton, matching: find.text('Before')),
      findsOneWidget,
    );
  });

  testWidgets('Compare stays over the canvas on wide layouts', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final engine = FakeImageEngine();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [imageEngineProvider.overrideWithValue(engine)],
        child: localizedApp(ProductEditorScreen(imageBytes: testPngBytes)),
      ),
    );
    await tester.pumpAndSettle();

    final compareButton = find.byKey(const ValueKey('editor_compare_button'));
    expect(compareButton, findsOneWidget);

    final rect = tester.getRect(compareButton);
    const canvasRightEdge = 1200.0 - 16.0 - 360.0 - 20.0;
    expect(rect.right, lessThanOrEqualTo(canvasRightEdge - 16.0 + 0.5));
  });
}
