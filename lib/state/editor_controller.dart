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
    this.selectedFilter = 'brightness',
    this.selectedTool = EditorTool.adjust,
    this.value = 1,
    this.straightenDegrees = 0,
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
  final EditorTool selectedTool;
  final double value;
  final double straightenDegrees;
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
    EditorTool? selectedTool,
    double? value,
    double? straightenDegrees,
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
        selectedTool: selectedTool ?? this.selectedTool,
        value: value ?? this.value,
        straightenDegrees: straightenDegrees ?? this.straightenDegrees,
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
      final session = _engine.sessionInfo();
      state = state.copyWith(
        originalBytes: bytes,
        originalPreviewBytes: originalPreview,
        previewBytes: preview,
        histogram: _engine.getHistogram(preview),
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

  void selectTool(EditorTool tool) {
    state = state.copyWith(selectedTool: tool, error: null);
  }

  void selectFilter(String filter) {
    if (state.isAdjusting) {
      try {
        _engine.cancelFilter();
      } catch (_) {}
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
      _applyCommittedPreview(_engine.commitFilter(), value: value);
    } catch (error) {
      state = state.copyWith(isAdjusting: false, error: '$error');
    }
  }

  void applyCenteredCrop(double aspectRatio) {
    try {
      double width = 1;
      double height = 1;
      if (aspectRatio >= 1) {
        height = 1 / aspectRatio;
      } else {
        width = aspectRatio;
      }
      _applyCommittedPreview(
        _engine.applyCrop(
          x: (1 - width) / 2,
          y: (1 - height) / 2,
          width: width,
          height: height,
        ),
      );
    } catch (error) {
      state = state.copyWith(error: '$error');
    }
  }

  void rotateLeft() => _applyTransform(() => _engine.rotateQuarterTurns(3));
  void rotateRight() => _applyTransform(() => _engine.rotateQuarterTurns(1));
  void flipHorizontal() => _applyTransform(_engine.flipHorizontal);
  void flipVertical() => _applyTransform(_engine.flipVertical);

  void commitStraighten(double degrees) {
    if (degrees.abs() < 0.01) return;
    _applyTransform(() => _engine.straighten(degrees));
    state = state.copyWith(straightenDegrees: 0);
  }

  void setStraightenPreview(double degrees) {
    state = state.copyWith(straightenDegrees: degrees);
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
    _applyTransform(_engine.undo);
  }

  void redo() {
    if (!state.canRedo) return;
    _applyTransform(_engine.redo);
  }

  void _applyTransform(Uint8List Function() action) {
    try {
      _applyCommittedPreview(action());
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
