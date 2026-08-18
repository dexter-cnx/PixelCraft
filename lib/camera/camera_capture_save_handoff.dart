import 'dart:async';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../app/platform_flow_foundation.dart';
import '../app/platform_media_services.dart';
import 'camera_capture_pipeline.dart';
import 'camera_look_state.dart';
import 'camera_recent_thumbnail.dart';

/// PF3 transient camera-capture trigger.
///
/// This route pops immediately, then completes authoritative processing/save in
/// the background while feedback is shown through the Camera ScaffoldMessenger.
class CameraCaptureSaveHandoff extends StatefulWidget {
  const CameraCaptureSaveHandoff({
    super.key,
    required this.imagePath,
    required this.look,
    this.captureRenderer,
    this.mediaSaveService,
  });

  final String imagePath;
  final CameraLookState look;
  final CameraCaptureRenderer? captureRenderer;
  final MediaSaveService? mediaSaveService;

  @override
  State<CameraCaptureSaveHandoff> createState() =>
      _CameraCaptureSaveHandoffState();
}

class _CameraCaptureSaveHandoffState extends State<CameraCaptureSaveHandoff> {
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final imagePath = widget.imagePath;
    final look = widget.look;
    final pipeline = CameraCapturePipeline(
      renderer: widget.captureRenderer ?? const RustCameraCaptureRenderer(),
      saveService: widget.mediaSaveService ?? const GalleryMediaSaveService(),
    );

    scheduleMicrotask(() {
      navigator.pop();
      unawaited(
        _process(
          messenger: messenger,
          pipeline: pipeline,
          imagePath: imagePath,
          look: look,
        ),
      );
    });
  }

  Future<void> _process({
    required ScaffoldMessengerState messenger,
    required CameraCapturePipeline pipeline,
    required String imagePath,
    required CameraLookState look,
  }) async {
    void show(
      String message, {
      Duration duration = const Duration(seconds: 2),
      SnackBarAction? action,
    }) {
      // Camera status is a single live slot, not a Snackbar queue. Removing the
      // previous entry immediately avoids animated hide + queued display time.
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

    void showSaved() {
      const visibleFor = Duration(milliseconds: 900);
      show('camera.capture_saved'.tr(), duration: visibleFor);
      // Keep success feedback deterministic even if platform accessibility or
      // animation timing extends the framework Snackbar timer.
      unawaited(
        Future<void>.delayed(visibleFor, () {
          messenger.removeCurrentSnackBar();
        }),
      );
    }

    show('camera.processing_photo'.tr(), duration: const Duration(minutes: 2));

    try {
      final sourceBytes = await File(imagePath).readAsBytes();
      final result = await pipeline.processAndSave(
        sourceJpeg: sourceBytes,
        look: look,
        onPhase: (phase) {
          if (phase == ProcessingJobPhase.saving) {
            show(
              'camera.saving_photo'.tr(),
              duration: const Duration(minutes: 2),
            );
          }
        },
      );
      CameraRecentThumbnail.instance.update(result.jpegBytes);
      await _deleteSourceBestEffort(imagePath);
      showSaved();
    } catch (_) {
      show(
        'camera.capture_failed'.tr(),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: 'camera.try_again'.tr(),
          onPressed: () => unawaited(
            _process(
              messenger: messenger,
              pipeline: pipeline,
              imagePath: imagePath,
              look: look,
            ),
          ),
        ),
      );
    }
  }

  Future<void> _deleteSourceBestEffort(String imagePath) async {
    try {
      final source = File(imagePath);
      if (await source.exists()) await source.delete();
    } catch (_) {
      // Temporary-source cleanup failure must not invalidate a saved result.
    }
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(backgroundColor: Colors.black, body: SizedBox.expand());
}
