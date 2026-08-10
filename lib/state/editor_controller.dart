import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/editor_session_store.dart';
import '../core/image_engine.dart';

const coreFilters = <String>[
  'brightness',
  'contrast',
  'saturation',
  'gaussian_blur',
  'sharpen',
];

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
    filter == 'gaussian_blur' || filter == 'sharpen' ? 0 : 1;

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
        originalPreviewBytes: originalPreviewBytes ?? this.originalPreviewBytes,
        previewBytes: previewBytes ?? this.previewBytes,
        histogram: histogram ?? this.histogram,
        filterPreviews: filterPreviews ?? this.filterPreviews,
        filmProfiles: filmProfiles ?? this.filmProfiles,
        filmProfilePreviews: filmProfilePreviews ?? this.filmProfilePreviews,
        selectedFilter: selectedFilter ?? this.selectedFilter,
        selectedCreativeFilter:
            selectedCreativeFilter ?? this.selectedCreativeFilter,
        selectedFilmProfile: selectedFilmProfile ?? this.selectedFilmProfile,
        selectedTool: selectedTool ?? this.selectedTool,
        value: value ?? this.value,
        creativeFilterValue: creativeFilterValue ?? this.creativeFilterValue,
        filmProfileStrength: filmProfileStrength ?? this.filmProfileStrength,
        straightenDegrees: straightenDegrees ?? this.straightenDegrees,
        processingMs: processingMs ?? this.processingMs,
        isBusy: isBusy ?? this.isBusy,
        isPreviewProcessing: isPreviewProcessing ?? this.isPreviewProcessing,
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
  EditorController(this._engine, this._sessionStore) : super(const EditorState());

  final ImageEngine _engine;
  final EditorSessionStore _sessionStore;
  final Map<String, double> _adjustmentValues = {
    for (final filter in coreFilters) filter: defaultAdjustmentValue(filter),
  };
  int _thumbnailGeneration = 0;
  bool _hasPendingFilterOperation = false;
  bool _hasPendingFilmOperation = false;
  int _latestPreviewRequestId = 0;
  _PendingPreview? _pendingPreview;
  bool _previewWorkerRunning = false;
  Future<void> _persistTail = Future.value();

  void _resetAdjustmentValues() {
    for (final filter in coreFilters) {
      _adjustmentValues[filter] = defaultAdjustmentValue(filter);
    }
  }

  Future<void> load(Uint8List bytes) async {
    final generation = ++_thumbnailGeneration;
    _resetPendingKinds();
    _resetAdjustmentValues();
    state = state.copyWith(isBusy: true, error: null);
    try {
      final loaded = await _engine.loadImageInBackground(
        bytes,
        maxEdge: editorPreviewMaxEdge,
      );
      final profiles = await _engine.filmProfilesInBackground();
      _applyLoadedState(bytes, loaded, profiles);
      unawaited(_prewarmThumbnails(loaded.originalPreviewBytes, generation));
      unawaited(_persistSession());
    } catch (error) {
      state = state.copyWith(isBusy: false, error: '$error');
    }
  }

  Future<void> restore(Uint8List bytes, String recipeJson) async {
    final generation = ++_thumbnailGeneration;
    _resetPendingKinds();
    _resetAdjustmentValues();
    state = state.copyWith(isBusy: true, error: null);
    try {
      final loaded = await _engine.restoreSessionInBackground(bytes, recipeJson);
      final profiles = await _engine.filmProfilesInBackground();
      _applyLoadedState(bytes, loaded, profiles);
      unawaited(_prewarmThumbnails(loaded.originalPreviewBytes, generation));
    } catch (error) {
      state = state.copyWith(isBusy: false, error: '$error');
    }
  }

  void _applyLoadedState(
    Uint8List bytes,
    EngineLoadResult loaded,
    List<EngineFilmProfile> profiles,
  ) {
    state = state.copyWith(
      originalBytes: bytes,
      originalPreviewBytes: loaded.originalPreviewBytes,
      previewBytes: loaded.previewBytes,
      histogram: loaded.histogram,
      filterPreviews: const {},
      filmProfiles: profiles,
      filmProfilePreviews: const {},
      selectedFilter: 'brightness',
      selectedCreativeFilter: '',
      selectedFilmProfile: '',
      value: _adjustmentValues['brightness'] ?? 1,
      creativeFilterValue: 1,
      filmProfileStrength: 1,
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
    if (tool == EditorTool.film && state.filmProfilePreviews.isEmpty) {
      await refreshFilmProfilePreviews();
    }
  }

  void selectFilter(String filter) {
    if (state.isBusy) return;
    state = state.copyWith(
      selectedFilter: filter,
      selectedCreativeFilter: '',
      selectedFilmProfile: '',
      value: _adjustmentValues[filter] ?? defaultAdjustmentValue(filter),
      creativeFilterValue: 1,
      filmProfileStrength: 1,
      isAdjusting: false,
      error: null,
    );
  }

  Future<void> _prewarmThumbnails(Uint8List source, int generation) async {
    await Future.wait([
      _generateFilterPreviews(source, generation: generation),
      _generateFilmPreviews(source, generation: generation),
    ]);
  }

  Future<void> refreshFilterPreviews() async {
    if (state.filterPreviews.isNotEmpty || state.isGeneratingFilterPreviews) return;
    final source = state.originalPreviewBytes;
    if (source == null) return;
    await _generateFilterPreviews(source, generation: _thumbnailGeneration);
  }

  Future<void> refreshFilmProfilePreviews() async {
    if (state.filmProfilePreviews.isNotEmpty || state.isGeneratingFilmPreviews) return;
    final source = state.originalPreviewBytes;
    if (source == null || state.filmProfiles.isEmpty) return;
    await _generateFilmPreviews(source, generation: _thumbnailGeneration);
  }

  Future<void> _generateFilterPreviews(
    Uint8List source, {
    required int generation,
  }) async {
    if (generation != _thumbnailGeneration) return;
    state = state.copyWith(isGeneratingFilterPreviews: true, error: null);
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
      state = state.copyWith(isGeneratingFilterPreviews: false, error: '$error');
    }
  }

  Future<void> _generateFilmPreviews(
    Uint8List source, {
    required int generation,
  }) async {
    if (generation != _thumbnailGeneration || state.filmProfiles.isEmpty) return;
    state = state.copyWith(isGeneratingFilmPreviews: true, error: null);
    try {
      final previews = await _engine.generateFilmProfilePreviews(
        source,
        state.filmProfiles.map((profile) => profile.id).toList(growable: false),
        maxEdge: 160,
      );
      if (generation != _thumbnailGeneration) return;
      state = state.copyWith(
        filmProfilePreviews: previews,
        isGeneratingFilmPreviews: false,
      );
    } catch (error) {
      if (generation != _thumbnailGeneration) return;
      state = state.copyWith(isGeneratingFilmPreviews: false, error: '$error');
    }
  }

  Future<void> applyCreativeFilter(String filter) async {
    if (state.isBusy || state.isGeneratingFilterPreviews) return;
    state = state.copyWith(
      selectedCreativeFilter: filter,
      selectedFilmProfile: '',
      creativeFilterValue: 1,
      error: null,
    );
    _queuePreview(_PreviewKind.creative, filter, 1);
  }

  Future<void> updateCreativeFilterValue(double value) async {
    final filter = state.selectedCreativeFilter;
    if (filter.isEmpty || state.isBusy) return;
    state = state.copyWith(creativeFilterValue: value, error: null);
    _queuePreview(_PreviewKind.creative, filter, value);
  }

  Future<void> commitFilterValue(double value) async {
    if (state.isBusy || state.previewBytes == null) return;
    final filter = state.selectedFilter;
    _adjustmentValues[filter] = value;
    state = state.copyWith(value: value, isAdjusting: false, error: null);
    _queuePreview(_PreviewKind.adjust, filter, value);
  }

  Future<void> selectFilmProfile(String id) async {
    if (state.isBusy || state.isGeneratingFilmPreviews) return;
    state = state.copyWith(
      selectedFilmProfile: id,
      selectedCreativeFilter: '',
      filmProfileStrength: 1,
      error: null,
    );
    _queuePreview(_PreviewKind.film, id, 1);
  }

  Future<void> updateFilmProfileStrength(double value) async {
    final profile = state.selectedFilmProfile;
    if (profile.isEmpty || state.isBusy) return;
    state = state.copyWith(filmProfileStrength: value, error: null);
    _queuePreview(_PreviewKind.film, profile, value);
  }

  void _queuePreview(_PreviewKind kind, String key, double value) {
    final requestId = ++_latestPreviewRequestId;
    _pendingPreview = (
      requestId: requestId,
      kind: kind,
      key: key,
      value: value,
    );
    state = state.copyWith(isPreviewProcessing: true, error: null);
    if (!_previewWorkerRunning) {
      unawaited(_drainPreviewQueue());
    }
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
            _PreviewKind.adjust || _PreviewKind.creative =>
              _hasPendingFilterOperation
                  ? await _engine.replaceFilterValue(request.key, request.value)
                  : await _engine.commitFilterValue(request.key, request.value),
            _PreviewKind.film => _hasPendingFilmOperation
                ? await _engine.replaceFilmProfile(request.key, request.value)
                : await _engine.applyFilmProfile(request.key, request.value),
          };

          if (request.kind == _PreviewKind.film) {
            _hasPendingFilmOperation = true;
          } else {
            _hasPendingFilterOperation = true;
          }

          if (request.requestId == _latestPreviewRequestId) {
            _applyBackgroundResult(
              result,
              value: request.kind == _PreviewKind.adjust ? request.value : null,
              clearCreativeSelection: request.kind != _PreviewKind.creative,
              clearFilmSelection: request.kind != _PreviewKind.film,
            );
            state = state.copyWith(isPreviewProcessing: _pendingPreview != null);
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
    if (state.isBusy || state.isPreviewProcessing || !state.hasUnappliedEdits) return;
    final generation = ++_thumbnailGeneration;
    state = state.copyWith(isBusy: true, error: null);
    try {
      final result = await _engine.applyEditsInBackground();
      _resetPendingKinds();
      _resetAdjustmentValues();
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
        processingMs: result.elapsedMicros.toDouble() / 1000.0,
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
    if (state.isBusy || state.isPreviewProcessing || !state.hasUnappliedEdits) return;
    state = state.copyWith(isBusy: true, error: null);
    try {
      final result = await _engine.discardEditsInBackground();
      _resetPendingKinds();
      _resetAdjustmentValues();
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
        processingMs: result.elapsedMicros.toDouble() / 1000.0,
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
    await _applyBackgroundTransform(_engine.flipHorizontalInBackground);
  }

  Future<void> flipVertical() async {
    if (state.isBusy || state.isPreviewProcessing) return;
    _resetPendingKinds();
    await _applyBackgroundTransform(_engine.flipVerticalInBackground);
  }

  Future<void> commitStraighten(double degrees) async {
    if (degrees.abs() < 0.01 || state.isBusy || state.isPreviewProcessing) return;
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
    if (state.isBusy || state.isExporting || state.isPreviewProcessing) {
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
    return _engine.applyFilterTimed(input, state.selectedFilter, state.value);
  }

  Future<void> undo() async {
    if (!state.canUndo || state.isBusy || state.isPreviewProcessing) return;
    _resetPendingKinds();
    await _applyBackgroundTransform(_engine.undoInBackground);
  }

  Future<void> redo() async {
    if (!state.canRedo || state.isBusy || state.isPreviewProcessing) return;
    _resetPendingKinds();
    await _applyBackgroundTransform(_engine.redoInBackground);
  }

  Future<void> _applyBackgroundTransform(
    Future<EngineCommitResult> Function() action,
  ) async {
    if (state.isBusy || state.isPreviewProcessing) return;
    state = state.copyWith(isBusy: true, error: null);
    try {
      final result = await action();
      _applyBackgroundResult(
        result,
        clearCreativeSelection: true,
        clearFilmSelection: true,
      );
      unawaited(_persistSession());
    } catch (error) {
      state = state.copyWith(isBusy: false, error: '$error');
    }
  }

  void _applyBackgroundResult(
    EngineCommitResult result, {
    double? value,
    required bool clearCreativeSelection,
    required bool clearFilmSelection,
  }) {
    state = state.copyWith(
      previewBytes: result.bytes,
      histogram: result.histogram,
      value: value,
      selectedCreativeFilter:
          clearCreativeSelection ? '' : state.selectedCreativeFilter,
      creativeFilterValue:
          clearCreativeSelection ? 1 : state.creativeFilterValue,
      selectedFilmProfile: clearFilmSelection ? '' : state.selectedFilmProfile,
      filmProfileStrength:
          clearFilmSelection ? 1 : state.filmProfileStrength,
      processingMs: result.elapsedMicros.toDouble() / 1000.0,
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
    _hasPendingFilterOperation = false;
    _hasPendingFilmOperation = false;
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
        await _sessionStore.save(originalBytes: original, recipeJson: recipe);
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

final editorProvider = StateNotifierProvider<EditorController, EditorState>(
  (ref) => EditorController(
    ref.watch(imageEngineProvider),
    ref.watch(editorSessionStoreProvider),
  ),
);
