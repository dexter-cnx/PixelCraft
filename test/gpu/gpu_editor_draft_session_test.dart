import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcraft/gpu/gpu_editor_draft_session.dart';
import 'package:pixelcraft/gpu/gpu_editor_render_plan.dart';

void main() {
  String recipe() => jsonEncode(<String, Object?>{
        'version': 1,
        'preview_max_edge': 1280,
        'operations': <Object?>[
          <String, Object?>{
            'type': 'filter',
            'name': 'brightness',
            'value': 1.2,
          },
        ],
        'cursor': 1,
        'checkpoint_cursor': 0,
      });

  const edit = GpuEditorTransientEdit(
    kind: GpuEditorDraftKind.adjust,
    key: 'brightness',
    value: 1.25,
  );

  test('new activation supersedes stale async work', () {
    final session = GpuEditorDraftSession();
    final first = session.begin(edit);
    final second = session.begin(edit);

    expect(session.isCurrent(first), isFalse);
    expect(session.isCurrent(second), isTrue);
  });

  test('checkpoint invalidation advances checkpoint and activation generations', () {
    final session = GpuEditorDraftSession();
    final token = session.begin(edit);
    final before = session.snapshot;

    session.invalidate(
      checkpointChanged: true,
      reason: 'Rust checkpoint changed',
    );

    final after = session.snapshot;
    expect(session.isCurrent(token), isFalse);
    expect(after.checkpointGeneration, before.checkpointGeneration + 1);
    expect(after.activationGeneration, before.activationGeneration + 1);
    expect(after.status, GpuEditorPresentationStatus.fallback);
  });

  test('dropping renderer advances renderer generation exactly once', () {
    final session = GpuEditorDraftSession();
    final before = session.rendererGeneration;

    session.invalidate(dropRenderer: true, reason: 'background');

    expect(session.rendererGeneration, before + 1);
  });

  test('representable plan can transition preparing to active to idle', () {
    final session = GpuEditorDraftSession();
    final token = session.begin(edit);
    final json = recipe();
    final plan = GpuEditorRenderPlan.fromRecipeJson(json, transient: edit);

    expect(
      session.prepare(token, recipeJson: json, plan: plan),
      isTrue,
    );
    expect(session.activate(token), isTrue);
    expect(session.snapshot.isActive, isTrue);

    session.finish(token);
    expect(session.snapshot.status, GpuEditorPresentationStatus.idle);
    expect(session.plan, isNull);
  });

  test('unrepresentable plan enters deterministic fallback', () {
    final session = GpuEditorDraftSession();
    final token = session.begin(edit);
    final bad = jsonEncode(<String, Object?>{
      'version': 1,
      'preview_max_edge': 1280,
      'operations': <Object?>[
        <String, Object?>{'type': 'rotate90', 'turns': 1},
      ],
      'cursor': 1,
      'checkpoint_cursor': 0,
    });
    final plan = GpuEditorRenderPlan.fromRecipeJson(bad, transient: edit);

    expect(session.prepare(token, recipeJson: bad, plan: plan), isFalse);
    expect(session.snapshot.status, GpuEditorPresentationStatus.fallback);
    expect(session.snapshot.fallbackReason, isNotEmpty);
  });
}
