import 'dart:convert';
import 'dart:typed_data';

import 'package:pixelcraft/core/image_engine.dart';

final Uint8List testPngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

class FakeImageEngine implements ImageEngine {
  FakeImageEngine({Uint8List? output}) : output = output ?? testPngBytes;

  Uint8List output;
  bool failLoad = false;
  int loadCalls = 0;
  int beginCalls = 0;
  int previewCalls = 0;
  int commitCalls = 0;
  int undoCalls = 0;
  int redoCalls = 0;
  int exportCalls = 0;
  int transformCalls = 0;
  int cursor = 0;
  int operationCount = 0;
  String? activeFilter;
  double? lastValue;

  final List<int> bins = List<int>.generate(768, (index) => index % 256);

  @override
  void loadImage(Uint8List bytes) {
    loadCalls++;
    if (failLoad) throw StateError('decode failed');
    cursor = 0;
    operationCount = 0;
  }

  @override
  Uint8List preparePreview(Uint8List bytes, {required int maxEdge}) => output;

  @override
  Uint8List originalPreview() => output;

  @override
  List<int> getHistogram(Uint8List bytes) => bins;

  @override
  void beginFilter(String filter) {
    beginCalls++;
    activeFilter = filter;
  }

  @override
  EngineResult updateFilterPreview(String filter, double value) {
    previewCalls++;
    activeFilter = filter;
    lastValue = value;
    return EngineResult(bytes: output, elapsedMicros: BigInt.from(12500));
  }

  @override
  Uint8List commitFilter() {
    commitCalls++;
    return _commitTransform();
  }

  @override
  Uint8List cancelFilter() => output;

  @override
  EngineResult applyFilterTimed(
    Uint8List bytes,
    String filter,
    double value,
  ) =>
      EngineResult(bytes: output, elapsedMicros: BigInt.from(8000));

  Uint8List _commitTransform() {
    transformCalls++;
    operationCount = cursor + 1;
    cursor = operationCount;
    return output;
  }

  @override
  Uint8List applyCrop({required double x, required double y, required double width, required double height}) => _commitTransform();

  @override
  Uint8List rotateQuarterTurns(int turns) => _commitTransform();

  @override
  Uint8List straighten(double degrees) => _commitTransform();

  @override
  Uint8List flipHorizontal() => _commitTransform();

  @override
  Uint8List flipVertical() => _commitTransform();

  @override
  Uint8List resizeCommitted({required int width, required int height}) => _commitTransform();

  @override
  Uint8List undo() {
    undoCalls++;
    if (cursor > 0) cursor--;
    return output;
  }

  @override
  Uint8List redo() {
    redoCalls++;
    if (cursor < operationCount) cursor++;
    return output;
  }

  @override
  EngineSessionInfo sessionInfo() => EngineSessionInfo(
        version: 1,
        operationCount: operationCount,
        cursor: cursor,
        canUndo: cursor > 0,
        canRedo: cursor < operationCount,
      );

  @override
  Uint8List exportImage({required String format, required int quality}) {
    exportCalls++;
    return output;
  }
}
