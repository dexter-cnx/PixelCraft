import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const gpuFramePacingChannelName = 'dev.pixelcraft/gpu_frame_pacing_v1';

@immutable
class GpuFramePacingSnapshot {
  const GpuFramePacingSnapshot({
    required this.active,
    required this.elapsedSeconds,
    required this.frameCount,
    required this.fps,
    required this.averageFrameMs,
    required this.p95FrameMs,
    required this.p99FrameMs,
    required this.maxFrameMs,
    required this.over40MsFrames,
    required this.source,
  });

  final bool active;
  final double elapsedSeconds;
  final int frameCount;
  final double fps;
  final double averageFrameMs;
  final double p95FrameMs;
  final double p99FrameMs;
  final double maxFrameMs;
  final int over40MsFrames;
  final String source;

  bool get meetsG1Target =>
      elapsedSeconds >= 10 && fps >= 30 && p95FrameMs <= 40;

  factory GpuFramePacingSnapshot.fromMap(Map<Object?, Object?> map) =>
      GpuFramePacingSnapshot(
        active: map['active'] as bool? ?? false,
        elapsedSeconds: (map['elapsedSeconds'] as num? ?? 0).toDouble(),
        frameCount: map['frameCount'] as int? ?? 0,
        fps: (map['fps'] as num? ?? 0).toDouble(),
        averageFrameMs: (map['averageFrameMs'] as num? ?? 0).toDouble(),
        p95FrameMs: (map['p95FrameMs'] as num? ?? 0).toDouble(),
        p99FrameMs: (map['p99FrameMs'] as num? ?? 0).toDouble(),
        maxFrameMs: (map['maxFrameMs'] as num? ?? 0).toDouble(),
        over40MsFrames: map['over40MsFrames'] as int? ?? 0,
        source: map['source'] as String? ?? '',
      );
}

class GpuFramePacingBridge {
  const GpuFramePacingBridge({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(gpuFramePacingChannelName);

  final MethodChannel _channel;

  Future<void> start(String rendererId) => _channel.invokeMethod<void>(
        'start',
        <String, Object?>{'rendererId': rendererId},
      );

  Future<GpuFramePacingSnapshot> snapshot(String rendererId) async {
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'snapshot',
      <String, Object?>{'rendererId': rendererId},
    );
    if (result == null) {
      throw StateError('GPU frame pacing snapshot returned no data');
    }
    return GpuFramePacingSnapshot.fromMap(result);
  }

  Future<GpuFramePacingSnapshot> stop(String rendererId) async {
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'stop',
      <String, Object?>{'rendererId': rendererId},
    );
    if (result == null) {
      throw StateError('GPU frame pacing stop returned no data');
    }
    return GpuFramePacingSnapshot.fromMap(result);
  }
}
