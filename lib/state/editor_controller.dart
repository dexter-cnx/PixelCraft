import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

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

enum EditorTool { adjust, filters, crop, rotate, details }

class EditorState {
  const EditorState({
    this.originalBytes,
    this.originalPreviewBytes,
    this.previewBytes,
    this.histogram = const [],
    this.filterPreviews = const {},
    this.selectedFilter = 'brightness',
    this.selectedCreativeFilter = '',
    this.selectedTool = EditorTool.adjust,
    this.value = 1,
    this.creativeFilterValue = 1,
    this.straightenDegrees = 0,
    this.processingMs = 0,
    this.isBusy = false,
    this.isGeneratingFilterPreviews = false,
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
  final String selectedFilter;
  final String selectedCreativeFilter;
  final EditorTool selectedTool;
  final double value;
  final double creativeFilterValue;
  final double straightenDegrees;
  final double processingMs;
  final bool isBusy;
  final bool isGeneratingFilterPreviews;
  final bool isAdjusting;
  final bool showOriginal;
  final bool isExporting;
  final int operationCount;
  final int cursor;
  final bool canUndo;
  final bool canRedo;
  final String? error;

  /// Operations after the last Apply checkpoint are drafts until promoted.
  bool get hasUnappliedEdits => cursor > 0;

  Uint8List? get visiblePreview =>
      showOriginal ? originalPreviewBytes ?? previewBytes : previewBytes;

  EditorState copyWith({
    Uint8List? originalBytes,
    Uint8List? originalPreviewBytes,
    Uint8List? previewBytes,
    List<int>? histogram,
    Map<String, Uint8List>? filterPreviews,
    String? selectedFilter,
    String? selectedCreativeFilter,
    EditorTool? selectedTool,
    double? value,
    double? creativeFilterValue,
    double? straightenDegrees,
    double? processingMs,
    bool? isBusy,
    bool? isGeneratingFilterPreviews,
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
        selectedFilter: selectedFilter ?? this.selectedFilter,
        selectedCreativeFilter:
            selectedCreativeFilter ?? this.selectedCreativeFilter,
        selectedTool: selectedTool ?? this.selectedTool,
        value: value ?? this.value,
        creativeFilterValue: creativeFilterValue ?? this.creativeFilterValue,
        straightenDegrees: straightenDegrees ?? this.straightenDegrees,
        processingMs: processingMs ?? this.processingMs,
        isBusy: isBusy ?? this.isBusy,
        isGeneratingFilterPreviews:
            isGeneratingFilterPreviews ?? this.isGeneratingFilterPreviews,
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
  EditorController(this._engine) : super(const EditorState());

  final ImageEngine _engine;
  int _filterPreviewGeneration = 0;
  bool _hasPendingFilterOperation = false;

  Future<void> load(Uint8List bytes) async {
    final generation = ++_filterPreviewGeneration;
    _hasPendingFilterOperation = false;
    state = state.copyWith(isBusy: true, error: null);
    try {
      final loaded = await _engine.loadImageInBackground(
        bytes,
        maxEdge: editorPreviewMaxEdge,
      );
      state = state.copyWith(
        originalBytes: bytes,
        originalPreviewBytes: loaded.originalPreviewBytes,
        previewBytes: loaded.previewBytes,
        histogram: loaded.histogram,
        filterPreviews: const {},
        selectedFilter: 'brightness',
        selectedCreativeFilter: '',
        value: 1,
        creativeFilterValue: 1,
        straightenDegrees: 0,
        isBusy: false,
        isGeneratingFilterPreviews: false,
        operationCount: loaded.session.operationCount,
        cursor: loaded.session.cursor,
        canUndo: loaded.session.canUndo,
        canRedo: loaded.session.canRedo,
      );

      // Prewarm tiny creative-filter thumbnails from the reduced checkpoint.
      unawaited(
        _generateFilterPreviews(
          loaded.originalPreviewBytes,
          generation: generation,
        ),
      );
    } catch (error) {
      state = state.copyWith(isBusy: false, error: '$error');
    }
  }

  Future<void> selectTool(EditorTool tool) async {
    if (state.isBusy) return;
    state = state.copyWith(selectedTool: tool, error: null);
    if (tool == EditorTool.filters &&
        state.filterPreviews.isEmpty &&
        !state.isGeneratingFilterPreviews) {
      await refreshFilterPreviews();
    }
  }

  void selectFilter(String filter) {
    if (state.isBusy) return;
    state = state.copyWith(
      selectedFilter: filter,
      selectedCreativeFilter: '',
      value: filter == 'gaussian_blur' ? 0 : 1,
      creativeFilterValue: 1,
      isAdjusting: false,
      error: null,
    );
  }

  Future<void> refreshFilterPreviews() async {
    if (state.filterPreviews.isNotEmpty || state.isGeneratingFilterPreviews) {
      return;
    }
    final source = state.originalPreviewBytes;
    if (source == null) return;
    await _generateFilterPreviews(
      source,
      generation: _filterPreviewGeneration,
    );
  }

  Future<void> _generateFilterPreviews(
    Uint8List source, {
    required int generation,
  }) async {
    if (generation != _filterPreviewGeneration) return;
    state = state.copyWith(isGeneratingFilterPreviews: true, error: null);
    try {
      final previews = await _engine.generateFilterPreviews(
        source,
        creativeFilters,
        maxEdge: 180,
      );
      if (generation != _filterPreviewGeneration) return;
      state = state.copyWith(
        filterPreviews: previews,
        isGeneratingFilterPreviews: false,
      );
    } catch (error) {
      if (generation != _filterPreviewGeneration) return;
      state = state.copyWith(
        isGeneratingFilterPreviews: false,
        error: '$error',
      );
    }
  }

  /// Selects a creative filter as a draft. Choosing another filter or changing
  /// intensity replaces the same pending filter operation instead of stacking.
  Future<void> applyCreativeFilter(String filter) async {
    if (state.isBusy || state.isGeneratingFilterPreviews) return;
    state = state.copyWith(
      selectedCreativeFilter: filter,
      creativeFilterValue: 1,
      isBusy: true,
      error: null,
    );
    try {
      final result = _hasPendingFilterOperation
          ? await _engine.replaceFilterValue(filter, 1)
          : await _engine.commitFilterValue(filter, 1);
      _hasPendingFilterOperation = true;
      _applyBackgroundResult(result, clearCreativeSelection: false);
      state = state.copyWith(
        selectedCreativeFilter: filter,
        creativeFilterValue: 1,
      );
    } catch (error) {
      state = state.copyWith(isBusy: false, error: '$error');
    }
  }

  Future<void> updateCreativeFilterValue(double value) async {
    final filter = state.selectedCreativeFilter;
    if (filter.isEmpty || state.isBusy) return;
    state = state.copyWith(
      creativeFilterValue: value,
      isBusy: true,
      error: null,
    );
    try {
      final result = _hasPendingFilterOperation
          ? await _engine.replaceFilterValue(filter, value)
          : await _engine.commitFilterValue(filter, value);
      _hasPendingFilterOperation = true;
      _applyBackgroundResult(result, clearCreativeSelection: false);
      state = state.copyWith(
        selectedCreativeFilter: filter,
        creativeFilterValue: value,
      );
    } catch (error) {
      state = state.copyWith(isBusy: false, error: '$error');
    }
  }

  /// Adjust sliders create a draft operation. Releasing the slider again
  /// replaces that operation until Apply is pressed.
  Future<void> commitFilterValue(double value) async {
    if (state.isBusy || state.previewBytes == null) return;
    state = state.copyWith(isBusy: true, isAdjusting: false, error: null);
    try {
      final result = _hasPendingFilterOperation
          ? await _engine.replaceFilterValue(state.selectedFilter, value)
          : await _engine.commitFilterValue(state.selectedFilter, value);
      _hasPendingFilterOperation = true;
      _applyBackgroundResult(
        result,
        value: value,
        clearCreativeSelection: true,
      );
    } catch (error) {
      state = state.copyWith(isBusy: false, error: '$error');
    }
  }

  /// Apply only promotes the reduced working preview to a checkpoint. Rust
  /// retains the complete operation recipe; full-resolution replay is deferred
  /// until Export, so Apply stays fast even for large source images.
  Future<void> applyEdits() async {
    if (state.isBusy || !state.hasUnappliedEdits) return;
    final generation = ++_filterPreviewGeneration;
    state = state.copyWith(isBusy: true, error: null);
    try {
      final result = await _engine.applyEditsInBackground();
      _hasPendingFilterOperation = false;
      state = state.copyWith(
        originalPreviewBytes: result.bytes,
        previewBytes: result.bytes,
        histogram: result.histogram,
        filterPreviews: const {},
        selectedFilter: 'brightness',
        selectedCreativeFilter: '',
        value: 1,
        creativeFilterValue: 1,
        straightenDegrees: 0,
        processingMs: result.elapsedMicros.toDouble() / 1000.0,
        isBusy: false,
        isGeneratingFilterPreviews: false,
        isAdjusting: false,
        operationCount: result.session.operationCount,
        cursor: result.session.cursor,
        canUndo: result.session.canUndo,
        canRedo: result.session.canRedo,
        error: null,
      );
      unawaited(
        _generateFilterPreviews(result.bytes, generation: generation),
      );
    } catch (error) {
      state = state.copyWith(isBusy: false, error: '$error');
    }
  }

  Future<void> cancelEdits() async {
    if (state.isBusy || !state.hasUnappliedEdits) return;
    state = state.copyWith(isBusy: true, error: null);
    try {
      final result = await _engine.discardEditsInBackground();
      _hasPendingFilterOperation = false;
      state = state.copyWith(
        previewBytes: result.bytes,
        histogram: result.histogram,
        selectedFilter: 'brightness',
        selectedCreativeFilter: '',
        value: 1,
        creativeFilterValue: 1,
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
    } catch (error) {
      state = state.copyWith(isBusy: false, error: '$error');
    }
  }

  Future<void> applyCenteredCrop(double aspectRatio) async {
    if (state.isBusy) return;
    double width = 1;
    double height = 1;
    if (aspectRatio >= 1) {
      height = 1 / aspectRatio;
    } else {
      width = aspectRatio;
    }
    _hasPendingFilterOperation = false;
    await _applyBackgroundTransform(
      () => _engine.applyCropInBackground(
        x: (1 - width) / 2,
        y: (1 - height) / 2,
        width: width,
        height: height,
      ),
    );
  }

  Future<void> rotateLeft() {
    _hasPendingFilterOperation = false;
    return _applyBackgroundTransform(
      () => _engine.rotateQuarterTurnsInBackground(3),
    );
  }

  Future<void> rotateRight() {
    _hasPendingFilterOperation = false;
    return _applyBackgroundTransform(
      () => _engine.rotateQuarterTurnsInBackground(1),
    );
  }

  Future<void> flipHorizontal() {
    _hasPendingFilterOperation = false;
    return _applyBackgroundTransform(_engine.flipHorizontalInBackground);
  }

  Future<void> flipVertical() {
    _hasPendingFilterOperation = false;
    return _applyBackgroundTransform(_engine.flipVerticalInBackground);
  }

  Future<void> commitStraighten(double degrees) async {
    if (degrees.abs() < 0.01 || state.isBusy) return;
    _hasPendingFilterOperation = false;
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
    if (state.isBusy || state.isExporting) {
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
    if (!state.canUndo || state.isBusy) return;
    _hasPendingFilterOperation = false;
    await _applyBackgroundTransform(_engine.undoInBackground);
  }

  Future<void> redo() async {
    if (!state.canRedo || state.isBusy) return;
    _hasPendingFilterOperation = false;
    await _applyBackgroundTransform(_engine.redoInBackground);
  }

  Future<void> _applyBackgroundTransform(
    Future<EngineCommitResult> Function() action,
  ) async {
    if (state.isBusy) return;
    state = state.copyWith(isBusy: true, error: null);
    try {
      final result = await action();
      _applyBackgroundResult(result, clearCreativeSelection: true);
    } catch (error) {
      state = state.copyWith(isBusy: false, error: '$error');
    }
  }

  void _applyBackgroundResult(
    EngineCommitResult result, {
    double? value,
    required bool clearCreativeSelection,
  }) {
    state = state.copyWith(
      previewBytes: result.bytes,
      histogram: result.histogram,
      value: value,
      selectedCreativeFilter:
          clearCreativeSelection ? '' : state.selectedCreativeFilter,
      creativeFilterValue:
          clearCreativeSelection ? 1 : state.creativeFilterValue,
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
}

final imageEngineProvider = Provider<ImageEngine>(
  (ref) => const RustImageEngine(),
);

final editorProvider = StateNotifierProvider<EditorController, EditorState>(
  (ref) => EditorController(ref.watch(imageEngineProvider)),
);
