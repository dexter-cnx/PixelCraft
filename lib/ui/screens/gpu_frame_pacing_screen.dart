import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../gpu/gpu_frame_pacing_bridge.dart';
import '../../gpu/gpu_preview_renderer.dart';
import '../../gpu/ios_gpu_camera_preview.dart';
import '../../gpu/native_gpu_camera_bridge.dart';
import '../../gpu/native_gpu_preview_bridge.dart';

class GpuFramePacingScreen extends StatefulWidget {
  const GpuFramePacingScreen({super.key});

  @override
  State<GpuFramePacingScreen> createState() => _GpuFramePacingScreenState();
}

class _GpuFramePacingScreenState extends State<GpuFramePacingScreen> {
  static const _measurementDuration = Duration(seconds: 60);
  static const _benchmarkProfileId = 'velvia_inspired';
  static const _benchmarkStrength = 1.0;

  final _gpuBridge = const NativeGpuPreviewBridge();
  final _cameraBridge = const NativeGpuCameraBridge();
  final _pacingBridge = const GpuFramePacingBridge();

  String? _rendererId;
  NativeGpuProbe? _probe;
  GpuFramePacingSnapshot? _snapshot;
  Timer? _pollTimer;
  Timer? _stopTimer;
  bool _initializing = true;
  bool _running = false;
  bool _filmBenchmark = true;
  String? _error;

  String get _benchmarkLabel => _filmBenchmark ? 'Velvia 100%' : 'Original';

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _stopTimer?.cancel();
    final rendererId = _rendererId;
    _rendererId = null;
    if (rendererId != null) {
      unawaited(_gpuBridge.destroyRenderer(rendererId));
    }
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
        throw StateError('Frame pacing diagnostics currently targets iOS Metal.');
      }

      final probe = await _gpuBridge.probe(forceSelfTest: true);
      if (probe.backend != GpuPreviewBackendKind.iosMetal || !probe.available) {
        throw StateError('iOS Metal backend is not available on this device.');
      }

      final permission = await _cameraBridge.requestCameraPermission();
      if (!permission) {
        throw StateError(
          'Camera permission is required for live preview measurement.',
        );
      }

      final rendererId = await _gpuBridge.createRenderer();
      await _applyBenchmarkMode(rendererId, filmEnabled: _filmBenchmark);

      if (!mounted) {
        await _gpuBridge.destroyRenderer(rendererId);
        return;
      }
      setState(() {
        _probe = probe;
        _rendererId = rendererId;
        _initializing = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = '$error';
      });
    }
  }

  Future<void> _applyBenchmarkMode(
    String rendererId, {
    required bool filmEnabled,
  }) async {
    if (filmEnabled) {
      await _gpuBridge.setFilm(
        rendererId,
        const GpuPreviewFilmState(
          profileId: _benchmarkProfileId,
          strength: _benchmarkStrength,
        ),
      );
      await _gpuBridge.setEnabled(rendererId, true);
    } else {
      await _gpuBridge.setEnabled(rendererId, false);
    }
  }

  Future<void> _changeBenchmarkMode(bool filmEnabled) async {
    final rendererId = _rendererId;
    if (_running || rendererId == null || filmEnabled == _filmBenchmark) return;

    try {
      await _applyBenchmarkMode(rendererId, filmEnabled: filmEnabled);
      if (!mounted) return;
      setState(() {
        _filmBenchmark = filmEnabled;
        _snapshot = null;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    }
  }

  Future<void> _start() async {
    final rendererId = _rendererId;
    if (_running || rendererId == null) return;

    try {
      await _applyBenchmarkMode(rendererId, filmEnabled: _filmBenchmark);
      await _pacingBridge.start(rendererId);
      if (!mounted) return;
      setState(() {
        _running = true;
        _snapshot = null;
        _error = null;
      });

      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        unawaited(_refreshSnapshot());
      });
      _stopTimer?.cancel();
      _stopTimer = Timer(_measurementDuration, () {
        unawaited(_stop());
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    }
  }

  Future<void> _refreshSnapshot() async {
    final rendererId = _rendererId;
    if (!_running || rendererId == null) return;
    try {
      final snapshot = await _pacingBridge.snapshot(rendererId);
      if (!mounted) return;
      setState(() => _snapshot = snapshot);
    } catch (_) {
      // Keep the measurement running; stop() surfaces the final channel error.
    }
  }

  Future<void> _stop() async {
    final rendererId = _rendererId;
    if (!_running || rendererId == null) return;
    _pollTimer?.cancel();
    _stopTimer?.cancel();

    try {
      final snapshot = await _pacingBridge.stop(rendererId);
      debugPrint(
        '[GPU pipeline] workload=$_benchmarkLabel '
        'displayFps=${snapshot.fps.toStringAsFixed(2)} '
        'displayP95=${snapshot.p95FrameMs.toStringAsFixed(2)}ms '
        'captureFps=${snapshot.captureFps.toStringAsFixed(2)} '
        'captureP95=${snapshot.p95CaptureMs.toStringAsFixed(2)}ms '
        'overwritten=${snapshot.overwrittenCaptureFrames} '
        'avDropped=${snapshot.droppedCaptureFrames} '
        'uniqueFps=${snapshot.uniqueRenderedFps.toStringAsFixed(2)} '
        'metalAvg=${snapshot.averageCommandCompletionMs.toStringAsFixed(2)}ms '
        'metalP95=${snapshot.p95CommandCompletionMs.toStringAsFixed(2)}ms '
        'metalP99=${snapshot.p99CommandCompletionMs.toStringAsFixed(2)}ms '
        'elapsed=${snapshot.elapsedSeconds.toStringAsFixed(1)}s',
      );
      if (!mounted) return;
      setState(() {
        _running = false;
        _snapshot = snapshot;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _error = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    assert(
      kDebugMode,
      'GpuFramePacingScreen is intended for debug builds only.',
    );

    if (_initializing) {
      return Scaffold(
        appBar: AppBar(title: const Text('GPU Pipeline Metrics')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null && _rendererId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('GPU Pipeline Metrics')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_error!, textAlign: TextAlign.center),
          ),
        ),
      );
    }

    final rendererId = _rendererId!;
    final snapshot = _snapshot;

    return Scaffold(
      appBar: AppBar(title: const Text('GPU Pipeline Metrics')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              flex: 3,
              child: ColoredBox(
                color: Colors.black,
                child: IosGpuCameraPreview(rendererId: rendererId),
              ),
            ),
            Expanded(
              flex: 5,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${_probe?.renderer ?? 'iOS Metal'} · $_benchmarkLabel',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        if (_running)
                          Text(
                            '${snapshot?.elapsedSeconds.toStringAsFixed(0) ?? '0'} / 60 s',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment<bool>(
                          value: false,
                          icon: Icon(Icons.hide_image_outlined),
                          label: Text('Original'),
                        ),
                        ButtonSegment<bool>(
                          value: true,
                          icon: Icon(Icons.filter_vintage_outlined),
                          label: Text('Velvia 100%'),
                        ),
                      ],
                      selected: {_filmBenchmark},
                      onSelectionChanged: _running
                          ? null
                          : (selection) {
                              if (selection.isNotEmpty) {
                                unawaited(
                                  _changeBenchmarkMode(selection.first),
                                );
                              }
                            },
                    ),
                    const SizedBox(height: 10),
                    if (snapshot != null)
                      _StatsCard(
                        snapshot: snapshot,
                        workloadLabel: _benchmarkLabel,
                      ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: _running ? _stop : _start,
                      icon: Icon(
                        _running ? Icons.stop_rounded : Icons.speed_rounded,
                      ),
                      label: Text(
                        _running
                            ? 'Stop Measurement'
                            : 'Start 60s $_benchmarkLabel Measurement',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Display target: FPS ≥ 30 and p95 ≤ 40 ms. Pipeline health '
                      'also reports AVCapture unique FPS, pending-frame overwrite, '
                      'AVFoundation drops, unique frames completed by Metal, and '
                      'command-buffer completion latency. No image pixels cross Dart.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({
    required this.snapshot,
    required this.workloadLabel,
  });

  final GpuFramePacingSnapshot snapshot;
  final String workloadLabel;

  @override
  Widget build(BuildContext context) {
    final enoughData = snapshot.elapsedSeconds >= 10;
    final displayPassed = enoughData && snapshot.meetsG1Target;
    final pipelinePassed = enoughData && snapshot.meetsPipelineTarget;

    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            _row('Workload', workloadLabel),
            const Divider(),
            _section(context, 'Display / MTKView'),
            _row('FPS', snapshot.fps.toStringAsFixed(2)),
            _row('Average', '${snapshot.averageFrameMs.toStringAsFixed(2)} ms'),
            _row('p95', '${snapshot.p95FrameMs.toStringAsFixed(2)} ms'),
            _row('p99', '${snapshot.p99FrameMs.toStringAsFixed(2)} ms'),
            _row('Max', '${snapshot.maxFrameMs.toStringAsFixed(2)} ms'),
            _row('> 40 ms', '${snapshot.over40MsFrames} frames'),
            _row('Draw callbacks', '${snapshot.frameCount}'),
            const Divider(),
            _section(context, 'Camera / AVCapture'),
            _row('Capture FPS', snapshot.captureFps.toStringAsFixed(2)),
            _row('Capture avg', '${snapshot.averageCaptureMs.toStringAsFixed(2)} ms'),
            _row('Capture p95', '${snapshot.p95CaptureMs.toStringAsFixed(2)} ms'),
            _row('Captured', '${snapshot.captureFrameCount}'),
            _row('Overwritten', '${snapshot.overwrittenCaptureFrames}'),
            _row('AV dropped', '${snapshot.droppedCaptureFrames}'),
            _row('Capture loss', '${(snapshot.captureLossRate * 100).toStringAsFixed(2)}%'),
            const Divider(),
            _section(context, 'Metal completion'),
            _row('Unique FPS', snapshot.uniqueRenderedFps.toStringAsFixed(2)),
            _row('Unique frames', '${snapshot.uniqueRenderedFrames}'),
            _row('Commands', '${snapshot.commandCompletionCount}'),
            _row(
              'Completion avg',
              '${snapshot.averageCommandCompletionMs.toStringAsFixed(2)} ms',
            ),
            _row(
              'Completion p95',
              '${snapshot.p95CommandCompletionMs.toStringAsFixed(2)} ms',
            ),
            _row(
              'Completion p99',
              '${snapshot.p99CommandCompletionMs.toStringAsFixed(2)} ms',
            ),
            _row(
              'Completion max',
              '${snapshot.maxCommandCompletionMs.toStringAsFixed(2)} ms',
            ),
            _row('Elapsed', '${snapshot.elapsedSeconds.toStringAsFixed(1)} s'),
            const Divider(),
            _statusRow(
              context,
              enoughData: enoughData,
              passed: displayPassed,
              pendingLabel: 'Collecting display data…',
              passLabel: 'G1 display pacing PASS',
              failLabel: 'G1 display pacing FAIL',
            ),
            const SizedBox(height: 6),
            _statusRow(
              context,
              enoughData: enoughData,
              passed: pipelinePassed,
              pendingLabel: 'Collecting pipeline data…',
              passLabel: 'Pipeline health PASS',
              failLabel: 'Pipeline health CHECK',
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String text) => Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            text,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
      );

  Widget _statusRow(
    BuildContext context, {
    required bool enoughData,
    required bool passed,
    required String pendingLabel,
    required String passLabel,
    required String failLabel,
  }) {
    final color = !enoughData
        ? null
        : passed
            ? Colors.green
            : Theme.of(context).colorScheme.error;
    return Row(
      children: [
        Icon(
          !enoughData
              ? Icons.timelapse_rounded
              : passed
                  ? Icons.check_circle_rounded
                  : Icons.info_rounded,
          color: color,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            !enoughData
                ? pendingLabel
                : passed
                    ? passLabel
                    : failLabel,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
}
