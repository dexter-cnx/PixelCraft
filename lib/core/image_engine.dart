import 'dart:typed_data';

import '../src/rust/api.dart' as rust;

class EngineResult {
  const EngineResult({required this.bytes, required this.elapsedMicros});

  final Uint8List bytes;
  final BigInt elapsedMicros;
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
  Uint8List undo();
  Uint8List redo();
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
  Uint8List undo() => rust.undo();

  @override
  Uint8List redo() => rust.redo();
}
