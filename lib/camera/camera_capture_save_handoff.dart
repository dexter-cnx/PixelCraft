import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../app/platform_flow_foundation.dart';
import '../app/platform_media_services.dart';
import 'camera_capture_pipeline.dart';
import 'camera_look_state.dart';

/// PF3 camera-capture destination.
///
/// Clean camera JPEG -> Rust full-resolution CameraLook render -> system
/// Gallery -> return to Camera. Preview framebuffer pixels are never used as
/// saved-output authority.
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
  ProcessingJobPhase _phase = ProcessingJobPhase.processing;
  Object? _error;

  late final CameraCapturePipeline _pipeline = CameraCapturePipeline(
    renderer: widget.captureRenderer ?? const RustCameraCaptureRenderer(),
    saveService: widget.mediaSaveService ?? const GalleryMediaSaveService(),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _process());
  }

  Future<void> _deleteSourceBestEffort() async {
    try {
      final source = File(widget.imagePath);
      if (await source.exists()) await source.delete();
    } catch (_) {
      // Temporary-source cleanup failure must not invalidate a saved result.
    }
  }

  Future<void> _process() async {
    if (!mounted) return;
    setState(() {
      _phase = ProcessingJobPhase.processing;
      _error = null;
    });

    try {
      final sourceBytes = await File(widget.imagePath).readAsBytes();
      final result = await _pipeline.processAndSave(
        sourceJpeg: sourceBytes,
        look: widget.look,
        onPhase: (phase) {
          if (mounted) setState(() => _phase = phase);
        },
      );

      await _deleteSourceBestEffort();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('camera.capture_saved'.tr())),
      );
      Navigator.of(context).pop(result.savedUri);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = ProcessingJobPhase.failed;
        _error = error;
      });
    }
  }

  Future<void> _cancel() async {
    await _deleteSourceBestEffort();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final failed = _phase == ProcessingJobPhase.failed;
    final label = switch (_phase) {
      ProcessingJobPhase.processing => 'camera.processing_photo'.tr(),
      ProcessingJobPhase.saving => 'camera.saving_photo'.tr(),
      ProcessingJobPhase.completed => 'camera.capture_saved'.tr(),
      ProcessingJobPhase.failed => 'camera.capture_failed'.tr(),
      ProcessingJobPhase.idle => 'camera.processing_photo'.tr(),
    };

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!failed)
                  const CircularProgressIndicator()
                else
                  const Icon(
                    Icons.error_outline,
                    color: Colors.white70,
                    size: 48,
                  ),
                const SizedBox(height: 20),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (failed) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error?.toString() ?? '',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white54),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: _cancel,
                        child: Text('camera.cancel'.tr()),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        onPressed: _process,
                        child: Text('camera.try_again'.tr()),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
