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
  GpuEditorLatencyResult? _latency;
  String? _error;
  bool _runningParity = false;
  bool _runningLatency = false;

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
            'Brightness, contrast and saturation are checked against the exact u8 formulas used by rust/src/filters.rs. Film 33³ LUT sampling reuses the G1 canonical Metal parity path.',
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
            label: const Text('Run Adjustment Numeric Parity'),
          ),
          if (_parity case final parity?) ...[
            const SizedBox(height: 12),
            Card.filled(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _StatusLine(
                      passed: parity.passed,
                      label: parity.passed ? 'Adjustment parity PASS' : 'Adjustment parity FAIL',
                    ),
                    const SizedBox(height: 10),
                    _MetricRow('Reference', parity.reference),
                    _MetricRow(
                      'Tolerance',
                      '${parity.tolerance.toStringAsFixed(8)} (1/255)',
                    ),
                    _MetricRow(
                      'Overall max Δ',
                      parity.overallMaxChannelError.toStringAsFixed(8),
                    ),
                    const Divider(height: 24),
                    for (final item in parity.cases)
                      _MetricRow(
                        item.name,
                        '${item.maxChannelError.toStringAsFixed(8)}  ${item.passed ? 'PASS' : 'FAIL'}',
                      ),
                    const Divider(height: 24),
                    Text(parity.filmParity),
                  ],
                ),
              ),
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
            Card.filled(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _StatusLine(
                      passed: latency.passed,
                      label: latency.passed ? 'Latency target PASS' : 'Latency target FAIL',
                    ),
                    const SizedBox(height: 10),
                    _MetricRow('Device', latency.device),
                    _MetricRow('Workload', latency.workload),
                    _MetricRow('Size', '${latency.width}×${latency.height}'),
                    _MetricRow('Iterations', '${latency.iterations}'),
                    _MetricRow('Average', '${latency.averageMs.toStringAsFixed(3)} ms'),
                    _MetricRow('p50', '${latency.p50Ms.toStringAsFixed(3)} ms'),
                    _MetricRow('p95', '${latency.p95Ms.toStringAsFixed(3)} ms'),
                    _MetricRow('p99', '${latency.p99Ms.toStringAsFixed(3)} ms'),
                    _MetricRow('Max', '${latency.maxMs.toStringAsFixed(3)} ms'),
                    _MetricRow('Target p95', '≤ ${latency.targetMs.toStringAsFixed(2)} ms'),
                  ],
                ),
              ),
            ),
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
