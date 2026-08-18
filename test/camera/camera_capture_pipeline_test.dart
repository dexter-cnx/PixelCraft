import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcraft/app/platform_flow_foundation.dart';
import 'package:pixelcraft/camera/camera_capture_pipeline.dart';
import 'package:pixelcraft/camera/camera_image_ratio.dart';
import 'package:pixelcraft/camera/camera_look_state.dart';

void main() {
  test('PF3 renders clean capture before saving authoritative JPEG', () async {
    final renderer = _FakeRenderer(Uint8List.fromList([9, 8, 7]));
    final saver = _FakeSaveService();
    final phases = <ProcessingJobPhase>[];
    final look = CameraLookState()
        .withAdjustment('exposure', 0.75)
        .withFilm('provia_inspired', 0.8)
        .withCreative('vintage', 0.6);
    final source = Uint8List.fromList([1, 2, 3, 4]);

    final result =
        await CameraCapturePipeline(
          renderer: renderer,
          saveService: saver,
        ).processAndSave(
          sourceJpeg: source,
          look: look,
          imageRatio: CameraImageRatio.threeTwo,
          captureOrientation: CameraCaptureOrientation.landscape,
          suggestedName: 'capture.jpg',
          onPhase: phases.add,
        );

    expect(renderer.source, same(source));
    expect(renderer.look, same(look));
    expect(renderer.imageRatio, CameraImageRatio.threeTwo);
    expect(renderer.captureOrientation, CameraCaptureOrientation.landscape);
    expect(saver.bytes, orderedEquals([9, 8, 7]));
    expect(saver.suggestedName, 'capture.jpg');
    expect(result.savedUri, Uri.parse('media:/gallery/capture.jpg'));
    expect(result.jpegBytes, orderedEquals([9, 8, 7]));
    expect(phases, [
      ProcessingJobPhase.processing,
      ProcessingJobPhase.saving,
      ProcessingJobPhase.completed,
    ]);
  });

  test('PF3 never saves when authoritative render fails', () async {
    final saver = _FakeSaveService();
    final pipeline = CameraCapturePipeline(
      renderer: _ThrowingRenderer(),
      saveService: saver,
    );

    await expectLater(
      pipeline.processAndSave(
        sourceJpeg: Uint8List.fromList([1]),
        look: CameraLookState(),
      ),
      throwsA(isA<StateError>()),
    );

    expect(saver.bytes, isNull);
  });
}

class _FakeRenderer implements CameraCaptureRenderer {
  _FakeRenderer(this.output);

  final Uint8List output;
  Uint8List? source;
  CameraLookState? look;
  CameraImageRatio? imageRatio;
  CameraCaptureOrientation? captureOrientation;

  @override
  Future<Uint8List> renderJpeg({
    required Uint8List sourceJpeg,
    required CameraLookState look,
    CameraImageRatio imageRatio = CameraImageRatio.original,
    CameraCaptureOrientation captureOrientation =
        CameraCaptureOrientation.auto,
    int quality = 95,
  }) async {
    source = sourceJpeg;
    this.look = look;
    this.imageRatio = imageRatio;
    this.captureOrientation = captureOrientation;
    return output;
  }
}

class _ThrowingRenderer implements CameraCaptureRenderer {
  @override
  Future<Uint8List> renderJpeg({
    required Uint8List sourceJpeg,
    required CameraLookState look,
    CameraImageRatio imageRatio = CameraImageRatio.original,
    CameraCaptureOrientation captureOrientation =
        CameraCaptureOrientation.auto,
    int quality = 95,
  }) async {
    throw StateError('render failed');
  }
}

class _FakeSaveService implements MediaSaveService {
  Uint8List? bytes;
  String? suggestedName;

  @override
  Future<Uri> saveJpeg({
    required Uint8List bytes,
    String? suggestedName,
  }) async {
    this.bytes = bytes;
    this.suggestedName = suggestedName;
    return Uri.parse('media:/gallery/${suggestedName ?? 'capture.jpg'}');
  }
}
