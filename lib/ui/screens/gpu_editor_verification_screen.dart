import 'package:flutter/material.dart';

import '../../gpu/gpu_editor_diagnostics_bridge.dart';

class GpuEditorVerificationScreen extends StatefulWidget {
  const GpuEditorVerificationScreen({super.key});

  @override
  State<GpuEditorVerificationScreen> createState() =>
      _GpuEditorVerificationScreenState();
}

class _GpuEditorVerificationScreenState
    extends State<GpuEditorVerificationScreen> {
  static const _bridge = GpuEditorDiagnosticsBridge();

  GpuEditorParityResult? _parity;
  GpuEditorParityResult? _blurParity;
  GpuEditorParityResult? _creativeParity;
  GpuEditorLatencyResult? _latency;
  GpuEditorLatencyResult? _blurLatency;
  String? _error;
  bool _runningParity = false;
  bool _runningBlurParity = false;
  bool _runningCreativeParity = false;
  bool _runningLatency = false;
  bool _runningBlurLatency = false;

  Future<void> _runParity() async {
    if (_runningParity) return;
    setState(() {
      _runningParity = true;
      _error = null;
    });
    try {
      final result = await _bridge.runAdjustmentParity();
      if (!mounted) return;
      setState(() => _parity = result);
      debugPrint(
        '[G2 editor parity] passed=${result.passed} '
        'maxError=${result.overallMaxChannelError.toStringAsFixed(8)}',
      );
      for (final item in result.cases) {
        debugPrint(
          '[G2 editor parity] ${item.name} samples=${item.samples} '
          'maxError=${item.maxChannelError.toStringAsFixed(8)} '
          'passed=${item.passed}',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _runningParity = false);
    }
  }

  Future<void> _runBlurParity() async {
    if (_runningBlurParity) return;
    setState(() {
      _runningBlurParity = true;
      _error = null;
    });
    try {
      final result = await _bridge.runGaussianBlurParity();
      if (!mounted) return;
      setState(() => _blurParity = result);
      debugPrint(
        '[G2 gaussian parity] passed=${result.passed} '
        'maxError=${result.overallMaxChannelError.toStringAsFixed(8)}',
      );
      for (final item in result.cases) {
        debugPrint(
          '[G2 gaussian parity] ${item.name} samples=${item.samples} '
          'maxError=${item.maxChannelError.toStringAsFixed(8)} '
          'passed=${item.passed}',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _runningBlurParity = false);
    }
  }

  Future<void> _runCreativeParity() async {
    if (_runningCreativeParity) return;
    setState(() {
      _runningCreativeParity = true;
      _error = null;
    });
    try {
      final result = await _bridge.runCreativeParity();
      if (!mounted) return;
      setState(() => _creativeParity = result);
      debugPrint(
        '[G2 creative parity] passed=${result.passed} '
        'maxError=${result.overallMaxChannelError.toStringAsFixed(8)}',
      );
      for (final item in result.cases) {
        debugPrint(
          '[G2 creative parity] ${item.name} samples=${item.samples} '
          'maxError=${item.maxChannelError.toStringAsFixed(8)} '
          'passed=${item.passed}',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _runningCreativeParity = false);
    }
  }

  Future<void> _runLatency() async {
    if (_runningLatency) return;
    setState(() {
      _runningLatency = true;
      _error = null;
    });
    try {
      final result = await _bridge.runLatencyBenchmark();
      if (!mounted) return;
      setState(() => _latency = result);
      debugPrint(
        '[G2 editor latency] ${result.device} ${result.width}x${result.height} '
        'avg=${result.averageMs.toStringAsFixed(3)}ms '
        'p95=${result.p95Ms.toStringAsFixed(3)}ms '
        'p99=${result.p99Ms.toStringAsFixed(3)}ms '
        'passed=${result.passed}',
      );
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _runningLatency = false);
    }
  }

  Future<void> _runBlurLatency() async {
    if (_runningBlurLatency) return;
    setState(() {
      _runningBlurLatency = true;
      _error = null;
    });
    try {
      final result = await _bridge.runGaussianBlurLatencyBenchmark();
      if (!mounted) return;
      setState(() => _blurLatency = result);
      debugPrint(
        '[G2 gaussian latency] ${result.device} ${result.width}x${result.height} '
        'avg=${result.averageMs.toStringAsFixed(3)}ms '
        'p95=${result.p95Ms.toStringAsFixed(3)}ms '
        'p99=${result.p99Ms.toStringAsFixed(3)}ms '
        'passed=${result.passed}',
      );
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _runningBlurLatency = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('G2 Editor GPU Verification')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Numeric parity',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          const Text(
            'Brightness, contrast, saturation and sharpen are checked against Rust semantics. Film 33³ LUT sampling reuses the G1 canonical Metal parity path.',
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _runningParity ? null : _runParity,
            icon: _runningParity
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.rule_rounded),
            label: const Text('Run Editor Numeric Parity'),
          ),
          if (_parity case final parity?) ...[
            const SizedBox(height: 12),
            _ParityCard(
              result: parity,
              title: 'Editor parity',
              showFilmParity: true,
            ),
          ],
          const SizedBox(height: 28),
          Text(
            'Gaussian blur parity',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          const Text(
            'Checks a 9×9 spatial fixture using the imageproc 0.23 behavior used by the Rust engine: separable horizontal/vertical Gaussian passes, continuity edge padding, and u8 quantization between passes.',
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _runningBlurParity ? null : _runBlurParity,
            icon: _runningBlurParity
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.blur_on_rounded),
            label: const Text('Run Gaussian Blur Numeric Parity'),
          ),
          if (_blurParity case final blur?) ...[
            const SizedBox(height: 12),
            _ParityCard(
              result: blur,
              title: 'Gaussian blur parity',
              showFilmParity: false,
            ),
          ],
          const SizedBox(height: 28),
          Text(
            'Creative filter parity',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          const Text(
            'Checks grayscale and invert against photon-rs 0.3.3 u8 semantics, including PixelCraft intensity blending and rounding back to u8.',
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _runningCreativeParity ? null : _runCreativeParity,
            icon: _runningCreativeParity
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome_rounded),
            label: const Text('Run Creative Filter Numeric Parity'),
          ),
          if (_creativeParity case final creative?) ...[
            const SizedBox(height: 12),
            _ParityCard(
              result: creative,
              title: 'Creative filter parity',
              showFilmParity: false,
            ),
          ],
          const SizedBox(height: 28),
          Text(
            'Metal latency',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          const Text(
            'Runs a 1024×1024 Metal workload with brightness + contrast + saturation + Velvia 100%, then measures command completion after warm-up.',
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _runningLatency ? null : _runLatency,
            icon: _runningLatency
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.speed_rounded),
            label: const Text('Run 1024² Metal Latency Benchmark'),
          ),
          if (_latency case final latency?) ...[
            const SizedBox(height: 12),
            _LatencyCard(result: latency, title: 'Editor latency'),
          ],
          const SizedBox(height: 28),
          Text(
            'Gaussian blur latency',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          const Text(
            'Runs the worst-case editor blur value 2.00 (sigma 5.0) as two separable 1024×1024 Metal compute passes. Working textures are allocated before timing.',
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _runningBlurLatency ? null : _runBlurLatency,
            icon: _runningBlurLatency
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.blur_circular_rounded),
            label: const Text('Run 1024² Gaussian Blur Latency'),
          ),
          if (_blurLatency case final latency?) ...[
            const SizedBox(height: 12),
            _LatencyCard(result: latency, title: 'Gaussian blur latency'),
          ],
          if (_error case final error?) ...[
            const SizedBox(height: 16),
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(error),
              ),
            ),
          ],
          const SizedBox(height: 24),
          Text(
            'These diagnostics measure native Metal work only. Rust remains authoritative for committed edits and full-resolution export.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _ParityCard extends StatelessWidget {
  const _ParityCard({
    required this.result,
    required this.title,
    required this.showFilmParity,
  });

  final GpuEditorParityResult result;
  final String title;
  final bool showFilmParity;

  @override
  Widget build(BuildContext context) => Card.filled(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StatusLine(
                passed: result.passed,
                label: result.passed ? '$title PASS' : '$title FAIL',
              ),
              const SizedBox(height: 10),
              _MetricRow('Reference', result.reference),
              _MetricRow('Tolerance', result.tolerance.toStringAsFixed(8)),
              _MetricRow(
                'Overall max Δ',
                result.overallMaxChannelError.toStringAsFixed(8),
              ),
              const Divider(height: 24),
              for (final item in result.cases)
                _MetricRow(
                  item.name,
                  '${item.maxChannelError.toStringAsFixed(8)}  '
                  '${item.passed ? 'PASS' : 'FAIL'}',
                ),
              if (showFilmParity && result.filmParity.isNotEmpty) ...[
                const Divider(height: 24),
                Text(result.filmParity),
              ],
            ],
          ),
        ),
      );
}

class _LatencyCard extends StatelessWidget {
  const _LatencyCard({required this.result, required this.title});

  final GpuEditorLatencyResult result;
  final String title;

  @override
  Widget build(BuildContext context) => Card.filled(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StatusLine(
                passed: result.passed,
                label: result.passed ? '$title PASS' : '$title FAIL',
              ),
              const SizedBox(height: 10),
              _MetricRow('Device', result.device),
              _MetricRow('Workload', result.workload),
              _MetricRow('Size', '${result.width}×${result.height}'),
              _MetricRow('Iterations', '${result.iterations}'),
              _MetricRow('Average', '${result.averageMs.toStringAsFixed(3)} ms'),
              _MetricRow('p50', '${result.p50Ms.toStringAsFixed(3)} ms'),
              _MetricRow('p95', '${result.p95Ms.toStringAsFixed(3)} ms'),
              _MetricRow('p99', '${result.p99Ms.toStringAsFixed(3)} ms'),
              _MetricRow('Max', '${result.maxMs.toStringAsFixed(3)} ms'),
              _MetricRow(
                'Target p95',
                '≤ ${result.targetMs.toStringAsFixed(2)} ms',
              ),
            ],
          ),
        ),
      );
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.passed, required this.label});

  final bool passed;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(
            passed ? Icons.check_circle_rounded : Icons.error_rounded,
            color: passed ? Colors.green : Theme.of(context).colorScheme.error,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ],
      );
}

class _MetricRow extends StatelessWidget {
  const _MetricRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(label)),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
}
