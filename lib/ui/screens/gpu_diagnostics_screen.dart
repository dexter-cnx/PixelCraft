import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../gpu/gpu_preview_renderer.dart';
import '../../gpu/native_gpu_preview_bridge.dart';

class GpuDiagnosticsScreen extends StatefulWidget {
  const GpuDiagnosticsScreen({super.key});

  @override
  State<GpuDiagnosticsScreen> createState() => _GpuDiagnosticsScreenState();
}

class _GpuDiagnosticsScreenState extends State<GpuDiagnosticsScreen> {
  static const _tolerance = 2 / 255;
  static const _profiles = <String>[
    'provia_inspired',
    'velvia_inspired',
    'astia_inspired',
    'e100_inspired',
    'ektar_inspired',
    'chrome64_inspired',
  ];

  final NativeGpuPreviewBridge _bridge = const NativeGpuPreviewBridge();

  NativeGpuProbe? _probe;
  final Map<String, NativeGpuHarnessResult> _results = {};
  final Map<String, String> _errors = {};
  bool _running = false;
  String? _activeProfile;

  @override
  void initState() {
    super.initState();
    _refreshProbe();
  }

  Future<void> _refreshProbe() async {
    try {
      final probe = await _bridge.probe(forceSelfTest: true);
      if (!mounted) return;
      setState(() => _probe = probe);
    } catch (error) {
      if (!mounted) return;
      setState(() => _errors['probe'] = '$error');
    }
  }

  Future<void> _runAll() async {
    if (_running) return;
    setState(() {
      _running = true;
      _activeProfile = 'identity';
      _results.clear();
      _errors.clear();
    });

    try {
      final probe = await _bridge.probe(forceSelfTest: true);
      if (!mounted) return;
      setState(() => _probe = probe);

      await _runOne('identity', _bridge.runReferenceHarness);
      for (final profileId in _profiles) {
        await _runOne(
          profileId,
          () => _bridge.runFilmProfileHarness(profileId),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
          _activeProfile = null;
        });
      }
    }
  }

  Future<void> _runOne(
    String profileId,
    Future<NativeGpuHarnessResult> Function() action,
  ) async {
    if (!mounted) return;
    setState(() => _activeProfile = profileId);
    try {
      final result = await action();
      if (!mounted) return;
      setState(() => _results[profileId] = result);
      debugPrint(
        '[GPU diagnostics] ${_probe?.backend.name ?? 'unknown'} '
        '$profileId samples=${result.samples} '
        'maxError=${result.maxChannelError.toStringAsFixed(8)} '
        'passed=${result.passed}',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _errors[profileId] = '$error');
    }
  }

  Iterable<MapEntry<String, String>> get _harnessErrors =>
      _errors.entries.where((entry) => entry.key != 'probe');

  bool get _hasCompleteRun =>
      _results.length + _harnessErrors.length == _profiles.length + 1;

  bool get _overallPassed =>
      _hasCompleteRun &&
      _harnessErrors.isEmpty &&
      _results.length == _profiles.length + 1 &&
      _results.values.every(
        (result) => result.passed && result.maxChannelError <= _tolerance,
      );

  @override
  Widget build(BuildContext context) {
    assert(kDebugMode, 'GpuDiagnosticsScreen is intended for debug builds only.');
    final probe = _probe;

    return Scaffold(
      appBar: AppBar(title: const Text('GPU Diagnostics')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card.filled(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Native GPU capability',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  _MetricRow('Backend', _backendLabel(probe?.backend)),
                  _MetricRow(
                    'Renderer',
                    probe?.renderer.isNotEmpty == true ? probe!.renderer : '—',
                  ),
                  _MetricRow(
                    'Version',
                    probe?.version.isNotEmpty == true ? probe!.version : '—',
                  ),
                  _MetricRow(
                    'LUT size',
                    probe == null ? '—' : '${probe.maxLutSize}³',
                  ),
                  _MetricRow(
                    'LUT33',
                    probe == null
                        ? '—'
                        : (probe.supportsLut33 ? 'Supported' : 'Unsupported'),
                  ),
                  _MetricRow(
                    'Self-test',
                    probe == null
                        ? '—'
                        : (probe.selfTestPassed ? 'PASS' : 'FAIL'),
                  ),
                  _MetricRow(
                    'Assets',
                    probe == null
                        ? '—'
                        : (probe.assetsLoaded ? 'Loaded' : 'Missing'),
                  ),
                  _MetricRow(
                    'Tolerance',
                    '${_tolerance.toStringAsFixed(8)} (2/255)',
                  ),
                  if (_errors['probe'] case final error?) ...[
                    const SizedBox(height: 8),
                    Text(
                      error,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _running ? null : _runAll,
            icon: _running
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow_rounded),
            label: Text(
              _running
                  ? 'Running ${_displayName(_activeProfile ?? '')}…'
                  : 'Run LUT Parity',
            ),
          ),
          const SizedBox(height: 16),
          if (_hasCompleteRun)
            Card(
              color: _overallPassed
                  ? Colors.green.withValues(alpha: 0.10)
                  : Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                leading: Icon(
                  _overallPassed
                      ? Icons.check_circle_rounded
                      : Icons.error_rounded,
                  color: _overallPassed
                      ? Colors.green
                      : Theme.of(context).colorScheme.error,
                ),
                title: Text(_overallPassed ? 'Overall PASS' : 'Overall FAIL'),
                subtitle: const Text(
                  'All native LUT samples must remain within 2/255 per channel.',
                ),
              ),
            ),
          if (_hasCompleteRun) const SizedBox(height: 12),
          ...['identity', ..._profiles].map(_buildResultCard),
          const SizedBox(height: 24),
          Text(
            'This diagnostic runs deterministic offscreen GPU fixtures. It does not capture or send live camera frames through Dart.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard(String profileId) {
    final result = _results[profileId];
    final error = _errors[profileId];
    final active = _running && _activeProfile == profileId;
    final passed = result != null &&
        result.passed &&
        result.maxChannelError <= _tolerance;

    return Card(
      child: ListTile(
        leading: active
            ? const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                result == null && error == null
                    ? Icons.radio_button_unchecked_rounded
                    : passed
                        ? Icons.check_circle_rounded
                        : Icons.cancel_rounded,
                color: result == null && error == null
                    ? null
                    : passed
                        ? Colors.green
                        : Theme.of(context).colorScheme.error,
              ),
        title: Text(_displayName(profileId)),
        subtitle: error != null
            ? Text(error)
            : result == null
                ? const Text('Not run')
                : Text(
                    'samples=${result.samples}  '
                    'maxError=${result.maxChannelError.toStringAsFixed(8)}',
                  ),
        trailing: result == null
            ? null
            : Text(
                passed ? 'PASS' : 'FAIL',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: passed
                      ? Colors.green
                      : Theme.of(context).colorScheme.error,
                ),
              ),
      ),
    );
  }

  static String _backendLabel(GpuPreviewBackendKind? backend) => switch (backend) {
        GpuPreviewBackendKind.androidOpenGl => 'Android OpenGL ES',
        GpuPreviewBackendKind.iosMetal => 'iOS Metal',
        GpuPreviewBackendKind.fallback => 'Fallback',
        null => '—',
      };

  static String _displayName(String profileId) => switch (profileId) {
        'identity' => 'Identity',
        'provia_inspired' => 'Provia Inspired',
        'velvia_inspired' => 'Velvia Inspired',
        'astia_inspired' => 'Astia Inspired',
        'e100_inspired' => 'E100 Inspired',
        'ektar_inspired' => 'Ektar Inspired',
        'chrome64_inspired' => 'Chrome64 Inspired',
        _ => profileId,
      };
}

class _MetricRow extends StatelessWidget {
  const _MetricRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(
              width: 96,
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
            Expanded(
              child: SelectableText(
                value,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
}
