import 'dart:async';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../app/platform_flow_foundation.dart';
import '../app/platform_media_services.dart';
import '../gpu/native_gpu_preview_bridge.dart';
import 'camera_capture_pipeline.dart';
import 'camera_image_ratio.dart';
import 'camera_look_state.dart';
import 'camera_recent_thumbnail.dart';

/// Executes the authoritative PF7 capture transaction.
///
/// The widget owns only frozen-still presentation and navigation. The default
/// transaction owns source I/O, Rust rendering, Gallery delivery, and cleanup.
abstract interface class CameraCaptureHandoffTransaction {
  Future<CameraCaptureResult> execute({
    required String imagePath,
    required CameraLookState look,
    required CameraImageRatio imageRatio,
    required CameraCaptureOrientation captureOrientation,
    required double zoomFactor,
    void Function(ProcessingJobPhase phase)? onPhase,
  });

  Future<void> cleanupSource(String imagePath);
}

class DefaultCameraCaptureHandoffTransaction
    implements CameraCaptureHandoffTransaction {
  const DefaultCameraCaptureHandoffTransaction({
    this.renderer = const RustCameraCaptureRenderer(),
    this.saveService = const GalleryMediaSaveService(),
  });

  final CameraCaptureRenderer renderer;
  final MediaSaveService saveService;

  @override
  Future<CameraCaptureResult> execute({
    required String imagePath,
    required CameraLookState look,
    required CameraImageRatio imageRatio,
    required CameraCaptureOrientation captureOrientation,
    required double zoomFactor,
    void Function(ProcessingJobPhase phase)? onPhase,
  }) async {
    final sourceBytes = await File(imagePath).readAsBytes();
    final pipeline = CameraCapturePipeline(
      renderer: renderer,
      saveService: saveService,
    );
    return pipeline.processAndSave(
      sourceJpeg: sourceBytes,
      look: look,
      imageRatio: imageRatio,
      captureOrientation: captureOrientation,
      zoomFactor: zoomFactor,
      onPhase: onPhase,
    );
  }

  @override
  Future<void> cleanupSource(String imagePath) async {
    try {
      final source = File(imagePath);
      if (await source.exists()) await source.delete();
    } catch (_) {}
  }
}

/// PF3/PF7/PF9 camera-capture processing handoff.
///
/// The clean captured JPEG remains visible while authoritative processing and
/// Gallery delivery run. PF9 also suspends any tracked native GPU preview for
/// the lifetime of this route so hidden Metal/OpenGL rendering does not keep
/// running underneath the frozen captured still.
class CameraCaptureSaveHandoff extends StatefulWidget {
  const CameraCaptureSaveHandoff({
    super.key,
    required this.imagePath,
    required this.look,
    this.imageRatio = CameraImageRatio.original,
    this.captureOrientation = CameraCaptureOrientation.auto,
    this.zoomFactor = 1,
    this.transaction,
  });

  final String imagePath;
  final CameraLookState look;
  final CameraImageRatio imageRatio;
  final CameraCaptureOrientation captureOrientation;
  final double zoomFactor;
  final CameraCaptureHandoffTransaction? transaction;

  @override
  State<CameraCaptureSaveHandoff> createState() =>
      _CameraCaptureSaveHandoffState();
}

enum _CaptureHandoffPhase { processing, saving, completed, failed }

class _CameraCaptureSaveHandoffState extends State<CameraCaptureSaveHandoff> {
  bool _started = false;
  bool _previewSuspensionAcquired = false;
  _CaptureHandoffPhase _phase = _CaptureHandoffPhase.processing;

  bool get _canLeave =>
      _phase == _CaptureHandoffPhase.completed ||
      _phase == _CaptureHandoffPhase.failed;

  CameraCaptureHandoffTransaction get _transaction =>
      widget.transaction ?? const DefaultCameraCaptureHandoffTransaction();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _previewSuspensionAcquired = true;
    unawaited(NativeGpuPreviewSuspension.acquire());

    final messenger = ScaffoldMessenger.of(context);
    scheduleMicrotask(() {
      unawaited(_process(messenger: messenger));
    });
  }

  @override
  void dispose() {
    if (_previewSuspensionAcquired) {
      _previewSuspensionAcquired = false;
      unawaited(NativeGpuPreviewSuspension.release());
    }
    super.dispose();
  }

  Future<void> _process({required ScaffoldMessengerState messenger}) async {
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
      final result = await _transaction.execute(
        imagePath: widget.imagePath,
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
      if (!mounted) return;

      setState(() => _phase = _CaptureHandoffPhase.completed);
      const visibleFor = Duration(milliseconds: 900);
      show('camera.capture_saved'.tr(), duration: visibleFor);
      await Future<void>.delayed(visibleFor);
      if (!mounted) return;

      messenger.removeCurrentSnackBar();
      Navigator.of(context).pop();
      unawaited(_transaction.cleanupSource(widget.imagePath));
    } catch (_) {
      if (!mounted) return;
      setState(() => _phase = _CaptureHandoffPhase.failed);
      show(
        'camera.capture_failed'.tr(),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: 'camera.try_again'.tr(),
          onPressed: () => unawaited(_process(messenger: messenger)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _canLeave,
    onPopInvokedWithResult: (didPop, _) {
      if (didPop && _phase == _CaptureHandoffPhase.failed) {
        unawaited(_transaction.cleanupSource(widget.imagePath));
      }
    },
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
