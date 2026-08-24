import 'dart:async';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../app/platform_flow_foundation.dart';
import '../app/platform_media_services.dart';
import 'camera_capture_pipeline.dart';
import 'camera_image_ratio.dart';
import 'camera_look_state.dart';
import 'camera_recent_thumbnail.dart';

/// PF3/PF7 camera-capture processing handoff.
///
/// The clean captured JPEG remains visible while authoritative processing and
/// Gallery delivery run. This prevents the live preview from resuming before
/// the shutter transaction has completed.
class CameraCaptureSaveHandoff extends StatefulWidget {
  const CameraCaptureSaveHandoff({
    super.key,
    required this.imagePath,
    required this.look,
    this.imageRatio = CameraImageRatio.original,
    this.captureOrientation = CameraCaptureOrientation.auto,
    this.zoomFactor = 1,
    this.captureRenderer,
    this.mediaSaveService,
  });

  final String imagePath;
  final CameraLookState look;
  final CameraImageRatio imageRatio;
  final CameraCaptureOrientation captureOrientation;
  final double zoomFactor;
  final CameraCaptureRenderer? captureRenderer;
  final MediaSaveService? mediaSaveService;

  @override
  State<CameraCaptureSaveHandoff> createState() =>
      _CameraCaptureSaveHandoffState();
}

enum _CaptureHandoffPhase { processing, saving, completed, failed }

class _CameraCaptureSaveHandoffState extends State<CameraCaptureSaveHandoff> {
  bool _started = false;
  _CaptureHandoffPhase _phase = _CaptureHandoffPhase.processing;

  bool get _canLeave => _phase == _CaptureHandoffPhase.failed;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    final messenger = ScaffoldMessenger.of(context);
    final pipeline = CameraCapturePipeline(
      renderer: widget.captureRenderer ?? const RustCameraCaptureRenderer(),
      saveService: widget.mediaSaveService ?? const GalleryMediaSaveService(),
    );

    scheduleMicrotask(() {
      unawaited(_process(messenger: messenger, pipeline: pipeline));
    });
  }

  Future<void> _process({
    required ScaffoldMessengerState messenger,
    required CameraCapturePipeline pipeline,
  }) async {
    if (mounted) {
      setState(() => _phase = _CaptureHandoffPhase.processing);
    }

    void show(
      String message, {
      Duration duration = const Duration(seconds: 2),
      SnackBarAction? action,
    }) {
      messenger
        ..removeCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(message),
            duration: duration,
            action: action,
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.black.withValues(alpha: 0.72),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
            ),
          ),
        );
    }

    show('camera.processing_photo'.tr(), duration: const Duration(minutes: 2));

    try {
      final sourceBytes = await File(widget.imagePath).readAsBytes();
      final result = await pipeline.processAndSave(
        sourceJpeg: sourceBytes,
        look: widget.look,
        imageRatio: widget.imageRatio,
        captureOrientation: widget.captureOrientation,
        zoomFactor: widget.zoomFactor,
        onPhase: (phase) {
          if (phase != ProcessingJobPhase.saving) return;
          if (mounted) {
            setState(() => _phase = _CaptureHandoffPhase.saving);
          }
          show(
            'camera.saving_photo'.tr(),
            duration: const Duration(minutes: 2),
          );
        },
      );
      CameraRecentThumbnail.instance.update(result.jpegBytes);
      await _deleteSourceBestEffort(widget.imagePath);
      if (!mounted) return;

      setState(() => _phase = _CaptureHandoffPhase.completed);
      const visibleFor = Duration(milliseconds: 900);
      show('camera.capture_saved'.tr(), duration: visibleFor);
      await Future<void>.delayed(visibleFor);
      if (!mounted) return;
      messenger.removeCurrentSnackBar();
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _phase = _CaptureHandoffPhase.failed);
      show(
        'camera.capture_failed'.tr(),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: 'camera.try_again'.tr(),
          onPressed: () =>
              unawaited(_process(messenger: messenger, pipeline: pipeline)),
        ),
      );
    }
  }

  Future<void> _deleteSourceBestEffort(String imagePath) async {
    try {
      final source = File(imagePath);
      if (await source.exists()) await source.delete();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _canLeave,
    child: Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: Image.file(
              File(widget.imagePath),
              key: const ValueKey('camera_capture_frozen_still'),
              fit: BoxFit.contain,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => const SizedBox.expand(),
            ),
          ),
          if (_phase == _CaptureHandoffPhase.processing ||
              _phase == _CaptureHandoffPhase.saving)
            const IgnorePointer(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: SafeArea(
                  minimum: EdgeInsets.only(bottom: 24),
                  child: SizedBox.square(
                    dimension: 28,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
