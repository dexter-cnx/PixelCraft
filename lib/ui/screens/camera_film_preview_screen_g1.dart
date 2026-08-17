import 'dart:async';

import 'package:camera/camera.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/platform_flow_foundation.dart';
import '../../app/platform_media_services.dart';
import '../../camera/camera_film_editor_handoff.dart';
import '../../camera/camera_film_presets.dart';
import '../../camera/camera_look_preview_coordinator.dart';
import '../../camera/camera_look_state.dart';
import '../../gpu/android_gpu_camera_preview.dart';
import '../../gpu/gpu_preview_capability.dart';
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
  static const _cameraAdjustmentIds = <String>[
    'exposure',
    'temperature',
    'tint',
    'brightness',
    'contrast',
    'saturation',
    'vignette',
  ];

  final _gpuBridge = const NativeGpuPreviewBridge();
  final _nativeCameraBridge = const NativeGpuCameraBridge();
  final _lookCoordinator = CameraLookPreviewCoordinator();

  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  CameraDescription? _activeCamera;

  String? _gpuRendererId;
  List<String> _nativeLenses = const [];
  bool _useNativeGpu = false;

  CameraFilmPreset _preset = cameraFilmPresets.first;
  CameraPrimaryTool _selectedTool = CameraPrimaryTool.film;
  CameraLookState _cameraLook = CameraLookState();
  String _selectedAdjustmentId = 'exposure';
  double _strength = 1;
  bool _isInitializing = true;
  bool _isCapturing = false;
  String? _error;

  NativeCameraControlState _cameraControls = const NativeCameraControlState(
    lensDirection: 'back',
    hasFlash: true,
    hasTorch: true,
    flashMode: NativeCameraFlashMode.auto,
    torchEnabled: false,
    mirrorEnabled: false,
  );

  late final MediaPickerService _mediaPickerService =
      widget.mediaPickerService ?? ImagePickerMediaService();

  bool get _supportsNativeGpuCamera =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  bool get _supportsNativeDeviceControls => _supportsNativeGpuCamera;

  bool get _isFrontCamera => _useNativeGpu
      ? _cameraControls.isFront
      : _activeCamera?.lensDirection == CameraLensDirection.front;

  bool get _flashAvailable => _useNativeGpu
      ? _supportsNativeDeviceControls && _cameraControls.hasFlash
      : _activeCamera?.lensDirection == CameraLensDirection.back;

  bool get _torchAvailable => _useNativeGpu
      ? _supportsNativeDeviceControls && _cameraControls.hasTorch
      : _activeCamera?.lensDirection == CameraLensDirection.back;

  bool get _mirrorEnabled => _cameraControls.mirrorEnabled;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _nativeCameraBridge.setRuntimeFailureHandler(_handleNativeRuntimeFailure);
    _lookCoordinator.onFailure = (error) {
      final rendererId = _gpuRendererId;
      if (rendererId != null) {
        unawaited(_handleNativeRuntimeFailure(rendererId, error.toString()));
      }
    };
    unawaited(_discoverAndInitialize());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _nativeCameraBridge.setRuntimeFailureHandler(null);
    _lookCoordinator.onFailure = null;
    _lookCoordinator.detach();
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
      await _gpuBridge.setEnabled(rendererId, true);
      _lookCoordinator.attach(rendererId);
      _lookCoordinator.submit(_cameraLook);

      var controls = _cameraControls;
      if (_supportsNativeDeviceControls) {
        controls = await _nativeCameraBridge.controlState(rendererId);
      }

      if (!mounted) {
        _lookCoordinator.detach();
        await _gpuBridge.destroyRenderer(rendererId);
        return true;
      }
      setState(() {
        _gpuRendererId = rendererId;
        _nativeLenses = lenses;
        _cameraControls = controls;
        _useNativeGpu = true;
        _isInitializing = false;
        _error = null;
      });
      return true;
    } catch (_) {
      _lookCoordinator.detach();
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

    _lookCoordinator.detach();
    _gpuRendererId = null;
    setState(() {
      _useNativeGpu = false;
      _selectedTool = CameraPrimaryTool.film;
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
      final flashCapabilities = await _probeFallbackFlashCapabilities(
        controller,
      );
      if (flashCapabilities.hasFlash) {
        await _applyFallbackFlashMode(controller, _cameraControls.flashMode);
      }
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _activeCamera = camera;
        _cameraControls = NativeCameraControlState(
          lensDirection: camera.lensDirection == CameraLensDirection.front
              ? 'front'
              : 'back',
          hasFlash: flashCapabilities.hasFlash,
          hasTorch: flashCapabilities.hasTorch,
          flashMode: flashCapabilities.hasFlash
              ? _cameraControls.flashMode
              : NativeCameraFlashMode.off,
          torchEnabled: false,
          mirrorEnabled: _cameraControls.mirrorEnabled,
        );
        _isInitializing = false;
        _error = null;
      });
    } on CameraException catch (error) {
      await controller.dispose();
      _showCameraError(error);
    }
  }

  Future<({bool hasFlash, bool hasTorch})> _probeFallbackFlashCapabilities(
    CameraController controller,
  ) async {
    var hasFlash = false;
    var hasTorch = false;
    try {
      await controller.setFlashMode(FlashMode.auto);
      hasFlash = true;
    } on CameraException {
      // Unsupported auto flash means this fallback camera has no flash capability.
    }
    try {
      await controller.setFlashMode(FlashMode.torch);
      hasTorch = true;
    } on CameraException {
      // Unsupported torch means this fallback camera has no torch capability.
    }
    try {
      await controller.setFlashMode(FlashMode.off);
    } on CameraException {
      // Best-effort reset after probing; unsupported off mode needs no further action.
    }
    return (hasFlash: hasFlash, hasTorch: hasTorch);
  }

  Future<void> _applyFallbackFlashMode(
    CameraController controller,
    NativeCameraFlashMode mode,
  ) async {
    try {
      await controller.setFlashMode(switch (mode) {
        NativeCameraFlashMode.off => FlashMode.off,
        NativeCameraFlashMode.auto => FlashMode.auto,
        NativeCameraFlashMode.on => FlashMode.always,
      });
    } on CameraException {
      await controller.setFlashMode(FlashMode.off);
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
      if (_supportsNativeDeviceControls && mounted) {
        final controls = await _nativeCameraBridge.controlState(rendererId);
        if (mounted) setState(() => _cameraControls = controls);
      }
      return;
    }

    final current = _activeCamera;
    if (current == null) return;
    final currentIndex = _cameras.indexOf(current);
    await _initializeCamera(_cameras[(currentIndex + 1) % _cameras.length]);
  }

  Future<void> _setFlashMode(NativeCameraFlashMode mode) async {
    if (_isCapturing || _cameraControls.torchEnabled || !_flashAvailable) {
      return;
    }
    final rendererId = _gpuRendererId;
    if (_useNativeGpu && rendererId != null) {
      if (!_supportsNativeDeviceControls) return;
      final controls = await _nativeCameraBridge.setFlashMode(rendererId, mode);
      if (mounted) setState(() => _cameraControls = controls);
      return;
    }
    final controller = _controller;
    if (controller == null) return;
    await _applyFallbackFlashMode(controller, mode);
    if (!mounted) return;
    setState(() {
      _cameraControls = NativeCameraControlState(
        lensDirection: _cameraControls.lensDirection,
        hasFlash: _cameraControls.hasFlash,
        hasTorch: _cameraControls.hasTorch,
        flashMode: mode,
        torchEnabled: false,
        mirrorEnabled: _cameraControls.mirrorEnabled,
      );
    });
  }

  Future<void> _cycleFlashMode() async {
    final next = switch (_cameraControls.flashMode) {
      NativeCameraFlashMode.off => NativeCameraFlashMode.auto,
      NativeCameraFlashMode.auto => NativeCameraFlashMode.on,
      NativeCameraFlashMode.on => NativeCameraFlashMode.off,
    };
    await _setFlashMode(next);
  }

  Future<void> _setTorchEnabled(bool enabled) async {
    if (_isCapturing || !_torchAvailable) return;
    final rendererId = _gpuRendererId;
    if (_useNativeGpu && rendererId != null) {
      if (!_supportsNativeDeviceControls) return;
      final controls = await _nativeCameraBridge.setTorchEnabled(
        rendererId,
        enabled,
      );
      if (mounted) setState(() => _cameraControls = controls);
      return;
    }
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller.setFlashMode(enabled ? FlashMode.torch : FlashMode.off);
    } on CameraException {
      if (!mounted) return;
      setState(() {
        _cameraControls = NativeCameraControlState(
          lensDirection: _cameraControls.lensDirection,
          hasFlash: _cameraControls.hasFlash,
          hasTorch: false,
          flashMode: _cameraControls.flashMode,
          torchEnabled: false,
          mirrorEnabled: _cameraControls.mirrorEnabled,
        );
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _cameraControls = NativeCameraControlState(
        lensDirection: _cameraControls.lensDirection,
        hasFlash: _cameraControls.hasFlash,
        hasTorch: _cameraControls.hasTorch,
        flashMode: enabled
            ? NativeCameraFlashMode.off
            : _cameraControls.flashMode,
        torchEnabled: enabled,
        mirrorEnabled: _cameraControls.mirrorEnabled,
      );
    });
  }

  Future<void> _setMirrorEnabled(bool enabled) async {
    final rendererId = _gpuRendererId;
    if (_useNativeGpu && rendererId != null) {
      if (!_supportsNativeDeviceControls) return;
      final controls = await _nativeCameraBridge.setMirrorEnabled(
        rendererId,
        enabled,
      );
      if (mounted) setState(() => _cameraControls = controls);
      return;
    }
    if (!mounted) return;
    setState(() {
      _cameraControls = NativeCameraControlState(
        lensDirection: _cameraControls.lensDirection,
        hasFlash: _cameraControls.hasFlash,
        hasTorch: _cameraControls.hasTorch,
        flashMode: _cameraControls.flashMode,
        torchEnabled: _cameraControls.torchEnabled,
        mirrorEnabled: enabled,
      );
    });
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
    await _lookCoordinator.flush();
    final look = _cameraLook;
    final path = await _nativeCameraBridge.capturePhoto(rendererId);
    if (!mounted) return;
    await _gpuBridge.pause(rendererId);
    if (!mounted) return;
    await _openEditor(path, look: look);
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
    final look = _cameraLook;
    await _detachAndDisposeController(showLoading: true);
    if (!mounted) return;
    await _openEditor(capture.path, look: look);
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
    await _openEditor(source.uri.toFilePath(), look: CameraLookState());
  }

  Future<void> _openEditor(String imagePath, {required CameraLookState look}) =>
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CameraFilmEditorHandoff(
            imagePath: imagePath,
            profileId: look.filmProfileId,
            strength: look.filmStrength,
            look: look,
          ),
        ),
      );

  void _submitCameraLook() {
    if (_useNativeGpu && _gpuRendererId != null) {
      _lookCoordinator.submit(_cameraLook);
    }
  }

  void _selectPreset(CameraFilmPreset preset) {
    final strength = preset.isOriginal ? 0.0 : 1.0;
    setState(() {
      _preset = preset;
      _strength = strength;
      _cameraLook = preset.isOriginal
          ? _cameraLook.clearFilm()
          : _cameraLook.withFilm(preset.id, strength);
    });
    _submitCameraLook();
  }

  void _setStrength(double value) {
    setState(() {
      _strength = value;
      _cameraLook = _cameraLook.withFilm(_preset.id, value);
    });
    _submitCameraLook();
  }

  void _selectCreativeFilter(String? filterId) {
    setState(() {
      _cameraLook = filterId == null
          ? _cameraLook.clearCreative()
          : _cameraLook.withCreative(filterId, 1);
    });
    _submitCameraLook();
  }

  void _setCreativeStrength(double value) {
    final filterId = _cameraLook.creativeFilterId;
    if (filterId.isEmpty) return;
    setState(() {
      _cameraLook = _cameraLook.withCreative(filterId, value);
    });
    _submitCameraLook();
  }

  void _selectAdjustment(String id) {
    setState(() => _selectedAdjustmentId = id);
  }

  void _setAdjustment(double value) {
    setState(() {
      _cameraLook = _cameraLook.withAdjustment(_selectedAdjustmentId, value);
    });
    _submitCameraLook();
  }

  void _selectTool(CameraPrimaryTool tool) {
    if (tool != CameraPrimaryTool.film && !_useNativeGpu) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('camera.native_look_required'.tr())),
      );
      return;
    }
    setState(() => _selectedTool = tool);
  }

  Future<void> _showCameraControls() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF111111),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          Future<void> refresh(Future<void> Function() action) async {
            await action();
            if (sheetContext.mounted) setSheetState(() {});
          }

          return SafeArea(
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
                  const SizedBox(height: 14),
                  Text(
                    'camera.flash'.tr(),
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<NativeCameraFlashMode>(
                    segments: [
                      ButtonSegment(
                        value: NativeCameraFlashMode.off,
                        label: Text('camera.flash_off'.tr()),
                      ),
                      ButtonSegment(
                        value: NativeCameraFlashMode.auto,
                        label: Text('camera.flash_auto'.tr()),
                      ),
                      ButtonSegment(
                        value: NativeCameraFlashMode.on,
                        label: Text('camera.flash_on'.tr()),
                      ),
                    ],
                    selected: {_cameraControls.flashMode},
                    onSelectionChanged:
                        _flashAvailable && !_cameraControls.torchEnabled
                        ? (selection) => unawaited(
                            refresh(() => _setFlashMode(selection.first)),
                          )
                        : null,
                    showSelectedIcon: false,
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile.adaptive(
                    value: _cameraControls.torchEnabled,
                    onChanged: _torchAvailable
                        ? (value) =>
                              unawaited(refresh(() => _setTorchEnabled(value)))
                        : null,
                    secondary: const Icon(Icons.flashlight_on_outlined),
                    title: Text('camera.torch'.tr()),
                  ),
                  SwitchListTile.adaptive(
                    value: _mirrorEnabled,
                    onChanged: _isFrontCamera
                        ? (value) =>
                              unawaited(refresh(() => _setMirrorEnabled(value)))
                        : null,
                    secondary: const Icon(Icons.flip_outlined),
                    title: Text('camera.mirror'.tr()),
                  ),
                  ListTile(
                    leading: const Icon(Icons.cameraswitch_outlined),
                    iconColor: Colors.white,
                    textColor: Colors.white,
                    title: Text('camera.switch_camera'.tr()),
                    enabled: _canSwitchCamera,
                    onTap: _canSwitchCamera
                        ? () async {
                            await _switchCamera();
                            if (sheetContext.mounted) setSheetState(() {});
                          }
                        : null,
                  ),
                ],
              ),
            ),
          );
        },
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
            if (_selectedTool == CameraPrimaryTool.filter)
              _buildFilterControls(),
            if (_selectedTool == CameraPrimaryTool.adjust)
              _buildAdjustControls(),
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

    Widget preview = ColorFiltered(
      colorFilter: _preset.colorFilter(_strength),
      child: CameraPreview(controller),
    );
    if (_isFrontCamera && _mirrorEnabled) {
      preview = Transform(
        alignment: Alignment.center,
        transform: Matrix4.diagonal3Values(-1, 1, 1),
        child: preview,
      );
    }
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

  IconData get _flashIcon => switch (_cameraControls.flashMode) {
    NativeCameraFlashMode.off => Icons.flash_off,
    NativeCameraFlashMode.auto => Icons.flash_auto,
    NativeCameraFlashMode.on => Icons.flash_on,
  };

  Widget _buildTopBar() {
    final flashEnabled =
        _flashAvailable && !_cameraControls.torchEnabled && !_isCapturing;
    return Positioned(
      left: 12,
      right: 12,
      top: 8,
      child: Row(
        children: [
          SizedBox.square(
            dimension: 44,
            child: IconButton.filledTonal(
              key: const Key('camera-flash'),
              tooltip: 'camera.flash'.tr(),
              onPressed: flashEnabled
                  ? () => unawaited(_cycleFlashMode())
                  : null,
              icon: Icon(_flashIcon),
              style: IconButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.black54,
                disabledForegroundColor: Colors.white30,
                disabledBackgroundColor: Colors.black26,
              ),
            ),
          ),
          const Spacer(),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Text(
                kDebugMode
                    ? (_useNativeGpu
                          ? 'camera.gpu_look_preview'.tr()
                          : 'camera.film_preview'.tr())
                    : 'Dxtr Pixs',
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
          SizedBox.square(
            dimension: 44,
            child: IconButton.filledTonal(
              key: const Key('camera-switch'),
              tooltip: 'camera.switch_camera'.tr(),
              onPressed: _canSwitchCamera && !_isCapturing
                  ? () => unawaited(_switchCamera())
                  : null,
              icon: const Icon(Icons.cameraswitch_outlined),
              style: IconButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.black54,
                disabledForegroundColor: Colors.white30,
                disabledBackgroundColor: Colors.black26,
              ),
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration get _lookPanelDecoration => const BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Colors.transparent, Color(0xB3000000)],
    ),
  );

  Widget _buildFilmControls() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 156,
      child: DecoratedBox(
        decoration: _lookPanelDecoration,
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

  Widget _buildFilterControls() {
    final activeId = _cameraLook.creativeFilterId;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 156,
      child: DecoratedBox(
        decoration: _lookPanelDecoration,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 40, 0, 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                activeId.isEmpty
                    ? 'camera.original'.tr()
                    : 'camera.$activeId'.tr(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (activeId.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 44),
                  child: Slider(
                    value: _cameraLook.creativeFilterStrength,
                    min: 0,
                    max: 1,
                    onChanged: _isCapturing ? null : _setCreativeStrength,
                  ),
                )
              else
                const SizedBox(height: 12),
              SizedBox(
                height: 42,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: cameraCreativeFilters.length + 1,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final filter = index == 0
                        ? null
                        : cameraCreativeFilters[index - 1];
                    final id = filter?.id ?? '';
                    final selected = id == activeId;
                    return ChoiceChip(
                      selected: selected,
                      label: Text(
                        filter == null
                            ? 'camera.original'.tr()
                            : 'camera.${filter.id}'.tr(),
                      ),
                      onSelected: _isCapturing
                          ? null
                          : (_) => _selectCreativeFilter(filter?.id),
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

  Widget _buildAdjustControls() {
    final spec = cameraAdjustmentSpec(_selectedAdjustmentId);
    final value = _cameraLook.adjustmentValue(_selectedAdjustmentId);
    return Positioned(
      left: 0,
      right: 0,
      bottom: 156,
      child: DecoratedBox(
        decoration: _lookPanelDecoration,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 40, 0, 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${'camera.$_selectedAdjustmentId'.tr()}  ${value.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 44),
                child: Slider(
                  value: value,
                  min: spec.min,
                  max: spec.max,
                  onChanged: _isCapturing ? null : _setAdjustment,
                ),
              ),
              SizedBox(
                height: 42,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: _cameraAdjustmentIds.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final id = _cameraAdjustmentIds[index];
                    final selected = id == _selectedAdjustmentId;
                    return ChoiceChip(
                      selected: selected,
                      label: Text('camera.$id'.tr()),
                      onSelected: _isCapturing
                          ? null
                          : (_) => _selectAdjustment(id),
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
