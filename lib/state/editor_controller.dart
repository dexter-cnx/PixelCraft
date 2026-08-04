import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../src/rust/api.dart' as rust;

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
  EditorController() : super(const EditorState());

  Future<void> load(Uint8List bytes) async {
    state = state.copyWith(isBusy: true, error: null);
    try {
      rust.loadImage(bytes: bytes);
      final preview = rust.preparePreview(imageBytes: bytes, maxEdge: 1280);
      final histogram = rust.getHistogram(imageBytes: preview);
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
        rust.cancelFilter();
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
      rust.beginFilter(filter: state.selectedFilter);
      state = state.copyWith(isAdjusting: true, error: null);
    } catch (error) {
      state = state.copyWith(isAdjusting: false, error: '$error');
    }
  }

  /// Renders from the immutable Rust-side transaction base. Intermediate
  /// values do not create history entries and do not compound on each other.
  void previewValue(double value) {
    if (!state.isAdjusting) return;
    try {
      final result = rust.updateFilterPreview(
        filter: state.selectedFilter,
        value: value,
      );
      final histogram = rust.getHistogram(imageBytes: result.bytes);
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
      final bytes = rust.commitFilter();
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

  /// Stateless call used only by the benchmark dialog.
  rust.ProcessedImage benchmarkCurrentFilter() {
    final input = state.previewBytes;
    if (input == null) {
      throw StateError('No preview loaded');
    }
    return rust.applyFilterTimed(
      imageBytes: input,
      filter: state.selectedFilter,
      value: state.value,
    );
  }

  void undo() {
    try {
      final bytes = rust.undo();
      state = state.copyWith(
        previewBytes: bytes,
        histogram: rust.getHistogram(imageBytes: bytes),
        isAdjusting: false,
        error: null,
      );
    } catch (error) {
      state = state.copyWith(error: '$error');
    }
  }

  void redo() {
    try {
      final bytes = rust.redo();
      state = state.copyWith(
        previewBytes: bytes,
        histogram: rust.getHistogram(imageBytes: bytes),
        isAdjusting: false,
        error: null,
      );
    } catch (error) {
      state = state.copyWith(error: '$error');
    }
  }
}

final editorProvider = StateNotifierProvider<EditorController, EditorState>(
  (ref) => EditorController(),
);
