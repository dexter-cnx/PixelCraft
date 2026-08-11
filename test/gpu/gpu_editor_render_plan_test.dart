import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcraft/gpu/gpu_editor_render_plan.dart';

void main() {
  String recipe(List<Map<String, Object?>> operations, {int checkpoint = 0}) =>
      jsonEncode(<String, Object?>{
        'version': 1,
        'preview_max_edge': 1280,
        'operations': operations,
        'cursor': operations.length,
        'checkpoint_cursor': checkpoint,
      });

  Map<String, Object?> adjust(String name, double value) =>
      <String, Object?>{'type': 'filter', 'name': name, 'value': value};

  Map<String, Object?> film(String id, double strength) =>
      <String, Object?>{
        'type': 'film_profile',
        'id': id,
        'strength': strength,
      };

  test('composes simultaneous BCS in authoritative order', () {
    final plan = GpuEditorRenderPlan.fromRecipeJson(
      recipe(<Map<String, Object?>>[
        adjust('brightness', 1.20),
        adjust('contrast', 1.30),
        adjust('saturation', 0.85),
      ]),
      transient: const GpuEditorTransientEdit(
        kind: GpuEditorDraftKind.adjust,
        key: 'brightness',
        value: 1.25,
      ),
    );

    expect(plan.isRepresentable, isTrue);
    expect(plan.adjustments.brightness, 1.25);
    expect(plan.adjustments.contrast, 1.30);
    expect(plan.adjustments.saturation, 0.85);
    expect(
      plan.orderedOperations,
      <String>['brightness', 'contrast', 'saturation'],
    );
  });

  test('new transient slot is appended like the Rust draft transaction', () {
    final plan = GpuEditorRenderPlan.fromRecipeJson(
      recipe(<Map<String, Object?>>[
        adjust('brightness', 1.2),
        adjust('contrast', 1.1),
      ]),
      transient: const GpuEditorTransientEdit(
        kind: GpuEditorDraftKind.adjust,
        key: 'saturation',
        value: 0.75,
      ),
    );

    expect(plan.isRepresentable, isTrue);
    expect(
      plan.orderedOperations,
      <String>['brightness', 'contrast', 'saturation'],
    );
  });

  test('fails closed when Adjust order differs from native stage order', () {
    final plan = GpuEditorRenderPlan.fromRecipeJson(
      recipe(<Map<String, Object?>>[
        adjust('contrast', 1.2),
        adjust('brightness', 1.1),
      ]),
    );

    expect(plan.isRepresentable, isFalse);
    expect(plan.fallbackReason, contains('authoritative Rust order'));
  });

  test('supports faithful compute Creative + Adjust + Film composition', () {
    final plan = GpuEditorRenderPlan.fromRecipeJson(
      recipe(<Map<String, Object?>>[
        adjust('grayscale', 0.6),
        adjust('brightness', 1.2),
        adjust('contrast', 1.3),
        film('velvia_inspired', 0.7),
      ]),
    );

    expect(plan.isRepresentable, isTrue);
    expect(plan.creativeFilterId, 'grayscale');
    expect(plan.creativeIntensity, 0.6);
    expect(plan.adjustments.brightness, 1.2);
    expect(plan.adjustments.contrast, 1.3);
    expect(plan.filmProfileId, 'velvia_inspired');
    expect(plan.filmStrength, 0.7);
  });

  test('supports Adjust + canonical Creative LUT when no Film is active', () {
    final plan = GpuEditorRenderPlan.fromRecipeJson(
      recipe(<Map<String, Object?>>[
        adjust('brightness', 1.2),
        adjust('contrast', 1.3),
        adjust('vintage', 0.6),
      ]),
    );

    expect(plan.isRepresentable, isTrue);
    expect(plan.creativeFilterId, 'vintage');
    expect(plan.creativeUsesFilmSlot, isTrue);
    expect(plan.hasFilm, isFalse);
  });

  test('fails closed for Creative LUT + Film native LUT-slot conflict', () {
    final plan = GpuEditorRenderPlan.fromRecipeJson(
      recipe(<Map<String, Object?>>[
        adjust('brightness', 1.2),
        adjust('vintage', 0.6),
        film('velvia_inspired', 0.7),
      ]),
    );

    expect(plan.isRepresentable, isFalse);
    expect(plan.fallbackReason, contains('native LUT slot'));
  });

  test('fails closed for transforms inside active draft', () {
    final plan = GpuEditorRenderPlan.fromRecipeJson(
      recipe(<Map<String, Object?>>[
        adjust('brightness', 1.2),
        <String, Object?>{'type': 'rotate90', 'turns': 1},
      ]),
    );

    expect(plan.isRepresentable, isFalse);
    expect(plan.fallbackReason, contains('unsupported active recipe node'));
  });

  test('uses only operations after checkpoint boundary', () {
    final plan = GpuEditorRenderPlan.fromRecipeJson(
      recipe(
        <Map<String, Object?>>[
          <String, Object?>{'type': 'rotate90', 'turns': 1},
          adjust('brightness', 1.2),
          adjust('contrast', 1.1),
        ],
        checkpoint: 1,
      ),
    );

    expect(plan.isRepresentable, isTrue);
    expect(plan.orderedOperations, <String>['brightness', 'contrast']);
  });

  test('transient Creative replaces existing shared Creative slot in place', () {
    final plan = GpuEditorRenderPlan.fromRecipeJson(
      recipe(<Map<String, Object?>>[
        adjust('grayscale', 0.4),
        adjust('brightness', 1.2),
      ]),
      transient: const GpuEditorTransientEdit(
        kind: GpuEditorDraftKind.creative,
        key: 'invert',
        value: 0.8,
      ),
    );

    expect(plan.isRepresentable, isTrue);
    expect(plan.creativeFilterId, 'invert');
    expect(plan.creativeIntensity, 0.8);
    expect(
      plan.orderedOperations,
      <String>['creative_compute', 'brightness'],
    );
  });
}
