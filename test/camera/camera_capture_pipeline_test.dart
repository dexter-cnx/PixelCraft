import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcraft/app/platform_flow_foundation.dart';
import 'package:pixelcraft/camera/camera_capture_pipeline.dart';
import 'package:pixelcraft/camera/camera_image_ratio.dart';
import 'package:pixelcraft/camera/camera_look_state.dart';

void main() {
  test('PF3 forwards orientation and zoom before authoritative save', () async {
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
          captureOrientation: CameraCaptureOrientation.landscapeLeft,
          zoomFactor: 2.25,
          suggestedName: 'capture.jpg',
          onPhase: phases.add,
        );

    expect(renderer.source, same(source));
    expect(renderer.look, same(look));
    expect(renderer.imageRatio, CameraImageRatio.threeTwo);
    expect(renderer.captureOrientation, CameraCaptureOrientation.landscapeLeft);
    expect(renderer.zoomFactor, 2.25);
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

  test('PF3 serializes complete authoritative render transactions', () async {
    final renderer = _SerialProbeRenderer();
    final firstPipeline = CameraCapturePipeline(
      renderer: renderer,
      saveService: _FakeSaveService(),
    );
    final secondPipeline = CameraCapturePipeline(
      renderer: renderer,
      saveService: _FakeSaveService(),
    );

    final first = firstPipeline.processAndSave(
      sourceJpeg: Uint8List.fromList([1]),
      look: CameraLookState(),
    );
    await renderer.firstStarted.future;

    final second = secondPipeline.processAndSave(
      sourceJpeg: Uint8List.fromList([2]),
      look: CameraLookState(),
    );
    await Future<void>.delayed(Duration.zero);

    expect(renderer.invocations, 1);
    expect(renderer.maxActive, 1);

    renderer.releaseFirst.complete();
    await Future.wait([first, second]);

    expect(renderer.invocations, 2);
    expect(renderer.maxActive, 1);
  });
}

class _FakeRenderer implements CameraCaptureRenderer {
  _FakeRenderer(this.output);

  final Uint8List output;
  Uint8List? source;
  CameraLookState? look;
  CameraImageRatio? imageRatio;
  CameraCaptureOrientation? captureOrientation;
  double? zoomFactor;

  @override
  Future<Uint8List> renderJpeg({
    required Uint8List sourceJpeg,
    required CameraLookState look,
    CameraImageRatio imageRatio = CameraImageRatio.original,
    CameraCaptureOrientation captureOrientation = CameraCaptureOrientation.auto,
    double zoomFactor = 1,
    int quality = 95,
  }) async {
    source = sourceJpeg;
    this.look = look;
    this.imageRatio = imageRatio;
    this.captureOrientation = captureOrientation;
    this.zoomFactor = zoomFactor;
    return output;
  }
}

class _ThrowingRenderer implements CameraCaptureRenderer {
  @override
  Future<Uint8List> renderJpeg({
    required Uint8List sourceJpeg,
    required CameraLookState look,
    CameraImageRatio imageRatio = CameraImageRatio.original,
    CameraCaptureOrientation captureOrientation = CameraCaptureOrientation.auto,
    double zoomFactor = 1,
    int quality = 95,
  }) async {
    throw StateError('render failed');
  }
}

class _SerialProbeRenderer implements CameraCaptureRenderer {
  final firstStarted = Completer<void>();
  final releaseFirst = Completer<void>();

  int invocations = 0;
  int active = 0;
  int maxActive = 0;

  @override
  Future<Uint8List> renderJpeg({
    required Uint8List sourceJpeg,
    required CameraLookState look,
    CameraImageRatio imageRatio = CameraImageRatio.original,
    CameraCaptureOrientation captureOrientation = CameraCaptureOrientation.auto,
    double zoomFactor = 1,
    int quality = 95,
  }) async {
    invocations += 1;
    active += 1;
    if (active > maxActive) maxActive = active;
    try {
      if (invocations == 1) {
        firstStarted.complete();
        await releaseFirst.future;
      }
      return Uint8List.fromList(sourceJpeg);
    } finally {
      active -= 1;
    }
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
