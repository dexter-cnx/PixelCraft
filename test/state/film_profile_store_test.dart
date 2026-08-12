import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcraft/core/film_profile_store.dart';
import 'package:pixelcraft/core/film_profile_v1.dart';

void main() {
  late Directory temp;
  late FilmProfileStore store;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pixelcraft-profile-test-');
    store = FilmProfileStore(directoryProvider: () async => temp);
  });

  tearDown(() async {
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  test('save load update and delete user profile', () async {
    final profile = FilmProfileV1(
      id: 'one',
      name: 'One',
      parameters: const {'exposure': 0.4},
    );

    await store.save(profile);
    var profiles = await store.loadAll();
    expect(profiles, hasLength(1));
    expect(profiles.single.parameters['exposure'], 0.4);

    await store.save(profile.copyWith(name: 'Updated'));
    profiles = await store.loadAll();
    expect(profiles, hasLength(1));
    expect(profiles.single.name, 'Updated');

    await store.delete('one');
    expect(await store.loadAll(), isEmpty);
  });

  test('built-in profile is immutable in user store', () async {
    final profile = FilmProfileV1(
      id: 'builtin',
      name: 'Built In',
      origin: FilmProfileOrigin.builtIn,
    );

    expect(() => store.save(profile), throwsA(isA<StateError>()));
  });

  test('corrupt stored entries fail closed without losing valid profiles', () async {
    final folder = Directory('${temp.path}/pixelcraft_profiles');
    await folder.create(recursive: true);
    final file = File('${folder.path}/profiles_v1.json');
    await file.writeAsString('''[
      {"schema":"pixelcraft-film-profile","schemaVersion":1,"minEngineVersion":1,"id":"ok","name":"Okay","origin":"user","baseFilmId":"","baseStrength":1,"parameters":{},"tags":[]},
      {"broken":true}
    ]''');

    final profiles = await store.loadAll();
    expect(profiles, hasLength(1));
    expect(profiles.single.id, 'ok');
  });
}
