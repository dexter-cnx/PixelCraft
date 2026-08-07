import 'dart:typed_data';

import '../src/rust/api.dart' as rust;

class EngineResult {
  const EngineResult({required this.bytes, required this.elapsedMicros});

  final Uint8List bytes;
  final BigInt elapsedMicros;
}

class EngineSessionInfo {
  const EngineSessionInfo({
    required this.version,
    required this.operationCount,
    required this.cursor,
    required this.canUndo,
    required this.canRedo,
  });

  final int version;
  final int operationCount;
  final int cursor;
  final bool canUndo;
  final bool canRedo;
}

abstract interface class ImageEngine {
  void loadImage(Uint8List bytes);
  Uint8List preparePreview(Uint8List bytes, {required int maxEdge});
  List<int> getHistogram(Uint8List bytes);
  void beginFilter(String filter);
  EngineResult updateFilterPreview(String filter, double value);
  Uint8List commitFilter();
  Uint8List cancelFilter();
  EngineResult applyFilterTimed(Uint8List bytes, String filter, double value);
  Uint8List applyCrop({
    required double x,
    required double y,
    required double width,
    required double height,
  });
  Uint8List rotateQuarterTurns(int turns);
  Uint8List straighten(double degrees);
  Uint8List flipHorizontal();
  Uint8List flipVertical();
  Uint8List resizeCommitted({required int width, required int height});
  Uint8List undo();
  Uint8List redo();
  EngineSessionInfo sessionInfo();
  Uint8List exportImage({required String format, required int quality});
  Uint8List originalPreview();
}

class RustImageEngine implements ImageEngine {
  const RustImageEngine();

  @override
  void loadImage(Uint8List bytes) => rust.loadImage(bytes: bytes);

  @override
  Uint8List preparePreview(Uint8List bytes, {required int maxEdge}) =>
      rust.preparePreview(imageBytes: bytes, maxEdge: maxEdge);

  @override
  List<int> getHistogram(Uint8List bytes) =>
      rust.getHistogram(imageBytes: bytes);

  @override
  void beginFilter(String filter) => rust.beginFilter(filter: filter);

  @override
  EngineResult updateFilterPreview(String filter, double value) {
    final result = rust.updateFilterPreview(filter: filter, value: value);
    return EngineResult(
      bytes: result.bytes,
      elapsedMicros: result.elapsedMicros,
    );
  }

  @override
  Uint8List commitFilter() => rust.commitFilter();

  @override
  Uint8List cancelFilter() => rust.cancelFilter();

  @override
  EngineResult applyFilterTimed(
    Uint8List bytes,
    String filter,
    double value,
  ) {
    final result = rust.applyFilterTimed(
      imageBytes: bytes,
      filter: filter,
      value: value,
    );
    return EngineResult(
      bytes: result.bytes,
      elapsedMicros: result.elapsedMicros,
    );
  }

  @override
  Uint8List applyCrop({
    required double x,
    required double y,
    required double width,
    required double height,
  }) =>
      rust.applyCrop(x: x, y: y, width: width, height: height);

  @override
  Uint8List rotateQuarterTurns(int turns) =>
      rust.rotateQuarterTurns(turns: turns);

  @override
  Uint8List straighten(double degrees) => rust.straighten(degrees: degrees);

  @override
  Uint8List flipHorizontal() => rust.flipHorizontal();

  @override
  Uint8List flipVertical() => rust.flipVertical();

  @override
  Uint8List resizeCommitted({required int width, required int height}) =>
      rust.resizeCommitted(width: width, height: height);

  @override
  Uint8List undo() => rust.undo();

  @override
  Uint8List redo() => rust.redo();

  @override
  EngineSessionInfo sessionInfo() {
    final info = rust.sessionInfo();
    return EngineSessionInfo(
      version: info.version,
      operationCount: info.operationCount,
      cursor: info.cursor,
      canUndo: info.canUndo,
      canRedo: info.canRedo,
    );
  }

  @override
  Uint8List exportImage({required String format, required int quality}) =>
      rust.exportImage(format: format, quality: quality);

  @override
  Uint8List originalPreview() => rust.originalPreview();
}
