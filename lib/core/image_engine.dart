import 'dart:isolate';
import 'dart:typed_data';

import '../src/rust/api.dart' as rust;
import 'bridge.dart';

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

class EngineCommitResult {
  const EngineCommitResult({
    required this.bytes,
    required this.histogram,
    required this.elapsedMicros,
    required this.session,
  });

  final Uint8List bytes;
  final List<int> histogram;
  final BigInt elapsedMicros;
  final EngineSessionInfo session;
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

  Future<Map<String, Uint8List>> generateFilterPreviews(
    Uint8List bytes,
    List<String> filters, {
    int maxEdge = 180,
  });
  Future<EngineCommitResult> commitFilterValue(String filter, double value);
  Future<EngineCommitResult> replaceFilterValue(String filter, double value);
  Future<EngineCommitResult> applyEditsInBackground();
  Future<EngineCommitResult> applyCropInBackground({
    required double x,
    required double y,
    required double width,
    required double height,
  });
  Future<EngineCommitResult> rotateQuarterTurnsInBackground(int turns);
  Future<EngineCommitResult> straightenInBackground(double degrees);
  Future<EngineCommitResult> flipHorizontalInBackground();
  Future<EngineCommitResult> flipVerticalInBackground();
  Future<EngineCommitResult> resizeCommittedInBackground({
    required int width,
    required int height,
  });
  Future<EngineCommitResult> undoInBackground();
  Future<EngineCommitResult> redoInBackground();
  Future<Uint8List> exportImageInBackground({
    required String format,
    required int quality,
  });

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
  Future<Map<String, Uint8List>> generateFilterPreviews(
    Uint8List bytes,
    List<String> filters, {
    int maxEdge = 180,
  }) =>
      Isolate.run(() async {
        await initializeRustBridge();
        final generated = rust.generateFilterPreviews(
          imageBytes: bytes,
          filterNames: filters,
          maxEdge: maxEdge,
        );
        return <String, Uint8List>{
          for (final preview in generated) preview.name: preview.bytes,
        };
      });

  @override
  Future<EngineCommitResult> commitFilterValue(
    String filter,
    double value,
  ) =>
      _runCommittedRustTask(() {
        rust.beginFilter(filter: filter);
        final preview = rust.updateFilterPreview(filter: filter, value: value);
        final bytes = rust.commitFilter();
        return (bytes: bytes, elapsedMicros: preview.elapsedMicros);
      });

  @override
  Future<EngineCommitResult> replaceFilterValue(
    String filter,
    double value,
  ) =>
      _runCommittedRustTask(() {
        rust.undo();
        rust.beginFilter(filter: filter);
        final preview = rust.updateFilterPreview(filter: filter, value: value);
        final bytes = rust.commitFilter();
        return (bytes: bytes, elapsedMicros: preview.elapsedMicros);
      });

  @override
  Future<EngineCommitResult> applyEditsInBackground() =>
      _runCommittedRustTask(() {
        final watch = Stopwatch()..start();
        final bytes = rust.applyEdits();
        watch.stop();
        return (
          bytes: bytes,
          elapsedMicros: BigInt.from(watch.elapsedMicroseconds),
        );
      });

  @override
  Future<EngineCommitResult> applyCropInBackground({
    required double x,
    required double y,
    required double width,
    required double height,
  }) =>
      _runCommittedRustTask(() {
        final watch = Stopwatch()..start();
        final bytes = rust.applyCrop(x: x, y: y, width: width, height: height);
        watch.stop();
        return (
          bytes: bytes,
          elapsedMicros: BigInt.from(watch.elapsedMicroseconds),
        );
      });

  @override
  Future<EngineCommitResult> rotateQuarterTurnsInBackground(int turns) =>
      _runCommittedRustTask(() {
        final watch = Stopwatch()..start();
        final bytes = rust.rotateQuarterTurns(turns: turns);
        watch.stop();
        return (
          bytes: bytes,
          elapsedMicros: BigInt.from(watch.elapsedMicroseconds),
        );
      });

  @override
  Future<EngineCommitResult> straightenInBackground(double degrees) =>
      _runCommittedRustTask(() {
        final watch = Stopwatch()..start();
        final bytes = rust.straighten(degrees: degrees);
        watch.stop();
        return (
          bytes: bytes,
          elapsedMicros: BigInt.from(watch.elapsedMicroseconds),
        );
      });

  @override
  Future<EngineCommitResult> flipHorizontalInBackground() =>
      _runCommittedRustTask(() {
        final watch = Stopwatch()..start();
        final bytes = rust.flipHorizontal();
        watch.stop();
        return (
          bytes: bytes,
          elapsedMicros: BigInt.from(watch.elapsedMicroseconds),
        );
      });

  @override
  Future<EngineCommitResult> flipVerticalInBackground() =>
      _runCommittedRustTask(() {
        final watch = Stopwatch()..start();
        final bytes = rust.flipVertical();
        watch.stop();
        return (
          bytes: bytes,
          elapsedMicros: BigInt.from(watch.elapsedMicroseconds),
        );
      });

  @override
  Future<EngineCommitResult> resizeCommittedInBackground({
    required int width,
    required int height,
  }) =>
      _runCommittedRustTask(() {
        final watch = Stopwatch()..start();
        final bytes = rust.resizeCommitted(width: width, height: height);
        watch.stop();
        return (
          bytes: bytes,
          elapsedMicros: BigInt.from(watch.elapsedMicroseconds),
        );
      });

  @override
  Future<EngineCommitResult> undoInBackground() => _runCommittedRustTask(() {
        final watch = Stopwatch()..start();
        final bytes = rust.undo();
        watch.stop();
        return (
          bytes: bytes,
          elapsedMicros: BigInt.from(watch.elapsedMicroseconds),
        );
      });

  @override
  Future<EngineCommitResult> redoInBackground() => _runCommittedRustTask(() {
        final watch = Stopwatch()..start();
        final bytes = rust.redo();
        watch.stop();
        return (
          bytes: bytes,
          elapsedMicros: BigInt.from(watch.elapsedMicroseconds),
        );
      });

  @override
  Future<Uint8List> exportImageInBackground({
    required String format,
    required int quality,
  }) =>
      Isolate.run(() async {
        await initializeRustBridge();
        return rust.exportImage(format: format, quality: quality);
      });

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
  EngineSessionInfo sessionInfo() => _sessionInfo();

  @override
  Uint8List exportImage({required String format, required int quality}) =>
      rust.exportImage(format: format, quality: quality);

  @override
  Uint8List originalPreview() => rust.originalPreview();
}

typedef _RustCommittedCall = ({Uint8List bytes, BigInt elapsedMicros}) Function();

Future<EngineCommitResult> _runCommittedRustTask(_RustCommittedCall task) =>
    Isolate.run(() async {
      await initializeRustBridge();
      final result = task();
      final histogram = rust.getHistogram(imageBytes: result.bytes);
      final session = _sessionInfo();
      return EngineCommitResult(
        bytes: result.bytes,
        histogram: histogram,
        elapsedMicros: result.elapsedMicros,
        session: session,
      );
    });

EngineSessionInfo _sessionInfo() {
  final info = rust.sessionInfo();
  return EngineSessionInfo(
    version: info.version,
    operationCount: info.operationCount,
    cursor: info.cursor,
    canUndo: info.canUndo,
    canRedo: info.canRedo,
  );
}
