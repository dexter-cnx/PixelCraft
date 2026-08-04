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
    this.previewBytes,
    this.histogram = const [],
    this.selectedFilter = 'brightness',
    this.value = 1,
    this.processingMs = 0,
    this.isBusy = false,
    this.isAdjusting = false,
    this.error,
  });

  final Uint8List? originalBytes;
  final Uint8List? previewBytes;
  final List<int> histogram;
  final String selectedFilter;
  final double value;
  final double processingMs;
  final bool isBusy;
  final bool isAdjusting;
  final String? error;

  EditorState copyWith({
    Uint8List? originalBytes,
    Uint8List? previewBytes,
    List<int>? histogram,
    String? selectedFilter,
    double? value,
    double? processingMs,
    bool? isBusy,
    bool? isAdjusting,
    String? error,
  }) =>
      EditorState(
        originalBytes: originalBytes ?? this.originalBytes,
        previewBytes: previewBytes ?? this.previewBytes,
        histogram: histogram ?? this.histogram,
        selectedFilter: selectedFilter ?? this.selectedFilter,
        value: value ?? this.value,
        processingMs: processingMs ?? this.processingMs,
        isBusy: isBusy ?? this.isBusy,
        isAdjusting: isAdjusting ?? this.isAdjusting,
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
      final histogram = _engine.getHistogram(preview);
      state = state.copyWith(
        originalBytes: bytes,
        previewBytes: preview,
        histogram: histogram,
        isBusy: false,
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
        // Selection should remain responsive even if no transaction exists.
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
      final result = _engine.updateFilterPreview(
        state.selectedFilter,
        value,
      );
      final histogram = _engine.getHistogram(result.bytes);
      state = state.copyWith(
        previewBytes: result.bytes,
        histogram: histogram,
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
      state = state.copyWith(
        previewBytes: bytes,
        value: value,
        isAdjusting: false,
        error: null,
      );
    } catch (error) {
      state = state.copyWith(isAdjusting: false, error: '$error');
    }
  }

  EngineResult benchmarkCurrentFilter() {
    final input = state.previewBytes;
    if (input == null) {
      throw StateError('No preview loaded');
    }
    return _engine.applyFilterTimed(
      input,
      state.selectedFilter,
      state.value,
    );
  }

  void undo() {
    try {
      final bytes = _engine.undo();
      state = state.copyWith(
        previewBytes: bytes,
        histogram: _engine.getHistogram(bytes),
        isAdjusting: false,
        error: null,
      );
    } catch (error) {
      state = state.copyWith(error: '$error');
    }
  }

  void redo() {
    try {
      final bytes = _engine.redo();
      state = state.copyWith(
        previewBytes: bytes,
        histogram: _engine.getHistogram(bytes),
        isAdjusting: false,
        error: null,
      );
    } catch (error) {
      state = state.copyWith(error: '$error');
    }
  }
}

final imageEngineProvider = Provider<ImageEngine>(
  (ref) => const RustImageEngine(),
);

final editorProvider = StateNotifierProvider<EditorController, EditorState>(
  (ref) => EditorController(ref.watch(imageEngineProvider)),
);
