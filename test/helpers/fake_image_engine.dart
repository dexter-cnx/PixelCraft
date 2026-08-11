import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:pixelcraft/core/image_engine.dart';
import 'package:pixelcraft/state/editor_controller.dart';

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
  int checkpointCursor = 0;
  String? activeFilter;
  String? activeFilmProfile;
  double? lastValue;

  final List<Map<String, dynamic>> operations = [];

  final List<int> bins = List<int>.generate(768, (index) => index % 256);
  final List<EngineFilmProfile> profiles = const [
    EngineFilmProfile(
      id: 'provia_inspired',
      name: 'Provia Inspired',
      description: 'Balanced slide-film color.',
    ),
    EngineFilmProfile(
      id: 'velvia_inspired',
      name: 'Velvia Inspired',
      description: 'Vivid high-contrast landscape color.',
    ),
    EngineFilmProfile(
      id: 'astia_inspired',
      name: 'Astia Inspired',
      description: 'Soft portrait-oriented slide-film color.',
    ),
    EngineFilmProfile(
      id: 'e100_inspired',
      name: 'E100 Inspired',
      description: 'Neutral transparency-film look.',
    ),
    EngineFilmProfile(
      id: 'ektar_inspired',
      name: 'Ektar Inspired',
      description: 'Ultra-vivid color-negative look.',
    ),
    EngineFilmProfile(
      id: 'chrome64_inspired',
      name: 'Chrome 64 Inspired',
      description: 'Warm nostalgic chrome look.',
    ),
  ];

  @override
  void loadImage(Uint8List bytes) {
    loadCalls++;
    if (failLoad) throw StateError('decode failed');
    operations.clear();
    cursor = 0;
    operationCount = 0;
    checkpointCursor = 0;
    activeFilter = null;
    activeFilmProfile = null;
    lastValue = null;
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

    if (failLoad) throw StateError('decode failed');

    final decoded = jsonDecode(recipeJson);
    if (decoded is Map<String, dynamic> && decoded['operations'] is List) {
      operations
        ..clear()
        ..addAll(
          (decoded['operations'] as List)
              .whereType<Map>()
              .map((operation) => Map<String, dynamic>.from(operation)),
        );
      final requestedCursor = decoded['cursor'];
      cursor = requestedCursor is int
          ? requestedCursor.clamp(0, operations.length).toInt()
          : operations.length;
      final requestedCheckpoint = decoded['checkpoint_cursor'];
      checkpointCursor = requestedCheckpoint is int
          ? requestedCheckpoint.clamp(0, cursor).toInt()
          : 0;
      operationCount = operations.length;
      _syncActiveOperationState();
    } else {
      operations.clear();
      cursor = recipeJson.contains('draft') ? 1 : 0;
      operationCount = cursor;
      checkpointCursor = 0;
      activeFilter = null;
      activeFilmProfile = null;
      lastValue = null;
    }

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
    return jsonEncode(<String, dynamic>{
      'version': 3,
      'operations': operations,
      'cursor': cursor,
      'checkpoint_cursor': checkpointCursor,
    });
  }

  void _truncateRedoTail() {
    if (cursor < operations.length) {
      operations.removeRange(cursor, operations.length);
    }
  }

  int _findFilterSlot(String filter) {
    for (var index = checkpointCursor; index < cursor; index++) {
      final operation = operations[index];
      if (operation['type'] == 'filter' && operation['name'] == filter) {
        return index;
      }
    }
    return -1;
  }

  int _findCreativeSlot() {
    for (var index = checkpointCursor; index < cursor; index++) {
      final operation = operations[index];
      if (operation['type'] == 'filter' &&
          operation['name'] is String &&
          creativeFilters.contains(operation['name'])) {
        return index;
      }
    }
    return -1;
  }

  int _findFilmSlot() {
    for (var index = checkpointCursor; index < cursor; index++) {
      if (operations[index]['type'] == 'film_profile') return index;
    }
    return -1;
  }

  void _upsertFilter(String filter, double value) {
    _truncateRedoTail();
    final replacement = <String, dynamic>{
      'type': 'filter',
      'name': filter,
      'value': value,
    };
    final slot = _findFilterSlot(filter);
    if (slot >= 0) {
      operations[slot] = replacement;
    } else {
      operations.add(replacement);
      cursor = operations.length;
    }
    operationCount = operations.length;
  }

  void _upsertFilm(String id, double strength) {
    _truncateRedoTail();
    final replacement = <String, dynamic>{
      'type': 'film_profile',
      'id': id,
      'strength': strength,
    };
    final slot = _findFilmSlot();
    if (slot >= 0) {
      operations[slot] = replacement;
    } else {
      operations.add(replacement);
      cursor = operations.length;
    }
    operationCount = operations.length;
  }

  void _syncActiveOperationState() {
    activeFilter = null;
    activeFilmProfile = null;
    lastValue = null;
    for (var index = checkpointCursor; index < cursor; index++) {
      final operation = operations[index];
      if (operation['type'] == 'filter') {
        final name = operation['name'];
        final value = operation['value'];
        if (name is String && value is num) {
          activeFilter = name;
          lastValue = value.toDouble();
        }
      } else if (operation['type'] == 'film_profile') {
        final id = operation['id'];
        final strength = operation['strength'];
        if (id is String && strength is num) {
          activeFilmProfile = id;
          lastValue = strength.toDouble();
        }
      }
    }
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
    _upsertFilm(id, strength);
    activeFilmProfile = id;
    lastValue = strength;
    return _result(elapsedMicros: BigInt.from(9000));
  }

  @override
  Future<EngineCommitResult> replaceFilmProfile(String id, double strength) async {
    await _waitPreview();
    replaceFilmProfileCalls++;
    _upsertFilm(id, strength);
    activeFilmProfile = id;
    lastValue = strength;
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
    _upsertFilter(filter, value);
    return _result(elapsedMicros: BigInt.from(12500));
  }

  @override
  Future<EngineCommitResult> replaceFilterValue(
    String filter,
    double value,
  ) async {
    await _waitPreview();
    replaceFilterCalls++;
    beginFilter(filter);
    updateFilterPreview(filter, value);
    commitCalls++;
    _upsertFilter(filter, value);
    return _result(elapsedMicros: BigInt.from(12500));
  }

  @override
  Future<EngineCommitResult> applyEditsInBackground() async {
    applyEditsCalls++;
    operations.clear();
    cursor = 0;
    operationCount = 0;
    checkpointCursor = 0;
    activeFilter = null;
    activeFilmProfile = null;
    lastValue = null;
    return _result();
  }

  @override
  Future<EngineCommitResult> discardEditsInBackground() async {
    discardEditsCalls++;
    if (checkpointCursor < operations.length) {
      operations.removeRange(checkpointCursor, operations.length);
    }
    cursor = checkpointCursor;
    operationCount = operations.length;
    _syncActiveOperationState();
    return _result();
  }

  Uint8List _commitTransform([String type = 'transform']) {
    _truncateRedoTail();
    operations.add(<String, dynamic>{'type': type});
    cursor = operations.length;
    operationCount = operations.length;
    transformCalls++;
    return output;
  }

  EngineCommitResult _result({BigInt? elapsedMicros}) => EngineCommitResult(
        bytes: output,
        histogram: bins,
        elapsedMicros: elapsedMicros ?? BigInt.from(1000),
        session: sessionInfo(),
      );

  Future<EngineCommitResult> _backgroundTransform([String type = 'transform']) async {
    _commitTransform(type);
    return _result();
  }

  @override
  Future<EngineCommitResult> applyCropInBackground({
    required double x,
    required double y,
    required double width,
    required double height,
  }) =>
      _backgroundTransform('crop');

  @override
  Future<EngineCommitResult> rotateQuarterTurnsInBackground(int turns) =>
      _backgroundTransform('rotate90');

  @override
  Future<EngineCommitResult> straightenInBackground(double degrees) =>
      _backgroundTransform('rotate_degrees');

  @override
  Future<EngineCommitResult> flipHorizontalInBackground() =>
      _backgroundTransform('flip_horizontal');

  @override
  Future<EngineCommitResult> flipVerticalInBackground() =>
      _backgroundTransform('flip_vertical');

  @override
  Future<EngineCommitResult> resizeCommittedInBackground({
    required int width,
    required int height,
  }) =>
      _backgroundTransform('resize');

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
      _commitTransform('crop');

  @override
  Uint8List rotateQuarterTurns(int turns) => _commitTransform('rotate90');

  @override
  Uint8List straighten(double degrees) => _commitTransform('rotate_degrees');

  @override
  Uint8List flipHorizontal() => _commitTransform('flip_horizontal');

  @override
  Uint8List flipVertical() => _commitTransform('flip_vertical');

  @override
  Uint8List resizeCommitted({required int width, required int height}) =>
      _commitTransform('resize');

  @override
  Uint8List undo() {
    undoCalls++;
    if (cursor > 0) cursor--;
    _syncActiveOperationState();
    return output;
  }

  @override
  Uint8List redo() {
    redoCalls++;
    if (cursor < operationCount) cursor++;
    _syncActiveOperationState();
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
