import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../camera/camera_film_editor_handoff.dart';
import '../../camera/camera_film_presets.dart';

class CameraFilmPreviewScreen extends StatefulWidget {
  const CameraFilmPreviewScreen({super.key});

  @override
  State<CameraFilmPreviewScreen> createState() =>
      _CameraFilmPreviewScreenState();
}

class _CameraFilmPreviewScreenState extends State<CameraFilmPreviewScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  CameraDescription? _activeCamera;
  CameraFilmPreset _preset = cameraFilmPresets.first;
  double _strength = 1;
  bool _isInitializing = true;
  bool _isCapturing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_discoverAndInitialize());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_disposeController());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final camera = _activeCamera;
    if (camera == null) return;

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(_disposeController());
    } else if (state == AppLifecycleState.resumed && _controller == null) {
      unawaited(_initializeCamera(camera));
    }
  }

  Future<void> _discoverAndInitialize() async {
    try {
      final cameras = await availableCameras();
      if (!mounted) return;
      if (cameras.isEmpty) {
        setState(() {
          _isInitializing = false;
          _error = 'No camera is available on this device.';
        });
        return;
      }

      _cameras = cameras;
      final rear = cameras.where(
        (camera) => camera.lensDirection == CameraLensDirection.back,
      );
      final selected = rear.isNotEmpty ? rear.first : cameras.first;
      await _initializeCamera(selected);
    } on CameraException catch (error) {
      _showCameraError(error);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isInitializing = false;
        _error = 'Unable to start camera: $error';
      });
    }
  }

  Future<void> _initializeCamera(CameraDescription camera) async {
    if (!mounted) return;
    setState(() {
      _isInitializing = true;
      _error = null;
    });

    final previous = _controller;
    _controller = null;
    if (previous != null) {
      await previous.dispose();
    }

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
      });
    } on CameraException catch (error) {
      await controller.dispose();
      _showCameraError(error);
    }
  }

  Future<void> _disposeController() async {
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      await controller.dispose();
    }
  }

  void _showCameraError(CameraException error) {
    if (!mounted) return;
    final message = switch (error.code) {
      'CameraAccessDenied' =>
        'Camera access was denied. Allow camera access in system settings to use Film Camera.',
      'CameraAccessDeniedWithoutPrompt' =>
        'Camera access is disabled. Enable it in system settings to use Film Camera.',
      'CameraAccessRestricted' =>
        'Camera access is restricted on this device.',
      _ => 'Unable to start camera: ${error.description ?? error.code}',
    };
    setState(() {
      _isInitializing = false;
      _error = message;
    });
  }

  Future<void> _switchCamera() async {
    if (_isCapturing || _cameras.length < 2 || _activeCamera == null) return;

    final currentIndex = _cameras.indexOf(_activeCamera!);
    final next = _cameras[(currentIndex + 1) % _cameras.length];
    await _initializeCamera(next);
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        controller.value.isTakingPicture ||
        _isCapturing) {
      return;
    }

    setState(() => _isCapturing = true);
    try {
      final capture = await controller.takePicture();
      if (!mounted) return;

      final profileId = _preset.id;
      final strength = _strength;
      await _disposeController();
      if (!mounted) return;

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CameraFilmEditorHandoff(
            imagePath: capture.path,
            profileId: profileId,
            strength: strength,
          ),
        ),
      );

      if (!mounted) return;
      final camera = _activeCamera;
      if (camera != null) {
        await _initializeCamera(camera);
      }
    } on CameraException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Capture failed: ${error.description ?? error.code}'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Capture failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  void _selectPreset(CameraFilmPreset preset) {
    setState(() {
      _preset = preset;
      _strength = preset.isOriginal ? 0 : 1;
    });
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
            _buildFilmControls(),
            if (_isCapturing)
              const Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(color: Color(0x33000000)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildViewfinder() {
    final controller = _controller;
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_outlined,
                  color: Colors.white70, size: 48),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 20),
              FilledButton.tonal(
                onPressed: _discoverAndInitialize,
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }

    if (_isInitializing || controller == null || !controller.value.isInitialized) {
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
          _CameraCircleButton(
            tooltip: 'Back',
            icon: Icons.close,
            onPressed: () => Navigator.maybePop(context),
          ),
          const Spacer(),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Text(
                'FILM PREVIEW',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
          const Spacer(),
          _CameraCircleButton(
            tooltip: 'Switch camera',
            icon: Icons.cameraswitch_outlined,
            onPressed: _cameras.length > 1 ? _switchCamera : null,
          ),
        ],
      ),
    );
  }

  Widget _buildFilmControls() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Color(0xE6000000)],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 72, 0, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _preset.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  _preset.isOriginal
                      ? _preset.description
                      : '${_preset.description} · ${(100 * _strength).round()}%',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
              if (!_preset.isOriginal) ...[
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 44),
                  child: SliderTheme(
                    data: SliderThemeData(
                      activeTrackColor: Colors.white,
                      inactiveTrackColor: Colors.white30,
                      thumbColor: Colors.white,
                      overlayColor: Colors.white.withValues(alpha: 0.12),
                    ),
                    child: Slider(
                      value: _strength,
                      min: 0,
                      max: 1,
                      onChanged: _isCapturing
                          ? null
                          : (value) => setState(() => _strength = value),
                    ),
                  ),
                ),
              ] else
                const SizedBox(height: 16),
              SizedBox(
                height: 46,
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
                      onSelected: _isCapturing ? null : (_) => _selectPreset(preset),
                      selectedColor: Colors.white,
                      backgroundColor: Colors.black54,
                      side: BorderSide(
                        color: selected ? Colors.white : Colors.white38,
                      ),
                      labelStyle: TextStyle(
                        color: selected ? Colors.black : Colors.white,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      ),
                      showCheckmark: false,
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              Semantics(
                button: true,
                label: 'Take photo with ${_preset.name} preview',
                child: GestureDetector(
                  onTap: _isCapturing ? null : _capture,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(color: Colors.white70, width: 4),
                      boxShadow: const [
                        BoxShadow(color: Colors.black45, blurRadius: 12),
                      ],
                    ),
                    child: Center(
                      child: _isCapturing
                          ? const SizedBox.square(
                              dimension: 26,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.black,
                              ),
                            )
                          : Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.black12),
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CameraCircleButton extends StatelessWidget {
  const _CameraCircleButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      tooltip: tooltip,
      style: IconButton.styleFrom(
        backgroundColor: Colors.black54,
        foregroundColor: Colors.white,
        disabledBackgroundColor: Colors.black26,
        disabledForegroundColor: Colors.white30,
      ),
      onPressed: onPressed,
      icon: Icon(icon),
    );
  }
}
