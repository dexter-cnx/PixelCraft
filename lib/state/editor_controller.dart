import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/editor_session_store.dart';
import '../core/image_engine.dart';
import 'editor_adjustment_catalog.dart' as adjustment_catalog;

const coreFilters = adjustment_catalog.coreFilters;

const creativeFilters = <String>[
  'grayscale',
  'invert',
  'vintage',
  'oceanic',
  'lofi',
  'dramatic',
  'golden',
  'pastel_pink',
];

const editorPreviewMaxEdge = 1024;

bool isCreativeFilter(String filter) => creativeFilters.contains(filter);

double defaultAdjustmentValue(String filter) =>
    adjustment_catalog.defaultAdjustmentValue(filter);

adjustment_catalog.EditorAdjustmentSpec adjustmentSpec(String filter) =>
    adjustment_catalog.adjustmentSpec(filter);

enum EditorTool { adjust, filters, film, crop, rotate, details }

enum _PreviewKind { adjust, creative, film }

typedef _PendingPreview = ({
  int requestId,
  _PreviewKind kind,
  String key,
  double value,
});

class EditorState {
  const EditorState({
    this.originalBytes,
    this.originalPreviewBytes,
    this.previewBytes,
    this.histogram = const [],
    this.filterPreviews = const {},
    this.filmProfiles = const [],
    this.filmProfilePreviews = const {},
    this.selectedFilter = 'brightness',
    this.selectedCreativeFilter = '',
    this.selectedFilmProfile = '',
    this.selectedTool = EditorTool.adjust,
    this.value = 1,
    this.creativeFilterValue = 1,
    this.filmProfileStrength = 1,
    this.straightenDegrees = 0,
    this.processingMs = 0,
    this.isBusy = false,
    this.isPreviewProcessing = false,
    this.isGeneratingFilterPreviews = false,
    this.isGeneratingFilmPreviews = false,
    this.isAdjusting = false,
    this.showOriginal = false,
    this.isExporting = false,
    this.operationCount = 0,
    this.cursor = 0,
    this.canUndo = false,
    this.canRedo = false,
    this.error,
  });

  final Uint8List? originalBytes;
  final Uint8List? originalPreviewBytes;
  final Uint8List? previewBytes;
  final List<int> histogram;
  final Map<String, Uint8List> filterPreviews;
  final List<EngineFilmProfile> filmProfiles;
  final Map<String, Uint8List> filmProfilePreviews;
  final String selectedFilter;
  final String selectedCreativeFilter;
  final String selectedFilmProfile;
  final EditorTool selectedTool;
  final double value;
  final double creativeFilterValue;
  final double filmProfileStrength;
  final double straightenDegrees;
  final double processingMs;
  final bool isBusy;
  final bool isPreviewProcessing;
  final bool isGeneratingFilterPreviews;
  final bool isGeneratingFilmPreviews;
  final bool isAdjusting;
  final bool showOriginal;
  final bool isExporting;
  final int operationCount;
  final int cursor;
  final bool canUndo;
  final bool canRedo;
  final String? error;

  bool get hasUnappliedEdits => cursor > 0;

  Uint8List? get visiblePreview =>
      showOriginal ? originalPreviewBytes ?? previewBytes : previewBytes;

  EditorState copyWith({
    Uint8List? originalBytes,
    Uint8List? originalPreviewBytes,
    Uint8List? previewBytes,
    List<int>? histogram,
    Map<String, Uint8List>? filterPreviews,
    List<EngineFilmProfile>? filmProfiles,
    Map<String, Uint8List>? filmProfilePreviews,
    String? selectedFilter,
    String? selectedCreativeFilter,
    String? selectedFilmProfile,
    EditorTool? selectedTool,
    double? value,
    double? creativeFilterValue,
    double? filmProfileStrength,
    double? straightenDegrees,
    double? processingMs,
    bool? isBusy,
    bool? isPreviewProcessing,
    bool? isGeneratingFilterPreviews,
    bool? isGeneratingFilmPreviews,
    bool? isAdjusting,
    bool? showOriginal,
    bool? isExporting,
    int? operationCount,
    int? cursor,
    bool? canUndo,
    bool? canRedo,
    String? error,
  }) =>
      EditorState(
        originalBytes: originalBytes ?? this.originalBytes,
        originalPreviewBytes:
            originalPreviewBytes ?? this.originalPreviewBytes,
        previewBytes: previewBytes ?? this.previewBytes,
        histogram: histogram ?? this.histogram,
        filterPreviews: filterPreviews ?? this.filterPreviews,
        filmProfiles: filmProfiles ?? this.filmProfiles,
        filmProfilePreviews:
            filmProfilePreviews ?? this.filmProfilePreviews,
        selectedFilter: selectedFilter ?? this.selectedFilter,
        selectedCreativeFilter:
            selectedCreativeFilter ?? this.selectedCreativeFilter,
        selectedFilmProfile:
            selectedFilmProfile ?? this.selectedFilmProfile,
        selectedTool: selectedTool ?? this.selectedTool,
        value: value ?? this.value,
        creativeFilterValue:
            creativeFilterValue ?? this.creativeFilterValue,
        filmProfileStrength:
            filmProfileStrength ?? this.filmProfileStrength,
        straightenDegrees:
            straightenDegrees ?? this.straightenDegrees,
        processingMs: processingMs ?? this.processingMs,
        isBusy: isBusy ?? this.isBusy,
        isPreviewProcessing:
            isPreviewProcessing ?? this.isPreviewProcessing,
        isGeneratingFilterPreviews:
            isGeneratingFilterPreviews ?? this.isGeneratingFilterPreviews,
        isGeneratingFilmPreviews:
            isGeneratingFilmPreviews ?? this.isGeneratingFilmPreviews,
        isAdjusting: isAdjusting ?? this.isAdjusting,
        showOriginal: showOriginal ?? this.showOriginal,
        isExporting: isExporting ?? this.isExporting,
        operationCount: operationCount ?? this.operationCount,
        cursor: cursor ?? this.cursor,
        canUndo: canUndo ?? this.canUndo,
        canRedo: canRedo ?? this.canRedo,
        error: error,
      );
}

class EditorController extends StateNotifier<EditorState> {
  EditorController(this._engine, this._sessionStore)
      : super(const EditorState());

  final ImageEngine _engine;
  final EditorSessionStore _sessionStore;
  final Map<String, double> _adjustmentValues = {
    for (final filter in coreFilters)
      filter: defaultAdjustmentValue(filter),
  };
  final Map<String, double> _creativeValues = {
    for (final filter in creativeFilters) filter: 1,
  };
  final Map<String, double> _filmValues = {};
  String _activeCreativeFilter = '';
  String _activeFilmProfile = '';
  int _thumbnailGeneration = 0;
  int _latestPreviewRequestId = 0;
  _PendingPreview? _pendingPreview;
  bool _previewWorkerRunning = false;
  Future<void> _persistTail = Future.value();

  void _resetDraftControlValues() {
    for (final filter in coreFilters) {
      _adjustmentValues[filter] = defaultAdjustmentValue(filter);
    }
    for (final filter in creativeFilters) {
      _creativeValues[filter] = 1;
    }
    _filmValues.clear();
    _activeCreativeFilter = '';
    _activeFilmProfile = '';
  }

  void _hydrateDraftControlsFromRecipe(
    String recipeJson, {
    required bool resetMemories,
  }) {
    if (resetMemories) {
      _resetDraftControlValues();
    } else {
      for (final filter in coreFilters) {
        _adjustmentValues[filter] = defaultAdjustmentValue(filter);
      }
      _activeCreativeFilter = '';
      _activeFilmProfile = '';
    }

    try {
      final decoded = jsonDecode(recipeJson);
      if (decoded is! Map<String, dynamic>) return;
      final operations = decoded['operations'];
      final cursor = decoded['cursor'];
      final checkpointCursor = decoded['checkpoint_cursor'];
      if (operations is! List ||
          cursor is! int ||
          checkpointCursor is! int) {
        return;
      }

      final start = checkpointCursor.clamp(0, operations.length).toInt();
      final end = cursor.clamp(start, operations.length).toInt();
      for (final operation in operations.sublist(start, end)) {
        if (operation is! Map) continue;
        final type = operation['type'];

        if (type == 'filter') {
          final name = operation['name'];
          final value = operation['value'];
          if (name is! String || value is! num) continue;
          if (coreFilters.contains(name)) {
            _adjustmentValues[name] = value.toDouble();
          } else if (creativeFilters.contains(name)) {
            _activeCreativeFilter = name;
            _creativeValues[name] = value.toDouble();
          }
          continue;
        }

        if (type == 'film_profile') {
          final id = operation['id'];
          final strength = operation['strength'];
          if (id is String && strength is num) {
            _activeFilmProfile = id;
            _filmValues[id] = strength.toDouble();
          }
        }
      }
    } catch (_) {
      if (resetMemories) {
        _resetDraftControlValues();
      }
    }
  }

  Future<void> _syncDraftControlsFromEngine() async {
    try {
      final recipe = await _engine.exportSessionRecipeInBackground();
      _hydrateDraftControlsFromRecipe(
        recipe,
        resetMemories: false,
      );
      final selectedFilter = state.selectedFilter;
      final creative = _activeCreativeFilter;
      final film = _activeFilmProfile;
      state = state.copyWith(
        value: _adjustmentValues[selectedFilter] ??
            defaultAdjustmentValue(selectedFilter),
        selectedCreativeFilter: creative,
        creativeFilterValue:
            creative.isEmpty ? 1 : _creativeValues[creative] ?? 1,
        selectedFilmProfile: film,
        filmProfileStrength:
            film.isEmpty ? 1 : _filmValues[film] ?? 1,
      );
    } catch (_) {
      // UI recovery is best-effort; Rust image/session state remains authoritative.
    }
  }

  Future<void> load(Uint8List bytes) async {
    final generation = ++_thumbnailGeneration;
    _resetPendingKinds();
    _resetDraftControlValues();
    state = state.copyWith(isBusy: true, error: null);
    try {
      final loaded = await _engine.loadImageInBackground(
        bytes,
        maxEdge: editorPreviewMaxEdge,
      );
      final profiles = await _engine.filmProfilesInBackground();
      _applyLoadedState(bytes, loaded, profiles);
      unawaited(
        _prewarmThumbnails(loaded.originalPreviewBytes, generation),
      );
      unawaited(_persistSession());
    } catch (error) {
      state = state.copyWith(isBusy: false, error: '$error');
    }
  }

  Future<void> restore(Uint8List bytes, String recipeJson) async {
    final generation = ++_thumbnailGeneration;
    final sameSource = identical(state.originalBytes, bytes);
    _resetPendingKinds();
    _hydrateDraftControlsFromRecipe(
      recipeJson,
      resetMemories: !sameSource,
    );
    state = state.copyWith(isBusy: true, error: null);
    try {
      final loaded =
          await _engine.restoreSessionInBackground(bytes, recipeJson);
      final profiles = await _engine.filmProfilesInBackground();
      _applyLoadedState(bytes, loaded, profiles);
      unawaited(
        _prewarmThumbnails(loaded.originalPreviewBytes, generation),
      );
    } catch (error) {
      state = state.copyWith(isBusy: false, error: '$error');
    }
  }

  void _applyLoadedState(
    Uint8List bytes,
    EngineLoadResult loaded,
    List<EngineFilmProfile> profiles,
  ) {
    final creative = _activeCreativeFilter;
    final film = _activeFilmProfile;
    state = state.copyWith(
      originalBytes: bytes,
      originalPreviewBytes: loaded.originalPreviewBytes,
      previewBytes: loaded.previewBytes,
      histogram: loaded.histogram,
      filterPreviews: const {},
      filmProfiles: profiles,
      filmProfilePreviews: const {},
      selectedFilter: 'brightness',
      selectedCreativeFilter: creative,
      selectedFilmProfile: film,
      value: _adjustmentValues['brightness'] ?? 1,
      creativeFilterValue:
          creative.isEmpty ? 1 : _creativeValues[creative] ?? 1,
      filmProfileStrength:
          film.isEmpty ? 1 : _filmValues[film] ?? 1,
      straightenDegrees: 0,
      isBusy: false,
      isPreviewProcessing: false,
      isGeneratingFilterPreviews: false,
      isGeneratingFilmPreviews: false,
      operationCount: loaded.session.operationCount,
      cursor: loaded.session.cursor,
      canUndo: loaded.session.canUndo,
      canRedo: loaded.session.canRedo,
      error: null,
    );
  }

  Future<void> selectTool(EditorTool tool) async {
    if (state.isBusy) return;
    state = state.copyWith(selectedTool: tool, error: null);
    if (tool == EditorTool.filters && state.filterPreviews.isEmpty) {
      await refreshFilterPreviews();
    }
    if (tool == EditorTool.film &&
        state.filmProfilePreviews.isEmpty) {
      await refreshFilmProfilePreviews();
    }
  }

  void selectFilter(String filter) {
    if (state.isBusy) return;
    state = state.copyWith(
      selectedFilter: filter,
      value: _adjustmentValues[filter] ??
          defaultAdjustmentValue(filter),
      isAdjusting: false,
      error: null,
    );
  }

  Future<void> _prewarmThumbnails(
    Uint8List source,
    int generation,
  ) async {
    await Future.wait([
      _generateFilterPreviews(source, generation: generation),
      _generateFilmPreviews(source, generation: generation),
    ]);
  }

  Future<void> refreshFilterPreviews() async {
    if (state.filterPreviews.isNotEmpty ||
        state.isGeneratingFilterPreviews) {
      return;
    }
    final source = state.originalPreviewBytes;
    if (source == null) return;
    await _generateFilterPreviews(
      source,
      generation: _thumbnailGeneration,
    );
  }

  Future<void> refreshFilmProfilePreviews() async {
    if (state.filmProfilePreviews.isNotEmpty ||
        state.isGeneratingFilmPreviews) {
      return;
    }
    final source = state.originalPreviewBytes;
    if (source == null || state.filmProfiles.isEmpty) return;
    await _generateFilmPreviews(
      source,
      generation: _thumbnailGeneration,
    );
  }

  Future<void> _generateFilterPreviews(
    Uint8List source, {
    required int generation,
  }) async {
    if (generation != _thumbnailGeneration) return;
    state = state.copyWith(
      isGeneratingFilterPreviews: true,
      error: null,
    );
    try {
      final previews = await _engine.generateFilterPreviews(
        source,
        creativeFilters,
        maxEdge: 160,
      );
      if (generation != _thumbnailGeneration) return;
      state = state.copyWith(
        filterPreviews: previews,
        isGeneratingFilterPreviews: false,
      );
    } catch (error) {
      if (generation != _thumbnailGeneration) return;
      state = state.copyWith(
        isGeneratingFilterPreviews: false,
        error: '$error',
      );
    }
  }

  Future<void> _generateFilmPreviews(
    Uint8List source, {
    required int generation,
  }) async {
    if (generation != _thumbnailGeneration ||
        state.filmProfiles.isEmpty) {
      return;
    }
    state = state.copyWith(
      isGeneratingFilmPreviews: true,
      error: null,
    );
    try {
      final previews = await _engine.generateFilmProfilePreviews(
        source,
        state.filmProfiles
            .map((profile) => profile.id)
            .toList(growable: false),
        maxEdge: 160,
      );
      if (generation != _thumbnailGeneration) return;
      state = state.copyWith(
        filmProfilePreviews: previews,
        isGeneratingFilmPreviews: false,
      );
    } catch (error) {
      if (generation != _thumbnailGeneration) return;
      state = state.copyWith(
        isGeneratingFilmPreviews: false,
        error: '$error',
      );
    }
  }

  Future<void> applyCreativeFilter(String filter) async {
    if (state.isBusy || state.isGeneratingFilterPreviews) return;
    final value = _creativeValues[filter] ?? 1;
    _activeCreativeFilter = filter;
    state = state.copyWith(
      selectedCreativeFilter: filter,
      creativeFilterValue: value,
      error: null,
    );
    _queuePreview(_PreviewKind.creative, filter, value);
  }

  Future<void> updateCreativeFilterValue(double value) async {
    final filter = state.selectedCreativeFilter;
    if (filter.isEmpty || state.isBusy) return;
    _activeCreativeFilter = filter;
    _creativeValues[filter] = value;
    state = state.copyWith(
      creativeFilterValue: value,
      error: null,
    );
    _queuePreview(_PreviewKind.creative, filter, value);
  }

  Future<void> commitFilterValue(double value) async {
    if (state.isBusy || state.previewBytes == null) return;
    final filter = state.selectedFilter;
    _adjustmentValues[filter] = value;
    state = state.copyWith(
      value: value,
      isAdjusting: false,
      error: null,
    );
    _queuePreview(_PreviewKind.adjust, filter, value);
  }

  Future<void> selectFilmProfile(String id) async {
    if (state.isBusy || state.isGeneratingFilmPreviews) return;
    final strength = _filmValues[id] ?? 1;
    _activeFilmProfile = id;
    state = state.copyWith(
      selectedFilmProfile: id,
      filmProfileStrength: strength,
      error: null,
    );
    _queuePreview(_PreviewKind.film, id, strength);
  }

  Future<void> updateFilmProfileStrength(double value) async {
    final profile = state.selectedFilmProfile;
    if (profile.isEmpty || state.isBusy) return;
    _activeFilmProfile = profile;
    _filmValues[profile] = value;
    state = state.copyWith(
      filmProfileStrength: value,
      error: null,
    );
    _queuePreview(_PreviewKind.film, profile, value);
  }

  void _queuePreview(
    _PreviewKind kind,
    String key,
    double value,
  ) {
    final requestId = ++_latestPreviewRequestId;
    _pendingPreview = (
      requestId: requestId,
      kind: kind,
      key: key,
      value: value,
    );
    state = state.copyWith(
      isPreviewProcessing: true,
      error: null,
    );
    if (!_previewWorkerRunning) {
      unawaited(_drainPreviewQueue());
    }
  }

  Future<EngineCommitResult> _replaceExclusiveDraftSlot(
    _PreviewKind kind,
    String key,
    double value,
  ) async {
    final original = state.originalBytes;
    if (original == null) {
      throw StateError('No source image is loaded');
    }

    final recipeJson =
        await _engine.exportSessionRecipeInBackground();
    final decoded = jsonDecode(recipeJson);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Invalid editor recipe');
    }
    final rawOperations = decoded['operations'];
    final rawCursor = decoded['cursor'];
    final rawCheckpoint = decoded['checkpoint_cursor'];
    if (rawOperations is! List ||
        rawCursor is! int ||
        rawCheckpoint is! int) {
      throw StateError('Invalid editor recipe bounds');
    }

    var cursor = rawCursor.clamp(0, rawOperations.length).toInt();
    final checkpoint =
        rawCheckpoint.clamp(0, cursor).toInt();
    final operations = List<dynamic>.from(
      rawOperations.take(cursor),
    );

    bool isSlot(dynamic operation) {
      if (operation is! Map) return false;
      if (kind == _PreviewKind.creative) {
        return operation['type'] == 'filter' &&
            operation['name'] is String &&
            creativeFilters.contains(operation['name']);
      }
      if (kind == _PreviewKind.film) {
        return operation['type'] == 'film_profile';
      }
      return false;
    }

    final replacement = kind == _PreviewKind.creative
        ? <String, dynamic>{
            'type': 'filter',
            'name': key,
            'value': value,
          }
        : <String, dynamic>{
            'type': 'film_profile',
            'id': key,
            'strength': value,
          };

    var slotIndex = -1;
    for (var index = checkpoint; index < cursor; index++) {
      if (isSlot(operations[index])) {
        slotIndex = index;
        break;
      }
    }

    if (slotIndex >= 0) {
      operations[slotIndex] = replacement;
    } else {
      operations.add(replacement);
      cursor++;
    }

    decoded['operations'] = operations;
    decoded['cursor'] = cursor;
    decoded['checkpoint_cursor'] = checkpoint;

    final watch = Stopwatch()..start();
    final loaded = await _engine.restoreSessionInBackground(
      original,
      jsonEncode(decoded),
    );
    watch.stop();
    return EngineCommitResult(
      bytes: loaded.previewBytes,
      histogram: loaded.histogram,
      elapsedMicros: BigInt.from(watch.elapsedMicroseconds),
      session: loaded.session,
    );
  }

  Future<void> _drainPreviewQueue() async {
    if (_previewWorkerRunning) return;
    _previewWorkerRunning = true;
    try {
      while (_pendingPreview != null) {
        final request = _pendingPreview!;
        _pendingPreview = null;
        try {
          final result = switch (request.kind) {
            _PreviewKind.adjust => await _engine.commitFilterValue(
                request.key,
                request.value,
              ),
            _PreviewKind.creative || _PreviewKind.film =>
              await _replaceExclusiveDraftSlot(
                request.kind,
                request.key,
                request.value,
              ),
          };

          if (request.requestId == _latestPreviewRequestId) {
            _applyBackgroundResult(result);
            state = state.copyWith(
              isPreviewProcessing: _pendingPreview != null,
            );
            unawaited(_persistSession());
          }
        } catch (error) {
          if (request.requestId == _latestPreviewRequestId) {
            state = state.copyWith(
              isPreviewProcessing: false,
              error: '$error',
            );
          }
        }
      }
    } finally {
      _previewWorkerRunning = false;
      state = state.copyWith(isPreviewProcessing: false);
    }
  }

  Future<void> applyEdits() async {
    if (state.isBusy ||
        state.isPreviewProcessing ||
        !state.hasUnappliedEdits) {
      return;
    }
    final generation = ++_thumbnailGeneration;
    state = state.copyWith(isBusy: true, error: null);
    try {
      final result = await _engine.applyEditsInBackground();
      _resetPendingKinds();
      _resetDraftControlValues();
      state = state.copyWith(
        originalPreviewBytes: result.bytes,
        previewBytes: result.bytes,
        histogram: result.histogram,
        filterPreviews: const {},
        filmProfilePreviews: const {},
        selectedFilter: 'brightness',
        selectedCreativeFilter: '',
        selectedFilmProfile: '',
        value: 1,
        creativeFilterValue: 1,
        filmProfileStrength: 1,
        straightenDegrees: 0,
        processingMs:
            result.elapsedMicros.toDouble() / 1000.0,
        isBusy: false,
        isGeneratingFilterPreviews: false,
        isGeneratingFilmPreviews: false,
        isAdjusting: false,
        operationCount: result.session.operationCount,
        cursor: result.session.cursor,
        canUndo: result.session.canUndo,
        canRedo: result.session.canRedo,
        error: null,
      );
      unawaited(_prewarmThumbnails(result.bytes, generation));
      unawaited(_persistSession());
    } catch (error) {
      state = state.copyWith(isBusy: false, error: '$error');
    }
  }

  Future<void> cancelEdits() async {
    if (state.isBusy ||
        state.isPreviewProcessing ||
        !state.hasUnappliedEdits) {
      return;
    }
    state = state.copyWith(isBusy: true, error: null);
    try {
      final result = await _engine.discardEditsInBackground();
      _resetPendingKinds();
      _resetDraftControlValues();
      state = state.copyWith(
        previewBytes: result.bytes,
        histogram: result.histogram,
        selectedFilter: 'brightness',
        selectedCreativeFilter: '',
        selectedFilmProfile: '',
        value: 1,
        creativeFilterValue: 1,
        filmProfileStrength: 1,
        straightenDegrees: 0,
        processingMs:
            result.elapsedMicros.toDouble() / 1000.0,
        isBusy: false,
        isAdjusting: false,
        operationCount: result.session.operationCount,
        cursor: result.session.cursor,
        canUndo: result.session.canUndo,
        canRedo: result.session.canRedo,
        error: null,
      );
      unawaited(_persistSession());
    } catch (error) {
      state = state.copyWith(isBusy: false, error: '$error');
    }
  }

  Future<void> commitCrop({
    required double x,
    required double y,
    required double width,
    required double height,
  }) async {
    if (state.isBusy || state.isPreviewProcessing) return;
    _resetPendingKinds();
    await _applyBackgroundTransform(
      () => _engine.applyCropInBackground(
        x: x,
        y: y,
        width: width,
        height: height,
      ),
    );
  }

  Future<void> applyCenteredCrop(double aspectRatio) async {
    if (state.isBusy || state.isPreviewProcessing) return;
    double width = 1;
    double height = 1;
    if (aspectRatio >= 1) {
      height = 1 / aspectRatio;
    } else {
      width = aspectRatio;
    }
    _resetPendingKinds();
    await _applyBackgroundTransform(
      () => _engine.applyCropInBackground(
        x: (1 - width) / 2,
        y: (1 - height) / 2,
        width: width,
        height: height,
      ),
    );
  }

  Future<void> rotateLeft() async {
    if (state.isBusy || state.isPreviewProcessing) return;
    _resetPendingKinds();
    await _applyBackgroundTransform(
      () => _engine.rotateQuarterTurnsInBackground(3),
    );
  }

  Future<void> rotateRight() async {
    if (state.isBusy || state.isPreviewProcessing) return;
    _resetPendingKinds();
    await _applyBackgroundTransform(
      () => _engine.rotateQuarterTurnsInBackground(1),
    );
  }

  Future<void> flipHorizontal() async {
    if (state.isBusy || state.isPreviewProcessing) return;
    _resetPendingKinds();
    await _applyBackgroundTransform(
      _engine.flipHorizontalInBackground,
    );
  }

  Future<void> flipVertical() async {
    if (state.isBusy || state.isPreviewProcessing) return;
    _resetPendingKinds();
    await _applyBackgroundTransform(
      _engine.flipVerticalInBackground,
    );
  }

  Future<void> commitStraighten(double degrees) async {
    if (degrees.abs() < 0.01 ||
        state.isBusy ||
        state.isPreviewProcessing) {
      return;
    }
    _resetPendingKinds();
    await _applyBackgroundTransform(
      () => _engine.straightenInBackground(degrees),
    );
    state = state.copyWith(straightenDegrees: 0);
  }

  void setStraightenPreview(double degrees) {
    if (state.isBusy) return;
    state = state.copyWith(straightenDegrees: degrees);
  }

  void setShowOriginal(bool value) {
    state = state.copyWith(showOriginal: value);
  }

  Future<Uint8List> exportImage({
    required String format,
    required int quality,
  }) async {
    if (state.isBusy ||
        state.isExporting ||
        state.isPreviewProcessing) {
      throw StateError('Image processing is already in progress');
    }
    state = state.copyWith(isExporting: true, error: null);
    try {
      return await _engine.exportImageInBackground(
        format: format,
        quality: quality,
      );
    } catch (error) {
      state = state.copyWith(error: '$error');
      rethrow;
    } finally {
      state = state.copyWith(isExporting: false);
    }
  }

  EngineResult benchmarkCurrentFilter() {
    final input = state.previewBytes;
    if (input == null) throw StateError('No preview loaded');
    return _engine.applyFilterTimed(
      input,
      state.selectedFilter,
      state.value,
    );
  }

  Future<void> undo() async {
    if (!state.canUndo || state.isBusy || state.isPreviewProcessing) {
      return;
    }
    _resetPendingKinds();
    await _applyBackgroundTransform(_engine.undoInBackground);
    await _syncDraftControlsFromEngine();
  }

  Future<void> redo() async {
    if (!state.canRedo || state.isBusy || state.isPreviewProcessing) {
      return;
    }
    _resetPendingKinds();
    await _applyBackgroundTransform(_engine.redoInBackground);
    await _syncDraftControlsFromEngine();
  }

  Future<void> _applyBackgroundTransform(
    Future<EngineCommitResult> Function() action,
  ) async {
    if (state.isBusy || state.isPreviewProcessing) return;
    state = state.copyWith(isBusy: true, error: null);
    try {
      final result = await action();
      _applyBackgroundResult(result);
      unawaited(_persistSession());
    } catch (error) {
      state = state.copyWith(isBusy: false, error: '$error');
    }
  }

  void _applyBackgroundResult(EngineCommitResult result) {
    state = state.copyWith(
      previewBytes: result.bytes,
      histogram: result.histogram,
      value: _adjustmentValues[state.selectedFilter] ??
          defaultAdjustmentValue(state.selectedFilter),
      selectedCreativeFilter: _activeCreativeFilter,
      creativeFilterValue: _activeCreativeFilter.isEmpty
          ? 1
          : _creativeValues[_activeCreativeFilter] ?? 1,
      selectedFilmProfile: _activeFilmProfile,
      filmProfileStrength: _activeFilmProfile.isEmpty
          ? 1
          : _filmValues[_activeFilmProfile] ?? 1,
      processingMs:
          result.elapsedMicros.toDouble() / 1000.0,
      isBusy: false,
      isAdjusting: false,
      operationCount: result.session.operationCount,
      cursor: result.session.cursor,
      canUndo: result.session.canUndo,
      canRedo: result.session.canRedo,
      error: null,
    );
  }

  void _resetPendingKinds() {
    _pendingPreview = null;
    _latestPreviewRequestId++;
  }

  Future<void> _persistSession() {
    final original = state.originalBytes;
    if (original == null) return Future.value();

    final task = _persistTail.then((_) async {
      // A queued save for a previous image must never export the recipe from a
      // newly loaded image and pair it with stale source bytes.
      if (!identical(state.originalBytes, original)) return;
      try {
        final recipe = await _engine.exportSessionRecipeInBackground();
        if (!identical(state.originalBytes, original)) return;
        await _sessionStore.save(
          originalBytes: original,
          recipeJson: recipe,
        );
      } catch (_) {
        // Session recovery is best-effort and must never interrupt editing.
      }
    });
    _persistTail = task.catchError((_) {});
    return task;
  }
}

final imageEngineProvider = Provider<ImageEngine>(
  (ref) => const RustImageEngine(),
);

final editorSessionStoreProvider = Provider<EditorSessionStore>(
  (ref) => EditorSessionStore(),
);

final editorProvider =
    StateNotifierProvider<EditorController, EditorState>(
  (ref) => EditorController(
    ref.watch(imageEngineProvider),
    ref.watch(editorSessionStoreProvider),
  ),
);
