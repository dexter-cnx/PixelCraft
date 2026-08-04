import 'dart:convert';
import 'dart:typed_data';

import 'package:pixelcraft/core/image_engine.dart';

/// Valid 1x1 PNG used by widget and golden tests.
///
/// Keeping the fixture inline avoids file-system and asset-loading variance in
/// tests while still exercising Flutter's real image decoder.
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
  String? activeFilter;
  double? lastValue;

  final List<int> bins = List<int>.generate(768, (index) => index % 256);

  @override
  void loadImage(Uint8List bytes) {
    loadCalls++;
    if (failLoad) throw StateError('decode failed');
  }

  @override
  Uint8List preparePreview(Uint8List bytes, {required int maxEdge}) => output;

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
    return output;
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

  @override
  Uint8List undo() {
    undoCalls++;
    return output;
  }

  @override
  Uint8List redo() {
    redoCalls++;
    return output;
  }
}
