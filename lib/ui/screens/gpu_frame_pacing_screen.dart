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

  String get _benchmarkLabel =>
      _filmBenchmark ? 'Velvia 100%' : 'Original';

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
      // Re-apply the workload immediately before measurement so the recorded
      // interval cannot accidentally represent a stale renderer mode.
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
      // Keep the measurement running; stop() will surface a final error if the
      // native diagnostics channel is no longer available.
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
        '[GPU frame pacing] workload=$_benchmarkLabel '
        'fps=${snapshot.fps.toStringAsFixed(2)} '
        'avg=${snapshot.averageFrameMs.toStringAsFixed(2)}ms '
        'p95=${snapshot.p95FrameMs.toStringAsFixed(2)}ms '
        'p99=${snapshot.p99FrameMs.toStringAsFixed(2)}ms '
        'max=${snapshot.maxFrameMs.toStringAsFixed(2)}ms '
        'over40=${snapshot.over40MsFrames} '
        'frames=${snapshot.frameCount} '
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
        appBar: AppBar(title: const Text('GPU Frame Pacing')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null && _rendererId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('GPU Frame Pacing')),
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
      appBar: AppBar(title: const Text('GPU Frame Pacing')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ColoredBox(
                color: Colors.black,
                child: IosGpuCameraPreview(rendererId: rendererId),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
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
                    'Default G1 workload is Velvia at 100% strength so the '
                    'measurement includes the 33³ Film LUT shader path. '
                    'Target: sustained FPS ≥ 30 and p95 frame interval ≤ 40 ms. '
                    'Source is native MTKView draw cadence, not Flutter frame timing.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
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
    final passed = enoughData && snapshot.meetsG1Target;

    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            _row('Workload', workloadLabel),
            _row('FPS', snapshot.fps.toStringAsFixed(2)),
            _row(
              'Average',
              '${snapshot.averageFrameMs.toStringAsFixed(2)} ms',
            ),
            _row('p95', '${snapshot.p95FrameMs.toStringAsFixed(2)} ms'),
            _row('p99', '${snapshot.p99FrameMs.toStringAsFixed(2)} ms'),
            _row('Max', '${snapshot.maxFrameMs.toStringAsFixed(2)} ms'),
            _row('> 40 ms', '${snapshot.over40MsFrames} frames'),
            _row('Frames', '${snapshot.frameCount}'),
            _row(
              'Elapsed',
              '${snapshot.elapsedSeconds.toStringAsFixed(1)} s',
            ),
            const Divider(),
            Row(
              children: [
                Icon(
                  !enoughData
                      ? Icons.timelapse_rounded
                      : passed
                          ? Icons.check_circle_rounded
                          : Icons.error_rounded,
                  color: !enoughData
                      ? null
                      : passed
                          ? Colors.green
                          : Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 8),
                Text(
                  !enoughData
                      ? 'Collecting data…'
                      : passed
                          ? 'G1 pacing target PASS'
                          : 'G1 pacing target FAIL',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ],
        ),
      ),
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
