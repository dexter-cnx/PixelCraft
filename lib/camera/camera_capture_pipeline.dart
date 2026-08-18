import 'dart:isolate';
import 'dart:typed_data';

import '../app/platform_flow_foundation.dart';
import '../core/bridge.dart';
import '../src/rust/api.dart' as rust;
import 'camera_image_ratio.dart';
import 'camera_look_state.dart';

/// Final-pixel PF3 renderer contract.
///
/// Implementations must render from the clean captured JPEG and must not use
/// preview framebuffer pixels as saved-output authority.
abstract interface class CameraCaptureRenderer {
  Future<Uint8List> renderJpeg({
    required Uint8List sourceJpeg,
    required CameraLookState look,
    CameraImageRatio imageRatio = CameraImageRatio.original,
    CameraCaptureOrientation captureOrientation =
        CameraCaptureOrientation.portrait,
    int quality = 95,
  });
}

/// Rust-authoritative PF3 renderer.
///
/// The complete render executes inside one background isolate so the full
/// CameraLook is committed to one Rust session in canonical order without
/// blocking Flutter UI work between individual operations.
class RustCameraCaptureRenderer implements CameraCaptureRenderer {
  const RustCameraCaptureRenderer();

  static const _adjustmentOrder = <String>[
    'exposure',
    'temperature',
    'tint',
    'brightness',
    'contrast',
    'saturation',
    'vignette',
  ];

  @override
  Future<Uint8List> renderJpeg({
    required Uint8List sourceJpeg,
    required CameraLookState look,
    CameraImageRatio imageRatio = CameraImageRatio.original,
    CameraCaptureOrientation captureOrientation =
        CameraCaptureOrientation.portrait,
    int quality = 95,
  }) {
    final adjustments = <String, double>{
      for (final id in _adjustmentOrder) id: look.adjustmentValue(id),
    };
    final filmProfileId = look.filmProfileId;
    final filmStrength = look.filmStrength;
    final creativeFilterId = look.creativeFilterId;
    final creativeFilterStrength = look.creativeFilterStrength;
    final crop = imageRatio.cropForJpeg(
      sourceJpeg,
      orientation: captureOrientation,
    );

    return Isolate.run(() async {
      await initializeRustBridge();
      rust.loadImage(bytes: sourceJpeg);

      // Ratio is an authoritative framing operation, not a stretched resize.
      // Apply it before CameraLook so spatial effects such as vignette are
      // evaluated against the final composition.
      if (crop != null &&
          (crop.x > 0 || crop.y > 0 || crop.width < 1 || crop.height < 1)) {
        rust.applyCrop(
          x: crop.x,
          y: crop.y,
          width: crop.width,
          height: crop.height,
        );
      }

      for (final id in _adjustmentOrder) {
        final value = adjustments[id]!;
        final neutral = cameraAdjustmentSpec(id).neutral;
        if ((value - neutral).abs() <= 0.000001) continue;
        rust.beginFilter(filter: id);
        rust.updateFilterPreview(filter: id, value: value);
        rust.commitFilter();
      }

      if (filmProfileId.isNotEmpty && filmStrength > 0) {
        rust.applyFilmProfile(id: filmProfileId, strength: filmStrength);
      }

      if (creativeFilterId.isNotEmpty && creativeFilterStrength > 0) {
        rust.beginFilter(filter: creativeFilterId);
        rust.updateFilterPreview(
          filter: creativeFilterId,
          value: creativeFilterStrength,
        );
        rust.commitFilter();
      }

      return rust.exportImage(
        format: 'jpeg',
        quality: quality.clamp(1, 100).toInt(),
      );
    });
  }
}

class CameraCaptureResult {
  const CameraCaptureResult({required this.savedUri, required this.jpegBytes});

  final Uri savedUri;
  final Uint8List jpegBytes;
}

/// PF3 clean-capture -> Rust render -> system Gallery pipeline.
class CameraCapturePipeline {
  const CameraCapturePipeline({
    required CameraCaptureRenderer renderer,
    required MediaSaveService saveService,
  }) : this._(renderer, saveService);

  const CameraCapturePipeline._(this._renderer, this._saveService);

  final CameraCaptureRenderer _renderer;
  final MediaSaveService _saveService;

  Future<CameraCaptureResult> processAndSave({
    required Uint8List sourceJpeg,
    required CameraLookState look,
    CameraImageRatio imageRatio = CameraImageRatio.original,
    CameraCaptureOrientation captureOrientation =
        CameraCaptureOrientation.portrait,
    String? suggestedName,
    void Function(ProcessingJobPhase phase)? onPhase,
  }) async {
    onPhase?.call(ProcessingJobPhase.processing);
    final rendered = await _renderer.renderJpeg(
      sourceJpeg: sourceJpeg,
      look: look,
      imageRatio: imageRatio,
      captureOrientation: captureOrientation,
    );

    onPhase?.call(ProcessingJobPhase.saving);
    final uri = await _saveService.saveJpeg(
      bytes: rendered,
      suggestedName: suggestedName,
    );

    onPhase?.call(ProcessingJobPhase.completed);
    return CameraCaptureResult(savedUri: uri, jpegBytes: rendered);
  }
}
