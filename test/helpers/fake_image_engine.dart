import 'dart:async';
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
  Duration previewDelay = Duration.zero;
  int loadCalls = 0;
  int backgroundLoadCalls = 0;
  int restoreSessionCalls = 0;
  int exportSessionRecipeCalls = 0;
  int beginCalls = 0;
  int previewCalls = 0;
  int commitCalls = 0;
  int replaceFilterCalls = 0;
  int applyFilmProfileCalls = 0;
  int replaceFilmProfileCalls = 0;
  int applyEditsCalls = 0;
  int discardEditsCalls = 0;
  int filterPreviewGenerationCalls = 0;
  int filmPreviewGenerationCalls = 0;
  int undoCalls = 0;
  int redoCalls = 0;
  int exportCalls = 0;
  int transformCalls = 0;
  int cursor = 0;
  int operationCount = 0;
  String? activeFilter;
  String? activeFilmProfile;
  double? lastValue;

  final List<int> bins = List<int>.generate(768, (index) => index % 256);
  final List<EngineFilmProfile> profiles = const [
    EngineFilmProfile(
      id: 'provia_inspired',
      name: 'Provia Inspired',
      description: 'Balanced slide-film color.',
    ),
    EngineFilmProfile(
      id: 'e100_inspired',
      name: 'E100 Inspired',
      description: 'Neutral transparency-film look.',
    ),
  ];

  @override
  void loadImage(Uint8List bytes) {
    loadCalls++;
    if (failLoad) throw StateError('decode failed');
    cursor = 0;
    operationCount = 0;
  }

  @override
  Future<EngineLoadResult> loadImageInBackground(
    Uint8List bytes, {
    required int maxEdge,
  }) async {
    backgroundLoadCalls++;
    loadImage(bytes);
    return _loadResult();
  }

  @override
  Future<EngineLoadResult> restoreSessionInBackground(
    Uint8List bytes,
    String recipeJson,
  ) async {
    restoreSessionCalls++;
    loadImage(bytes);
    cursor = recipeJson.contains('draft') ? 1 : 0;
    operationCount = cursor;
    return _loadResult();
  }

  EngineLoadResult _loadResult() => EngineLoadResult(
        previewBytes: output,
        originalPreviewBytes: output,
        histogram: bins,
        session: sessionInfo(),
      );

  @override
  Future<String> exportSessionRecipeInBackground() async {
    exportSessionRecipeCalls++;
    return '{"version":1,"cursor":$cursor}';
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

  @override
  Future<Map<String, Uint8List>> generateFilterPreviews(
    Uint8List bytes,
    List<String> filters, {
    int maxEdge = 180,
  }) async {
    filterPreviewGenerationCalls++;
    return {for (final filter in filters) filter: output};
  }

  @override
  Future<List<EngineFilmProfile>> filmProfilesInBackground() async => profiles;

  @override
  Future<Map<String, Uint8List>> generateFilmProfilePreviews(
    Uint8List bytes,
    List<String> profileIds, {
    int maxEdge = 180,
  }) async {
    filmPreviewGenerationCalls++;
    return {for (final id in profileIds) id: output};
  }

  Future<void> _waitPreview() async {
    if (previewDelay > Duration.zero) await Future<void>.delayed(previewDelay);
  }

  @override
  Future<EngineCommitResult> applyFilmProfile(String id, double strength) async {
    await _waitPreview();
    applyFilmProfileCalls++;
    activeFilmProfile = id;
    lastValue = strength;
    _commitTransform();
    return _result(elapsedMicros: BigInt.from(9000));
  }

  @override
  Future<EngineCommitResult> replaceFilmProfile(String id, double strength) async {
    await _waitPreview();
    replaceFilmProfileCalls++;
    if (cursor > 0) cursor--;
    activeFilmProfile = id;
    lastValue = strength;
    operationCount = cursor + 1;
    cursor = operationCount;
    return _result(elapsedMicros: BigInt.from(9000));
  }

  @override
  Future<EngineCommitResult> commitFilterValue(
    String filter,
    double value,
  ) async {
    await _waitPreview();
    beginFilter(filter);
    updateFilterPreview(filter, value);
    commitCalls++;
    _commitTransform();
    return _result(elapsedMicros: BigInt.from(12500));
  }

  @override
  Future<EngineCommitResult> replaceFilterValue(
    String filter,
    double value,
  ) async {
    await _waitPreview();
    replaceFilterCalls++;
    if (cursor > 0) cursor--;
    beginFilter(filter);
    updateFilterPreview(filter, value);
    commitCalls++;
    operationCount = cursor + 1;
    cursor = operationCount;
    return _result(elapsedMicros: BigInt.from(12500));
  }

  @override
  Future<EngineCommitResult> applyEditsInBackground() async {
    applyEditsCalls++;
    cursor = 0;
    operationCount = 0;
    activeFilter = null;
    activeFilmProfile = null;
    lastValue = null;
    return _result();
  }

  @override
  Future<EngineCommitResult> discardEditsInBackground() async {
    discardEditsCalls++;
    cursor = 0;
    operationCount = 0;
    activeFilter = null;
    activeFilmProfile = null;
    lastValue = null;
    return _result();
  }

  Uint8List _commitTransform() {
    transformCalls++;
    operationCount = cursor + 1;
    cursor = operationCount;
    return output;
  }

  EngineCommitResult _result({BigInt? elapsedMicros}) => EngineCommitResult(
        bytes: output,
        histogram: bins,
        elapsedMicros: elapsedMicros ?? BigInt.from(1000),
        session: sessionInfo(),
      );

  Future<EngineCommitResult> _backgroundTransform() async {
    _commitTransform();
    return _result();
  }

  @override
  Future<EngineCommitResult> applyCropInBackground({
    required double x,
    required double y,
    required double width,
    required double height,
  }) =>
      _backgroundTransform();

  @override
  Future<EngineCommitResult> rotateQuarterTurnsInBackground(int turns) =>
      _backgroundTransform();

  @override
  Future<EngineCommitResult> straightenInBackground(double degrees) =>
      _backgroundTransform();

  @override
  Future<EngineCommitResult> flipHorizontalInBackground() =>
      _backgroundTransform();

  @override
  Future<EngineCommitResult> flipVerticalInBackground() =>
      _backgroundTransform();

  @override
  Future<EngineCommitResult> resizeCommittedInBackground({
    required int width,
    required int height,
  }) =>
      _backgroundTransform();

  @override
  Future<EngineCommitResult> undoInBackground() async {
    undo();
    return _result();
  }

  @override
  Future<EngineCommitResult> redoInBackground() async {
    redo();
    return _result();
  }

  @override
  Future<Uint8List> exportImageInBackground({
    required String format,
    required int quality,
  }) async =>
      exportImage(format: format, quality: quality);

  @override
  Uint8List applyCrop({
    required double x,
    required double y,
    required double width,
    required double height,
  }) =>
      _commitTransform();

  @override
  Uint8List rotateQuarterTurns(int turns) => _commitTransform();

  @override
  Uint8List straighten(double degrees) => _commitTransform();

  @override
  Uint8List flipHorizontal() => _commitTransform();

  @override
  Uint8List flipVertical() => _commitTransform();

  @override
  Uint8List resizeCommitted({required int width, required int height}) =>
      _commitTransform();

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
        version: 3,
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
