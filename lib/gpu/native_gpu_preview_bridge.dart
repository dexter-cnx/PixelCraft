import 'package:dxtr_pixs_gpu/native_gpu_preview_bridge.dart' as gpu;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

export 'package:dxtr_pixs_gpu/native_gpu_preview_bridge.dart'
    hide NativeGpuPreviewBridge;

/// Tracks native GPU renderers created through the app bridge and coordinates
/// temporary preview suspension while PF7/PF8 owns the capture handoff UI.
///
/// Suspension is reference-counted and serialized so a fast route disposal
/// cannot race a still-pending pause operation. App lifecycle resume calls are
/// suppressed while suspended; releasing only resumes tracked renderers when
/// the application is actually resumed.
class NativeGpuPreviewSuspension {
  NativeGpuPreviewSuspension._();

  static final Map<String, NativeGpuPreviewBridge> _renderers = {};
  static Future<void> _tail = Future<void>.value();
  static int _depth = 0;

  static bool get isSuspended => _depth > 0;

  static Future<void> acquire() {
    _depth++;
    if (_depth > 1) return _tail;
    return _enqueue(() async {
      for (final entry in List.of(_renderers.entries)) {
        if (_renderers[entry.key] != entry.value) continue;
        try {
          await entry.value._pauseDirect(entry.key);
        } catch (_) {
          // PF9 pause is best-effort. A clean capture already exists and the
          // authoritative shutter transaction must continue even if preview
          // suspension is unavailable.
        }
      }
    });
  }

  static Future<void> release() {
    if (_depth == 0) return _tail;
    _depth--;
    if (_depth > 0) return _tail;
    return _enqueue(() async {
      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        return;
      }
      for (final entry in List.of(_renderers.entries)) {
        if (_renderers[entry.key] != entry.value) continue;
        try {
          await entry.value._resumeDirect(entry.key);
        } catch (_) {
          // The camera screen's existing native runtime-failure handler remains
          // authoritative for renderer failure/fallback. Do not turn release
          // into a second shutter-transaction failure path.
        }
      }
    });
  }

  static void _register(String rendererId, NativeGpuPreviewBridge bridge) {
    _renderers[rendererId] = bridge;
  }

  static void _unregister(String rendererId, NativeGpuPreviewBridge bridge) {
    if (_renderers[rendererId] == bridge) _renderers.remove(rendererId);
  }

  static Future<void> _enqueue(Future<void> Function() task) {
    final next = _tail.then<void>((_) => task(), onError: (_, _) => task());
    _tail = next.then<void>((_) {}, onError: (_, _) {});
    return next;
  }

  @visibleForTesting
  static Future<void> resetForTesting() async {
    await _tail;
    _renderers.clear();
    _depth = 0;
    _tail = Future<void>.value();
  }
}

/// App-level bridge wrapper that preserves the package API while registering
/// renderer identity with [NativeGpuPreviewSuspension].
class NativeGpuPreviewBridge extends gpu.NativeGpuPreviewBridge {
  const NativeGpuPreviewBridge({MethodChannel? channel}) : super(channel: channel);

  @override
  Future<String> createRenderer() async {
    final rendererId = await super.createRenderer();
    NativeGpuPreviewSuspension._register(rendererId, this);
    if (NativeGpuPreviewSuspension.isSuspended) {
      try {
        await _pauseDirect(rendererId);
      } catch (_) {}
    }
    return rendererId;
  }

  @override
  Future<void> pause(String rendererId) => _pauseDirect(rendererId);

  @override
  Future<void> resume(String rendererId) {
    if (NativeGpuPreviewSuspension.isSuspended) return Future<void>.value();
    return _resumeDirect(rendererId);
  }

  @override
  Future<void> destroyRenderer(String rendererId) async {
    try {
      await super.destroyRenderer(rendererId);
    } finally {
      NativeGpuPreviewSuspension._unregister(rendererId, this);
    }
  }

  Future<void> _pauseDirect(String rendererId) => super.pause(rendererId);

  Future<void> _resumeDirect(String rendererId) => super.resume(rendererId);
}
