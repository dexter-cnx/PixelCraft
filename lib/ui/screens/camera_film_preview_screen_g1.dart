import 'dart:async';

import 'package:camera/camera.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_routes.dart';
import '../../app/platform_flow_foundation.dart';
import '../../app/platform_media_services.dart';
import '../../camera/camera_film_presets.dart';
import '../../gpu/android_gpu_camera_preview.dart';
import '../../gpu/gpu_preview_capability.dart';
import '../../gpu/gpu_preview_renderer.dart';
import '../../gpu/ios_gpu_camera_preview.dart';
import '../../gpu/native_gpu_camera_bridge.dart';
import '../../gpu/native_gpu_preview_bridge.dart';
import '../camera/camera_primary_controls.dart';

class CameraFilmPreviewScreen extends StatefulWidget {
  const CameraFilmPreviewScreen({super.key, this.mediaPickerService});

  final MediaPickerService? mediaPickerService;

  @override
  State<CameraFilmPreviewScreen> createState() =>
      _CameraFilmPreviewScreenState();
}

class _CameraFilmPreviewScreenState extends State<CameraFilmPreviewScreen>
    with WidgetsBindingObserver {
  static const _gpuPolicy = GpuPreviewCapabilityPolicy();

  final _gpuBridge = const NativeGpuPreviewBridge();
  final _nativeCameraBridge = const NativeGpuCameraBridge();

  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  CameraDescription? _activeCamera;

  String? _gpuRendererId;
  List<String> _nativeLenses = const [];
  bool _useNativeGpu = false;

  CameraFilmPreset _preset = cameraFilmPresets.first;
  CameraPrimaryTool _selectedTool = CameraPrimaryTool.film;
  double _strength = 1;
  bool _isInitializing = true;
  bool _isCapturing = false;
  String? _error;

  late final MediaPickerService _mediaPickerService =
      widget.mediaPickerService ?? ImagePickerMediaService();

  bool get _supportsNativeGpuCamera =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _nativeCameraBridge.setRuntimeFailureHandler(_handleNativeRuntimeFailure);
    unawaited(_discoverAndInitialize());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _nativeCameraBridge.setRuntimeFailureHandler(null);
    final rendererId = _gpuRendererId;
    _gpuRendererId = null;
    if (rendererId != null) {
      unawaited(_gpuBridge.destroyRenderer(rendererId));
    }
    final controller = _controller;
    _controller = null;
    if (controller != null) unawaited(controller.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final rendererId = _gpuRendererId;
    if (_useNativeGpu && rendererId != null) {
      if (state == AppLifecycleState.inactive ||
          state == AppLifecycleState.paused) {
        unawaited(_gpuBridge.pause(rendererId));
      } else if (state == AppLifecycleState.resumed) {
        unawaited(_gpuBridge.resume(rendererId));
      }
      return;
    }

    final camera = _activeCamera;
    if (camera == null) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(_detachAndDisposeController(showLoading: true));
    } else if (state == AppLifecycleState.resumed && _controller == null) {
      unawaited(_initializeCamera(camera));
    }
  }

  Future<void> _discoverAndInitialize() async {
    if (await _tryInitializeNativeGpu()) return;
    await _initializeFallbackCameraFlow();
  }

  Future<bool> _tryInitializeNativeGpu() async {
    if (!_supportsNativeGpuCamera) return false;

    String? rendererId;
    try {
      final probe = await _gpuBridge.probe();
      final decision = _gpuPolicy.evaluate(probe);
      if (!decision.useNativeGpu) return false;

      final permissionGranted = await _nativeCameraBridge
          .requestCameraPermission();
      if (!permissionGranted) {
        if (!mounted) return true;
        setState(() {
          _isInitializing = false;
          _error = 'errors.permission_denied'.tr();
        });
        return true;
      }

      final lenses = await _nativeCameraBridge.availableLenses();
      rendererId = await _gpuBridge.createRenderer();
      await _gpuBridge.setEnabled(rendererId, false);

      if (!mounted) {
        await _gpuBridge.destroyRenderer(rendererId);
        return true;
      }
      setState(() {
        _gpuRendererId = rendererId;
        _nativeLenses = lenses;
        _useNativeGpu = true;
        _isInitializing = false;
        _error = null;
      });
      return true;
    } catch (_) {
      if (rendererId != null) {
        try {
          await _gpuBridge.destroyRenderer(rendererId);
        } catch (_) {}
      }
      try {
        await _gpuBridge.invalidateCapabilityCache();
      } catch (_) {}
      return false;
    }
  }

  Future<void> _initializeFallbackCameraFlow() async {
    try {
      final cameras = await availableCameras();
      if (!mounted) return;
      if (cameras.isEmpty) {
        setState(() {
          _isInitializing = false;
          _error = 'errors.camera_unavailable'.tr();
        });
        return;
      }
      _cameras = cameras;
      final rear = cameras.where(
        (camera) => camera.lensDirection == CameraLensDirection.back,
      );
      await _initializeCamera(rear.isNotEmpty ? rear.first : cameras.first);
    } on CameraException catch (error) {
      _showCameraError(error);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isInitializing = false;
        _error = 'errors.camera_unavailable'.tr();
      });
    }
  }

  Future<void> _handleNativeRuntimeFailure(
    String rendererId,
    String message,
  ) async {
    if (!mounted || rendererId != _gpuRendererId) return;

    _gpuRendererId = null;
    setState(() {
      _useNativeGpu = false;
      _isInitializing = true;
    });
    try {
      await _gpuBridge.destroyRenderer(rendererId);
    } catch (_) {}
    if (!mounted) return;
    await _initializeFallbackCameraFlow();
  }

  Future<void> _initializeCamera(CameraDescription camera) async {
    if (!mounted) return;
    final previous = _controller;
    setState(() {
      _controller = null;
      _isInitializing = true;
      _error = null;
    });
    if (previous != null) {
      await WidgetsBinding.instance.endOfFrame;
      await previous.dispose();
    }
    if (!mounted) return;

    final controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    try {
      await controller.initialize();
      await controller.setFlashMode(FlashMode.off);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _activeCamera = camera;
        _isInitializing = false;
        _error = null;
      });
    } on CameraException catch (error) {
      await controller.dispose();
      _showCameraError(error);
    }
  }

  Future<void> _detachAndDisposeController({required bool showLoading}) async {
    final controller = _controller;
    if (controller == null) return;
    if (mounted) {
      setState(() {
        _controller = null;
        if (showLoading) _isInitializing = true;
      });
      await WidgetsBinding.instance.endOfFrame;
    } else {
      _controller = null;
    }
    await controller.dispose();
  }

  void _showCameraError(CameraException error) {
    if (!mounted) return;
    final message = switch (error.code) {
      'CameraAccessDenied' ||
      'CameraAccessDeniedWithoutPrompt' => 'errors.permission_denied'.tr(),
      'CameraAccessRestricted' => 'errors.permission_restricted'.tr(),
      _ => 'errors.camera_unavailable'.tr(),
    };
    setState(() {
      _isInitializing = false;
      _error = message;
    });
  }

  bool get _canSwitchCamera => _useNativeGpu
      ? _nativeLenses.length > 1
      : _cameras.length > 1 && _activeCamera != null;

  Future<void> _switchCamera() async {
    if (_isCapturing || !_canSwitchCamera) return;
    final rendererId = _gpuRendererId;
    if (_useNativeGpu && rendererId != null) {
      await _nativeCameraBridge.switchCamera(rendererId);
      return;
    }

    final current = _activeCamera;
    if (current == null) return;
    final currentIndex = _cameras.indexOf(current);
    await _initializeCamera(_cameras[(currentIndex + 1) % _cameras.length]);
  }

  Future<void> _capture() async {
    if (_isCapturing) return;
    setState(() => _isCapturing = true);
    try {
      if (_useNativeGpu && _gpuRendererId != null) {
        await _captureNative(_gpuRendererId!);
      } else {
        await _captureFallback();
      }
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  Future<void> _captureNative(String rendererId) async {
    final path = await _nativeCameraBridge.capturePhoto(rendererId);
    if (!mounted) return;
    await _gpuBridge.pause(rendererId);
    if (!mounted) return;
    await _openEditor(path, profileId: _preset.id, strength: _strength);
    if (!mounted || rendererId != _gpuRendererId) return;
    await _gpuBridge.resume(rendererId);
  }

  Future<void> _captureFallback() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        controller.value.isTakingPicture) {
      return;
    }
    final capture = await controller.takePicture();
    if (!mounted) return;
    final camera = _activeCamera;
    await _detachAndDisposeController(showLoading: true);
    if (!mounted) return;
    await _openEditor(capture.path, profileId: _preset.id, strength: _strength);
    if (!mounted) return;
    if (camera != null) await _initializeCamera(camera);
  }

  Future<void> _pickGallery() async {
    if (_isCapturing) return;
    final source = await _mediaPickerService.pickImage();
    if (!mounted || source == null) return;
    if (source.provenance != MediaSourceProvenance.gallery ||
        !source.uri.isScheme('file')) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('errors.unsupported_source'.tr())));
      return;
    }
    await _openEditor(source.uri.toFilePath(), profileId: '', strength: 0);
  }

  Future<void> _openEditor(
    String imagePath, {
    required String profileId,
    required double strength,
  }) async {
    await context.pushNamed(
      AppRouteNames.editor,
      extra: EditorRouteData(
        imagePath: imagePath,
        initialFilmProfileId: profileId.isEmpty ? null : profileId,
        initialFilmStrength: strength,
      ),
    );
  }

  void _selectPreset(CameraFilmPreset preset) {
    final strength = preset.isOriginal ? 0.0 : 1.0;
    setState(() {
      _preset = preset;
      _strength = strength;
    });
    final rendererId = _gpuRendererId;
    if (!_useNativeGpu || rendererId == null) return;
    if (preset.isOriginal) {
      unawaited(_gpuBridge.setEnabled(rendererId, false));
    } else {
      unawaited(_applyNativeFilm(rendererId, preset.id, strength));
    }
  }

  Future<void> _applyNativeFilm(
    String rendererId,
    String profileId,
    double strength,
  ) async {
    await _gpuBridge.setFilm(
      rendererId,
      GpuPreviewFilmState(profileId: profileId, strength: strength),
    );
    await _gpuBridge.setEnabled(rendererId, true);
  }

  void _setStrength(double value) {
    setState(() => _strength = value);
    final rendererId = _gpuRendererId;
    if (_useNativeGpu && rendererId != null) {
      unawaited(_gpuBridge.setStrength(rendererId, value));
    }
  }

  void _selectTool(CameraPrimaryTool tool) {
    if (tool == CameraPrimaryTool.film) {
      setState(() => _selectedTool = tool);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          tool == CameraPrimaryTool.filter
              ? 'camera.filter'.tr()
              : 'camera.adjust'.tr(),
        ),
      ),
    );
  }

  Future<void> _showCameraControls() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF111111),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'camera.controls'.tr(),
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.cameraswitch_outlined),
                iconColor: Colors.white,
                textColor: Colors.white,
                title: Text('camera.switch_camera'.tr()),
                enabled: _canSwitchCamera,
                onTap: _canSwitchCamera
                    ? () {
                        Navigator.pop(context);
                        unawaited(_switchCamera());
                      }
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildViewfinder(),
            _buildTopBar(),
            if (_selectedTool == CameraPrimaryTool.film) _buildFilmControls(),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: CameraPrimaryControls(
                selectedTool: _selectedTool,
                onToolSelected: _selectTool,
                onGalleryPressed: _pickGallery,
                onShutterPressed: _capture,
                onControlsPressed: _showCameraControls,
                galleryLabel: 'camera.gallery'.tr(),
                filmLabel: 'camera.film'.tr(),
                filterLabel: 'camera.filter'.tr(),
                adjustLabel: 'camera.adjust'.tr(),
                controlsLabel: 'camera.controls'.tr(),
                shutterSemanticLabel: 'camera.take_photo'.tr(),
                isCapturing: _isCapturing,
              ),
            ),
            if (_isCapturing)
              const Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(color: Color(0x22000000)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildViewfinder() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.no_photography_outlined,
                color: Colors.white70,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 20),
              FilledButton.tonal(
                onPressed: () {
                  setState(() {
                    _error = null;
                    _isInitializing = true;
                  });
                  unawaited(_discoverAndInitialize());
                },
                child: Text('camera.try_again'.tr()),
              ),
            ],
          ),
        ),
      );
    }

    final rendererId = _gpuRendererId;
    if (_useNativeGpu && rendererId != null) {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        return IosGpuCameraPreview(rendererId: rendererId);
      }
      return AndroidGpuCameraPreview(rendererId: rendererId);
    }

    final controller = _controller;
    if (_isInitializing ||
        controller == null ||
        !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    final preview = ColorFiltered(
      colorFilter: _preset.colorFilter(_strength),
      child: CameraPreview(controller),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenAspect = constraints.maxWidth / constraints.maxHeight;
        final previewAspect = controller.value.aspectRatio;
        var scale = screenAspect * previewAspect;
        if (scale < 1) scale = 1 / scale;
        return ClipRect(
          child: Transform.scale(
            scale: scale,
            child: Center(child: preview),
          ),
        );
      },
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      left: 12,
      right: 12,
      top: 8,
      child: Row(
        children: [
          const Spacer(),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Text(
                _useNativeGpu
                    ? 'camera.gpu_film_preview'.tr()
                    : 'camera.film_preview'.tr(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildFilmControls() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 156,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Color(0xB3000000)],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 40, 0, 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _preset.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (!_preset.isOriginal)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 44),
                  child: Slider(
                    value: _strength,
                    min: 0,
                    max: 1,
                    onChanged: _isCapturing ? null : _setStrength,
                  ),
                )
              else
                const SizedBox(height: 12),
              SizedBox(
                height: 42,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: cameraFilmPresets.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final preset = cameraFilmPresets[index];
                    final selected = preset.id == _preset.id;
                    return ChoiceChip(
                      selected: selected,
                      label: Text(preset.name.replaceAll(' Inspired', '')),
                      onSelected: _isCapturing
                          ? null
                          : (_) => _selectPreset(preset),
                      selectedColor: Colors.white,
                      backgroundColor: Colors.black54,
                      side: BorderSide(
                        color: selected ? Colors.white : Colors.white38,
                      ),
                      labelStyle: TextStyle(
                        color: selected ? Colors.black : Colors.white,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                      showCheckmark: false,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
