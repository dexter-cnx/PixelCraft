import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const gpuFramePacingChannelName = 'dev.pixelcraft/gpu_frame_pacing_v1';

@immutable
class GpuColorCharacterizationSample {
  const GpuColorCharacterizationSample({
    required this.profileId,
    required this.strength,
    required this.filmEnabled,
    required this.samples,
    required this.sourceMeanRgb,
    required this.filmMeanRgb,
    required this.roi,
    required this.pixelFormat,
  });

  final String profileId;
  final double strength;
  final bool filmEnabled;
  final int samples;
  final List<double> sourceMeanRgb;
  final List<double> filmMeanRgb;
  final String roi;
  final String pixelFormat;

  factory GpuColorCharacterizationSample.fromMap(Map<Object?, Object?> map) =>
      GpuColorCharacterizationSample(
        profileId: map['profileId'] as String? ?? '',
        strength: (map['strength'] as num? ?? 0).toDouble(),
        filmEnabled: map['filmEnabled'] as bool? ?? false,
        samples: map['samples'] as int? ?? 0,
        sourceMeanRgb: _rgb(map['sourceMeanRgb']),
        filmMeanRgb: _rgb(map['filmMeanRgb']),
        roi: map['roi'] as String? ?? '',
        pixelFormat: map['pixelFormat'] as String? ?? '',
      );

  static List<double> _rgb(Object? value) {
    if (value is! List || value.length != 3) return const [0, 0, 0];
    return value.map((item) => (item as num? ?? 0).toDouble()).toList(
          growable: false,
        );
  }
}

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
    required this.captureFrameCount,
    required this.captureFps,
    required this.averageCaptureMs,
    required this.p95CaptureMs,
    required this.overwrittenCaptureFrames,
    required this.droppedCaptureFrames,
    required this.commandCompletionCount,
    required this.uniqueRenderedFrames,
    required this.uniqueRenderedFps,
    required this.averageCommandCompletionMs,
    required this.p95CommandCompletionMs,
    required this.p99CommandCompletionMs,
    required this.maxCommandCompletionMs,
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
  final int captureFrameCount;
  final double captureFps;
  final double averageCaptureMs;
  final double p95CaptureMs;
  final int overwrittenCaptureFrames;
  final int droppedCaptureFrames;
  final int commandCompletionCount;
  final int uniqueRenderedFrames;
  final double uniqueRenderedFps;
  final double averageCommandCompletionMs;
  final double p95CommandCompletionMs;
  final double p99CommandCompletionMs;
  final double maxCommandCompletionMs;
  final String source;

  bool get meetsG1Target =>
      elapsedSeconds >= 10 && fps >= 30 && p95FrameMs <= 40;

  bool get meetsPipelineTarget {
    if (elapsedSeconds < 10 || captureFrameCount == 0) return false;
    final loss = overwrittenCaptureFrames + droppedCaptureFrames;
    final lossRate = loss / captureFrameCount;
    return captureFps >= 24 &&
        uniqueRenderedFps >= 24 &&
        lossRate <= 0.02 &&
        p95CommandCompletionMs <= 16;
  }

  double get captureLossRate {
    if (captureFrameCount == 0) return 0;
    return (overwrittenCaptureFrames + droppedCaptureFrames) /
        captureFrameCount;
  }

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
        captureFrameCount: map['captureFrameCount'] as int? ?? 0,
        captureFps: (map['captureFps'] as num? ?? 0).toDouble(),
        averageCaptureMs: (map['averageCaptureMs'] as num? ?? 0).toDouble(),
        p95CaptureMs: (map['p95CaptureMs'] as num? ?? 0).toDouble(),
        overwrittenCaptureFrames:
            map['overwrittenCaptureFrames'] as int? ?? 0,
        droppedCaptureFrames: map['droppedCaptureFrames'] as int? ?? 0,
        commandCompletionCount: map['commandCompletionCount'] as int? ?? 0,
        uniqueRenderedFrames: map['uniqueRenderedFrames'] as int? ?? 0,
        uniqueRenderedFps:
            (map['uniqueRenderedFps'] as num? ?? 0).toDouble(),
        averageCommandCompletionMs:
            (map['averageCommandCompletionMs'] as num? ?? 0).toDouble(),
        p95CommandCompletionMs:
            (map['p95CommandCompletionMs'] as num? ?? 0).toDouble(),
        p99CommandCompletionMs:
            (map['p99CommandCompletionMs'] as num? ?? 0).toDouble(),
        maxCommandCompletionMs:
            (map['maxCommandCompletionMs'] as num? ?? 0).toDouble(),
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

  Future<GpuColorCharacterizationSample> colorSample(
    String rendererId, {
    int maxSamples = 4096,
  }) async {
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'colorSample',
      <String, Object?>{
        'rendererId': rendererId,
        'maxSamples': maxSamples,
      },
    );
    if (result == null) {
      throw StateError('GPU color characterization returned no data');
    }
    return GpuColorCharacterizationSample.fromMap(result);
  }
}
