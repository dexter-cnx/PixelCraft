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

  Future<void> load(Uint8List bytes) async {
    state = state.copyWith(isBusy: true, error: null);
    try {
      _engine.loadImage(bytes);
      final preview = _engine.preparePreview(bytes, maxEdge: 1280);
      final originalPreview = _engine.originalPreview();
      final session = _engine.sessionInfo();
      state = state.copyWith(
        originalBytes: bytes,
        originalPreviewBytes: originalPreview,
        previewBytes: preview,
        histogram: _engine.getHistogram(preview),
        filterPreviews: const {},
        selectedCreativeFilter: '',
        isBusy: false,
        operationCount: session.operationCount,
        cursor: session.cursor,
        canUndo: session.canUndo,
        canRedo: session.canRedo,
      );
    } catch (error) {
      state = state.copyWith(isBusy: false, error: '$error');
    }
  }

  Future<void> selectTool(EditorTool tool) async {
    if (state.isBusy) return;
    state = state.copyWith(selectedTool: tool, error: null);
    if (tool == EditorTool.filters) {
      await refreshFilterPreviews();
    }
  }

  void selectFilter(String filter) {
    if (state.isBusy) return;
    state = state.copyWith(
      selectedFilter: filter,
      value: filter == 'gaussian_blur' ? 0 : 1,
      isAdjusting: false,
      error: null,
    );
  }

  Future<void> refreshFilterPreviews() async {
    final source = state.previewBytes;
    if (source == null || state.isBusy) return;

    final generation = ++_filterPreviewGeneration;
    state = state.copyWith(isGeneratingFilterPreviews: true, error: null);
    try {
      final previews = await _engine.generateFilterPreviews(
        source,
        creativeFilters,
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

  /// Creative filters have no default selection. Tapping a preview commits that
  /// filter immediately at full strength, with no additional slider gesture.
  Future<void> applyCreativeFilter(String filter) async {
    if (state.isBusy || state.isGeneratingFilterPreviews) return;
    state = state.copyWith(
      selectedCreativeFilter: filter,
      selectedFilter: filter,
      value: 1,
      isBusy: true,
      error: null,
    );
    try {
      final result = await _engine.commitFilterValue(filter, 1);
      _applyBackgroundResult(result, value: 1);
      if (state.selectedTool == EditorTool.filters) {
        unawaited(refreshFilterPreviews());
      }
    } catch (error) {
      state = state.copyWith(isBusy: false, error: '$error');
    }
  }

  /// Commits exactly one adjust-filter operation after the user releases the slider.
  /// No Rust processing occurs while the thumb is moving.
  Future<void> commitFilterValue(double value) async {
    if (state.isBusy || state.previewBytes == null) return;
    state = state.copyWith(isBusy: true, isAdjusting: false, error: null);
    try {
      final result = await _engine.commitFilterValue(state.selectedFilter, value);
      _applyBackgroundResult(result, value: value);
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
    await _applyBackgroundTransform(
      () => _engine.applyCropInBackground(
        x: (1 - width) / 2,
        y: (1 - height) / 2,
        width: width,
        height: height,
      ),
    );
  }

  Future<void> rotateLeft() =>
      _applyBackgroundTransform(() => _engine.rotateQuarterTurnsInBackground(3));

  Future<void> rotateRight() =>
      _applyBackgroundTransform(() => _engine.rotateQuarterTurnsInBackground(1));

  Future<void> flipHorizontal() =>
      _applyBackgroundTransform(_engine.flipHorizontalInBackground);

  Future<void> flipVertical() =>
      _applyBackgroundTransform(_engine.flipVerticalInBackground);

  Future<void> commitStraighten(double degrees) async {
    if (degrees.abs() < 0.01 || state.isBusy) return;
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
    await _applyBackgroundTransform(_engine.undoInBackground);
  }

  Future<void> redo() async {
    if (!state.canRedo || state.isBusy) return;
    await _applyBackgroundTransform(_engine.redoInBackground);
  }

  Future<void> _applyBackgroundTransform(
    Future<EngineCommitResult> Function() action,
  ) async {
    if (state.isBusy) return;
    state = state.copyWith(isBusy: true, error: null);
    try {
      final result = await action();
      _applyBackgroundResult(result);
    } catch (error) {
      state = state.copyWith(isBusy: false, error: '$error');
    }
  }

  void _applyBackgroundResult(EngineCommitResult result, {double? value}) {
    _filterPreviewGeneration++;
    state = state.copyWith(
      previewBytes: result.bytes,
      histogram: result.histogram,
      filterPreviews: const {},
      value: value,
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
  }
}

final imageEngineProvider = Provider<ImageEngine>(
  (ref) => const RustImageEngine(),
);

final editorProvider = StateNotifierProvider<EditorController, EditorState>(
  (ref) => EditorController(ref.watch(imageEngineProvider)),
);
