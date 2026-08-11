import 'package:flutter/foundation.dart';

import 'gpu_editor_render_plan.dart';

enum GpuEditorPresentationStatus {
  idle,
  preparing,
  active,
  fallback,
}

@immutable
class GpuEditorDraftSnapshot {
  const GpuEditorDraftSnapshot({
    required this.checkpointGeneration,
    required this.rendererGeneration,
    required this.activationGeneration,
    required this.status,
    this.transient,
    this.plan,
    this.fallbackReason,
  });

  final int checkpointGeneration;
  final int rendererGeneration;
  final int activationGeneration;
  final GpuEditorPresentationStatus status;
  final GpuEditorTransientEdit? transient;
  final GpuEditorRenderPlan? plan;
  final String? fallbackReason;

  bool get isActive => status == GpuEditorPresentationStatus.active;
}

/// Presentation-only state machine for the editor GPU draft.
///
/// It intentionally does not own semantic edit state. Recipe/order data always
/// originates from Rust and is held only for the lifetime of one activation.
class GpuEditorDraftSession {
  int _checkpointGeneration = 0;
  int _rendererGeneration = 0;
  int _activationGeneration = 0;
  GpuEditorPresentationStatus _status = GpuEditorPresentationStatus.idle;
  GpuEditorTransientEdit? _transient;
  String? _recipeJson;
  GpuEditorRenderPlan? _plan;
  String? _fallbackReason;

  int get rendererGeneration => _rendererGeneration;
  int get activationGeneration => _activationGeneration;
  bool get isActive => _status == GpuEditorPresentationStatus.active;
  GpuEditorTransientEdit? get transient => _transient;
  String? get recipeJson => _recipeJson;
  GpuEditorRenderPlan? get plan => _plan;

  GpuEditorDraftSnapshot get snapshot => GpuEditorDraftSnapshot(
        checkpointGeneration: _checkpointGeneration,
        rendererGeneration: _rendererGeneration,
        activationGeneration: _activationGeneration,
        status: _status,
        transient: _transient,
        plan: _plan,
        fallbackReason: _fallbackReason,
      );

  int begin(GpuEditorTransientEdit transient) {
    _activationGeneration++;
    _transient = transient;
    _recipeJson = null;
    _plan = null;
    _fallbackReason = null;
    _status = GpuEditorPresentationStatus.preparing;
    return _activationGeneration;
  }

  bool isCurrent(int generation) => generation == _activationGeneration;

  void updateTransient(GpuEditorTransientEdit transient) {
    if (_transient == null) return;
    _transient = transient;
  }

  bool prepare(
    int generation, {
    required String recipeJson,
    required GpuEditorRenderPlan plan,
  }) {
    if (!isCurrent(generation)) return false;
    if (!plan.isRepresentable) {
      fallback(
        generation,
        plan.fallbackReason ?? 'GPU render plan is not representable',
      );
      return false;
    }
    _recipeJson = recipeJson;
    _plan = plan;
    _fallbackReason = null;
    _status = GpuEditorPresentationStatus.preparing;
    return true;
  }

  bool activate(int generation) {
    if (!isCurrent(generation) || _plan == null) return false;
    _status = GpuEditorPresentationStatus.active;
    return true;
  }

  void fallback(int generation, String reason) {
    if (!isCurrent(generation)) return;
    _status = GpuEditorPresentationStatus.fallback;
    _fallbackReason = reason;
    _recipeJson = null;
    _plan = null;
    _transient = null;
  }

  void finish(int generation) {
    if (!isCurrent(generation)) return;
    _status = GpuEditorPresentationStatus.idle;
    _transient = null;
    _recipeJson = null;
    _plan = null;
    _fallbackReason = null;
  }

  void invalidate({
    bool checkpointChanged = false,
    bool dropRenderer = false,
    String? reason,
  }) {
    _activationGeneration++;
    if (checkpointChanged) _checkpointGeneration++;
    if (dropRenderer) _rendererGeneration++;
    _status = reason == null
        ? GpuEditorPresentationStatus.idle
        : GpuEditorPresentationStatus.fallback;
    _fallbackReason = reason;
    _transient = null;
    _recipeJson = null;
    _plan = null;
  }
}
