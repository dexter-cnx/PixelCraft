import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/image_engine.dart';
import '../../gpu/gpu_frame_pacing_bridge.dart';
import '../../gpu/gpu_preview_renderer.dart';
import '../../gpu/ios_gpu_camera_preview.dart';
import '../../gpu/native_gpu_camera_bridge.dart';
import '../../gpu/native_gpu_preview_bridge.dart';

class GpuColorCharacterizationScreen extends StatefulWidget {
  const GpuColorCharacterizationScreen({super.key});

  @override
  State<GpuColorCharacterizationScreen> createState() =>
      _GpuColorCharacterizationScreenState();
}

class _GpuColorCharacterizationScreenState
    extends State<GpuColorCharacterizationScreen> {
  static const _profileId = 'velvia_inspired';
  static const _strength = 1.0;

  final _gpuBridge = const NativeGpuPreviewBridge();
  final _cameraBridge = const NativeGpuCameraBridge();
  final _diagnosticsBridge = const GpuFramePacingBridge();
  final ImageEngine _engine = const RustImageEngine();

  String? _rendererId;
  NativeGpuProbe? _probe;
  _ColorCharacterizationResult? _result;
  bool _initializing = true;
  bool _measuring = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  @override
  void dispose() {
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
        throw StateError('Color characterization currently targets iOS Metal.');
      }
      final probe = await _gpuBridge.probe(forceSelfTest: true);
      if (!probe.available || probe.backend != GpuPreviewBackendKind.iosMetal) {
        throw StateError('iOS Metal backend is unavailable on this device.');
      }
      final permission = await _cameraBridge.requestCameraPermission();
      if (!permission) {
        throw StateError(
          'Camera permission is required for color characterization.',
        );
      }

      final rendererId = await _gpuBridge.createRenderer();
      await _gpuBridge.setFilm(
        rendererId,
        const GpuPreviewFilmState(profileId: _profileId, strength: _strength),
      );
      await _gpuBridge.setEnabled(rendererId, true);

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

  Future<void> _measure() async {
    final rendererId = _rendererId;
    if (_measuring || rendererId == null) return;

    setState(() {
      _measuring = true;
      _result = null;
      _error = null;
    });

    try {
      final native = await _diagnosticsBridge.colorSample(rendererId);
      final capture = await _cameraBridge.capturePhoto(rendererId);
      final cleanBytes = await File(capture.path).readAsBytes();

      final loaded = await _engine.loadImageInBackground(
        cleanBytes,
        maxEdge: 512,
      );
      final filmPreviews = await _engine.generateFilmProfilePreviews(
        cleanBytes,
        const [_profileId],
        maxEdge: 512,
      );
      final rustFilmBytes = filmPreviews[_profileId];
      if (rustFilmBytes == null) {
        throw StateError(
          'Rust did not return the Velvia characterization preview.',
        );
      }

      final rustSourceMean = await _centerSquareMeanRgb(
        loaded.originalPreviewBytes,
      );
      final rustFilmMean = await _centerSquareMeanRgb(rustFilmBytes);
      final sourceDelta = _delta(native.sourceMeanRgb, rustSourceMean);
      final filmDelta = _delta(native.filmMeanRgb, rustFilmMean);

      final result = _ColorCharacterizationResult(
        native: native,
        rustSourceMean: rustSourceMean,
        rustFilmMean: rustFilmMean,
        sourceDelta: sourceDelta,
        filmDelta: filmDelta,
      );

      debugPrint(
        '[GPU color] sourceNative=${_fmt(native.sourceMeanRgb)} '
        'sourceRust=${_fmt(rustSourceMean)} sourceDelta=${_fmt(sourceDelta)} '
        'filmNative=${_fmt(native.filmMeanRgb)} '
        'filmRust=${_fmt(rustFilmMean)} filmDelta=${_fmt(filmDelta)}',
      );

      if (!mounted) return;
      setState(() => _result = result);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _measuring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    assert(
      kDebugMode,
      'GpuColorCharacterizationScreen is intended for debug builds only.',
    );

    if (_initializing) {
      return Scaffold(
        appBar: AppBar(title: const Text('GPU Color Characterization')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_rendererId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('GPU Color Characterization')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_error ?? 'Unable to initialize diagnostics.'),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('GPU Color Characterization')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ColoredBox(
                color: Colors.black,
                child: IosGpuCameraPreview(rendererId: _rendererId!),
              ),
            ),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                children: [
                  Text(
                    '${_probe?.renderer ?? 'iOS Metal'} · Velvia 100%',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Point at a stable, evenly lit scene and keep the phone still. '
                    'The test samples the latest AVCapture center ROI, then takes a clean JPEG and replays Velvia through Rust.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _measuring ? null : _measure,
                    icon: _measuring
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.color_lens_outlined),
                    label: Text(
                      _measuring
                          ? 'Characterizing…'
                          : 'Capture & Characterize Color',
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  if (_result != null) ...[
                    const SizedBox(height: 12),
                    _ColorResultCard(result: _result!),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    'This is a characterization, not a pixel-perfect parity test. '
                    'Preview frames and AVCapturePhotoOutput pass through different ISP/still-photo paths and are captured at slightly different times. '
                    'Only RGB statistics cross Dart; no live camera frame buffer is sent through MethodChannel. Metal LUT numeric parity is verified separately by G1V.1.',
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

  static Future<List<double>> _centerSquareMeanRgb(Uint8List encoded) async {
    final codec = await ui.instantiateImageCodec(encoded);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) throw StateError('Unable to read decoded RGB pixels.');

      final bytes = data.buffer.asUint8List();
      final width = image.width;
      final height = image.height;
      final side = width < height ? width : height;
      final originX = (width - side) ~/ 2;
      final originY = (height - side) ~/ 2;
      final step = (side / 64).floor().clamp(1, side).toInt();

      var red = 0.0;
      var green = 0.0;
      var blue = 0.0;
      var samples = 0;
      for (var y = originY; y < originY + side; y += step) {
        for (var x = originX; x < originX + side; x += step) {
          final offset = (y * width + x) * 4;
          red += bytes[offset] / 255.0;
          green += bytes[offset + 1] / 255.0;
          blue += bytes[offset + 2] / 255.0;
          samples++;
        }
      }
      return [red / samples, green / samples, blue / samples];
    } finally {
      image.dispose();
      codec.dispose();
    }
  }

  static List<double> _delta(List<double> a, List<double> b) => [
    (a[0] - b[0]).abs(),
    (a[1] - b[1]).abs(),
    (a[2] - b[2]).abs(),
  ];

  static String _fmt(List<double> rgb) =>
      rgb.map((value) => value.toStringAsFixed(4)).join(',');
}

class _ColorCharacterizationResult {
  const _ColorCharacterizationResult({
    required this.native,
    required this.rustSourceMean,
    required this.rustFilmMean,
    required this.sourceDelta,
    required this.filmDelta,
  });

  final GpuColorCharacterizationSample native;
  final List<double> rustSourceMean;
  final List<double> rustFilmMean;
  final List<double> sourceDelta;
  final List<double> filmDelta;

  double get sourceMaxDelta => sourceDelta.reduce((a, b) => a > b ? a : b);
  double get filmMaxDelta => filmDelta.reduce((a, b) => a > b ? a : b);
}

class _ColorResultCard extends StatelessWidget {
  const _ColorResultCard({required this.result});

  final _ColorCharacterizationResult result;

  @override
  Widget build(BuildContext context) => Card.filled(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Center ROI color statistics',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 10),
          _rgbRow('Native source', result.native.sourceMeanRgb),
          _rgbRow('Rust clean JPEG', result.rustSourceMean),
          _rgbRow('Source |Δ|', result.sourceDelta),
          _metric('Source max Δ', result.sourceMaxDelta.toStringAsFixed(4)),
          const Divider(height: 24),
          _rgbRow('Native Film estimate', result.native.filmMeanRgb),
          _rgbRow('Rust Velvia', result.rustFilmMean),
          _rgbRow('Film |Δ|', result.filmDelta),
          _metric('Film max Δ', result.filmMaxDelta.toStringAsFixed(4)),
          const Divider(height: 24),
          _metric('Native samples', '${result.native.samples}'),
          _metric('ROI', result.native.roi),
          _metric('Native format', result.native.pixelFormat),
          const SizedBox(height: 8),
          const Text(
            'Record these deviations as the camera/still color-path characterization. Rust final rendering remains authoritative.',
          ),
        ],
      ),
    ),
  );

  Widget _rgbRow(String label, List<double> rgb) => _metric(
    label,
    'R ${rgb[0].toStringAsFixed(4)}  '
    'G ${rgb[1].toStringAsFixed(4)}  '
    'B ${rgb[2].toStringAsFixed(4)}',
  );

  Widget _metric(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 132, child: Text(label)),
        Expanded(
          child: SelectableText(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}
