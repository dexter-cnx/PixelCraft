import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcraft/core/film_profile_store.dart';
import 'package:pixelcraft/core/film_profile_v1.dart';
import 'package:pixelcraft/ui/screens/film_profiles_screen.dart';

void main() {
  testWidgets('Film library searches metadata and filters imported profiles',
      (tester) async {
    final directory =
        await Directory.systemTemp.createTemp('pixelcraft-film-ui-');
    addTearDown(() => directory.delete(recursive: true));
    final store = FilmProfileStore(directoryProvider: () async => directory);

    await store.save(
      FilmProfileV1(
        id: 'portrait_soft',
        name: 'Portrait Soft',
        description: 'Gentle skin tones',
        tags: const ['portrait'],
      ),
    );
    await store.save(
      FilmProfileV1(
        id: 'travel_chrome',
        name: 'Travel Chrome',
        description: 'Imported recipe for trips',
        origin: FilmProfileOrigin.imported,
        tags: const ['travel'],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(home: FilmProfilesScreen(store: store)),
    );

    // The screen starts with an indeterminate CircularProgressIndicator while
    // FilmProfileStore performs real async file I/O. pumpAndSettle() cannot be
    // used here because the spinner continuously schedules frames and can keep
    // the test harness alive indefinitely. Yield to the real event loop so the
    // store load can finish, then render the completed state once.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();

    expect(find.text('Portrait Soft'), findsOneWidget);
    expect(find.text('Travel Chrome'), findsOneWidget);

    final search = find.byKey(const ValueKey('film_profile_search'));
    await tester.enterText(search, 'skin');
    await tester.pump();

    expect(find.text('Portrait Soft'), findsOneWidget);
    expect(find.text('Travel Chrome'), findsNothing);

    await tester.enterText(search, '');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('film_origin_imported')));
    await tester.pump();

    expect(find.text('Portrait Soft'), findsNothing);
    expect(find.text('Travel Chrome'), findsOneWidget);
  });
}
