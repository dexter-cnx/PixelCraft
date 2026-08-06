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

class EditorState {
  const EditorState({
    this.originalBytes,
    this.originalPreviewBytes,
    this.previewBytes,
    this.histogram = const [],
    this.selectedFilter = 'brightness',
    this.value = 1,
    this.processingMs = 0,
    this.isBusy = false,
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
  final String selectedFilter;
  final double value;
  final double processingMs;
  final bool isBusy;
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
    String? selectedFilter,
    double? value,
    double? processingMs,
    bool? isBusy,
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
        selectedFilter: selectedFilter ?? this.selectedFilter,
        value: value ?? this.value,
        processingMs: processingMs ?? this.processingMs,
        isBusy: isBusy ?? this.isBusy,
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

  Future<void> load(Uint8List bytes) async {
    state = state.copyWith(isBusy: true, error: null);
    try {
      _engine.loadImage(bytes);
      final preview = _engine.preparePreview(bytes, maxEdge: 1280);
      final originalPreview = _engine.originalPreview();
      final histogram = _engine.getHistogram(preview);
      final session = _engine.sessionInfo();
      state = state.copyWith(
        originalBytes: bytes,
        originalPreviewBytes: originalPreview,
        previewBytes: preview,
        histogram: histogram,
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

  void selectFilter(String filter) {
    if (state.isAdjusting) {
      try {
        _engine.cancelFilter();
      } catch (_) {
        // Selection remains responsive even if no transaction exists.
      }
    }
    state = state.copyWith(
      selectedFilter: filter,
      value: filter == 'gaussian_blur' ? 0 : 1,
      isAdjusting: false,
      error: null,
    );
  }

  void beginAdjustment(double _) {
    try {
      _engine.beginFilter(state.selectedFilter);
      state = state.copyWith(isAdjusting: true, error: null);
    } catch (error) {
      state = state.copyWith(isAdjusting: false, error: '$error');
    }
  }

  void previewValue(double value) {
    if (!state.isAdjusting) return;
    try {
      final result = _engine.updateFilterPreview(state.selectedFilter, value);
      state = state.copyWith(
        previewBytes: result.bytes,
        histogram: _engine.getHistogram(result.bytes),
        value: value,
        processingMs: result.elapsedMicros.toDouble() / 1000.0,
        error: null,
      );
    } catch (error) {
      state = state.copyWith(error: '$error');
    }
  }

  void commitAdjustment(double value) {
    if (!state.isAdjusting) return;
    try {
      final bytes = _engine.commitFilter();
      _applyCommittedPreview(bytes, value: value);
    } catch (error) {
      state = state.copyWith(isAdjusting: false, error: '$error');
    }
  }

  void setShowOriginal(bool value) {
    state = state.copyWith(showOriginal: value);
  }

  Uint8List exportImage({required String format, required int quality}) {
    state = state.copyWith(isExporting: true, error: null);
    try {
      return _engine.exportImage(format: format, quality: quality);
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

  void undo() {
    if (!state.canUndo) return;
    try {
      _applyCommittedPreview(_engine.undo());
    } catch (error) {
      state = state.copyWith(error: '$error');
    }
  }

  void redo() {
    if (!state.canRedo) return;
    try {
      _applyCommittedPreview(_engine.redo());
    } catch (error) {
      state = state.copyWith(error: '$error');
    }
  }

  void _applyCommittedPreview(Uint8List bytes, {double? value}) {
    final session = _engine.sessionInfo();
    state = state.copyWith(
      previewBytes: bytes,
      histogram: _engine.getHistogram(bytes),
      value: value,
      isAdjusting: false,
      operationCount: session.operationCount,
      cursor: session.cursor,
      canUndo: session.canUndo,
      canRedo: session.canRedo,
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
