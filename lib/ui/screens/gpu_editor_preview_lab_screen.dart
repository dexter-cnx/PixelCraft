import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../gpu/gpu_editor_preview_bridge.dart';
import '../../gpu/ios_gpu_editor_preview.dart';

class GpuEditorPreviewLabScreen extends StatefulWidget {
  const GpuEditorPreviewLabScreen({super.key});

  @override
  State<GpuEditorPreviewLabScreen> createState() => _GpuEditorPreviewLabScreenState();
}

class _GpuEditorPreviewLabScreenState extends State<GpuEditorPreviewLabScreen> {
  static const _profiles = <(String, String)>[
    ('', 'Original'),
    ('provia_inspired', 'Provia'),
    ('velvia_inspired', 'Velvia'),
    ('astia_inspired', 'Astia'),
    ('e100_inspired', 'E100'),
    ('ektar_inspired', 'Ektar'),
    ('chrome64_inspired', 'Chrome64'),
  ];

  final _bridge = const GpuEditorPreviewBridge();
  final _picker = ImagePicker();

  String? _rendererId;
  String? _sourcePath;
  String _profileId = '';
  double _filmStrength = 1;
  GpuEditorAdjustmentState _adjustments = const GpuEditorAdjustmentState();
  String? _error;
  bool _initializing = true;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  @override
  void dispose() {
    final id = _rendererId;
    _rendererId = null;
    if (id != null) unawaited(_bridge.destroyRenderer(id));
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
        throw StateError('G2.0 Editor GPU Preview Lab currently targets iOS Metal.');
      }
      final id = await _bridge.createRenderer();
      if (!mounted) {
        await _bridge.destroyRenderer(id);
        return;
      }
      setState(() {
        _rendererId = id;
        _initializing = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = '$error';
      });
    }
  }

  Future<void> _pickImage() async {
    final id = _rendererId;
    if (id == null) return;
    try {
      final file = await _picker.pickImage(source: ImageSource.gallery);
      if (file == null) return;
      await _bridge.setSourcePath(id, file.path);
      if (!mounted) return;
      setState(() {
        _sourcePath = file.path;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    }
  }

  Future<void> _setAdjustments(GpuEditorAdjustmentState next) async {
    final id = _rendererId;
    if (id == null) return;
    setState(() => _adjustments = next);
    try {
      await _bridge.setAdjustments(id, next);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _setFilm(String profileId, [double? strength]) async {
    final id = _rendererId;
    if (id == null) return;
    final nextStrength = strength ?? _filmStrength;
    setState(() {
      _profileId = profileId;
      _filmStrength = nextStrength;
    });
    try {
      await _bridge.setFilm(
        id,
        profileId: profileId,
        strength: profileId.isEmpty ? 0 : nextStrength,
      );
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _reset() async {
    const neutral = GpuEditorAdjustmentState();
    await _setAdjustments(neutral);
    await _setFilm('', 1);
  }

  @override
  Widget build(BuildContext context) {
    assert(kDebugMode, 'GPU editor preview lab is debug-only.');
    final id = _rendererId;

    return Scaffold(
      appBar: AppBar(title: const Text('G2 Editor GPU Preview Lab')),
      body: _initializing
          ? const Center(child: CircularProgressIndicator())
          : id == null
              ? Center(child: Text(_error ?? 'Editor GPU renderer unavailable'))
              : SafeArea(
                  child: Column(
                    children: [
                      Expanded(
                        child: ColoredBox(
                          color: Colors.black,
                          child: _sourcePath == null
                              ? Center(
                                  child: FilledButton.icon(
                                    onPressed: _pickImage,
                                    icon: const Icon(Icons.photo_library_outlined),
                                    label: const Text('Choose image'),
                                  ),
                                )
                              : IosGpuEditorPreview(rendererId: id),
                        ),
                      ),
                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: _pickImage,
                                      icon: const Icon(Icons.photo_library_outlined),
                                      label: const Text('Choose image'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  OutlinedButton(
                                    onPressed: _reset,
                                    child: const Text('Reset'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              _LiveSlider(
                                label: 'Brightness',
                                value: _adjustments.brightness,
                                min: 0,
                                max: 2,
                                onChanged: (value) => unawaited(
                                  _setAdjustments(
                                    _adjustments.copyWith(brightness: value),
                                  ),
                                ),
                              ),
                              _LiveSlider(
                                label: 'Contrast',
                                value: _adjustments.contrast,
                                min: 0,
                                max: 2,
                                onChanged: (value) => unawaited(
                                  _setAdjustments(
                                    _adjustments.copyWith(contrast: value),
                                  ),
                                ),
                              ),
                              _LiveSlider(
                                label: 'Saturation',
                                value: _adjustments.saturation,
                                min: 0,
                                max: 2,
                                onChanged: (value) => unawaited(
                                  _setAdjustments(
                                    _adjustments.copyWith(saturation: value),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              DropdownButtonFormField<String>(
                                initialValue: _profileId,
                                decoration: const InputDecoration(
                                  labelText: 'Film Profile',
                                  border: OutlineInputBorder(),
                                ),
                                items: [
                                  for (final profile in _profiles)
                                    DropdownMenuItem(
                                      value: profile.$1,
                                      child: Text(profile.$2),
                                    ),
                                ],
                                onChanged: (value) {
                                  if (value != null) unawaited(_setFilm(value));
                                },
                              ),
                              if (_profileId.isNotEmpty)
                                _LiveSlider(
                                  label: 'Film strength',
                                  value: _filmStrength,
                                  min: 0,
                                  max: 1,
                                  onChanged: (value) =>
                                      unawaited(_setFilm(_profileId, value)),
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
                              const SizedBox(height: 8),
                              Text(
                                'G2.0 validates static-image Metal rendering before it is connected to Editor Apply/Cancel/Undo/Redo. '
                                'Brightness, contrast and saturation use the same formulas as rust/src/filters.rs. '
                                'Temperature/tint is intentionally not implemented yet because Rust has no authoritative node for it.',
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

class _LiveSlider extends StatelessWidget {
  const _LiveSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          SizedBox(width: 88, child: Text(label)),
          Expanded(
            child: Slider(
              value: value.clamp(min, max).toDouble(),
              min: min,
              max: max,
              divisions: 100,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(value.toStringAsFixed(2), textAlign: TextAlign.end),
          ),
        ],
      );
}
