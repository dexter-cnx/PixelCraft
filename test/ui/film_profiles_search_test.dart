import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcraft/core/film_profile_v1.dart';
import 'package:pixelcraft/ui/screens/film_profiles_screen.dart';
import 'package:pixelcraft_film/pixelcraft_film.dart';

class _MemoryFilmProfileRepository implements FilmProfileRepository {
  _MemoryFilmProfileRepository(this._profiles);

  final List<FilmProfileV1> _profiles;

  @override
  Future<List<FilmProfileV1>> loadAll() async => List.unmodifiable(_profiles);

  @override
  Future<void> save(FilmProfileV1 profile) async {
    final index = _profiles.indexWhere((item) => item.id == profile.id);
    if (index >= 0) {
      _profiles[index] = profile;
    } else {
      _profiles.add(profile);
    }
  }

  @override
  Future<void> delete(String id) async {
    _profiles.removeWhere((profile) => profile.id == id);
  }
}

void main() {
  testWidgets('Film library searches metadata and filters imported profiles',
      (tester) async {
    final repository = _MemoryFilmProfileRepository([
      FilmProfileV1(
        id: 'portrait_soft',
        name: 'Portrait Soft',
        description: 'Gentle skin tones',
        tags: const ['portrait'],
      ),
      FilmProfileV1(
        id: 'travel_chrome',
        name: 'Travel Chrome',
        description: 'Imported recipe for trips',
        origin: FilmProfileOrigin.imported,
        tags: const ['travel'],
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: FilmProfilesScreen(
          library: FilmProfileLibrary(repository),
        ),
      ),
    );
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
