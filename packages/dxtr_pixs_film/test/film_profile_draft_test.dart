import 'package:dxtr_pixs_editing/pixelcraft_editing.dart';
import 'package:dxtr_pixs_film/pixelcraft_film.dart';
import 'package:test/test.dart';

void main() {
  test('new draft starts from semantic neutral values', () {
    final draft = FilmProfileDraft();

    for (final spec in filmProfileParameterSpecs) {
      expect(draft.parameterValue(spec.id), spec.neutral);
    }
  });

  test('parameter changes clamp and reset through semantic specs', () {
    final changed = FilmProfileDraft().withParameter('exposure', 99);
    expect(changed.parameterValue('exposure'), 2);

    final reset = changed.resetParameter('exposure');
    expect(reset.parameterValue('exposure'), 0);
  });

  test('profile build trims fields and omits neutral parameters', () {
    final draft = FilmProfileDraft(
      name: '  Warm Day  ',
      description: '  Summer profile  ',
      tags: FilmProfileDraft.parseTags(' portrait, warm, , summer '),
    ).withParameter('contrast', 1.25);

    final profile = draft.toProfile(newId: 'user_1');

    expect(profile.id, 'user_1');
    expect(profile.name, 'Warm Day');
    expect(profile.description, 'Summer profile');
    expect(profile.tags, ['portrait', 'warm', 'summer']);
    expect(profile.parameters['contrast'], 1.25);
    expect(profile.parameters.containsKey('exposure'), isFalse);
  });

  test('editing an existing profile preserves its id', () {
    final source = FilmProfileV1(
      id: 'existing',
      name: 'Existing',
      parameters: const {'grain': 0.4},
    );

    final profile = FilmProfileDraft.fromProfile(source)
        .copyWith(name: 'Edited')
        .toProfile(newId: 'unused');

    expect(profile.id, 'existing');
    expect(profile.name, 'Edited');
    expect(profile.parameters['grain'], 0.4);
  });

  test('unknown parameter ids fail explicitly', () {
    final draft = FilmProfileDraft();
    expect(
      () => draft.withParameter('vendor_magic', 1),
      throwsArgumentError,
    );
  });
}
