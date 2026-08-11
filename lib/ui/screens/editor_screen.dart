import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/export_file_service.dart';
import '../../gpu/gpu_editor_adjustment_draft.dart';
import '../../gpu/gpu_editor_preview_bridge.dart';
import '../../gpu/ios_gpu_editor_preview.dart';
import '../../state/editor_controller.dart';
import '../widgets/editor_tool_panel.dart';
import '../widgets/image_preview.dart';

typedef ImageFileLoader = Future<Uint8List> Function(String path);

final imageFileLoaderProvider = Provider<ImageFileLoader>(
  (ref) => (path) => File(path).readAsBytes(),
);

class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({
    super.key,
    this.imageBytes,
    this.imagePath,
    this.recoveryRecipe,
  }) : assert(
          (imageBytes == null) != (imagePath == null),
          'Provide exactly one of imageBytes or imagePath.',
        );

  final List<int>? imageBytes;
  final String? imagePath;
  final String? recoveryRecipe;

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  static const _fileService = ExportFileService();
  static const _gpuEditorIntegration = bool.fromEnvironment(
    'GPU_EDITOR_INTEGRATION',
    defaultValue: true,
  );
  static const _gpuBridge = GpuEditorPreviewBridge();
  static const _gpuCreativeFilters = <String>{
    'grayscale',
    'invert',
    'vintage',
    'oceanic',
    'lofi',
    'dramatic',
    'golden',
    'pastel_pink',
  };
  static const _gpuCreativeComputeFilters = <String>{'grayscale', 'invert'};

  bool _isSavingExport = false;
  bool _isPreparingSource = true;
  String? _sourceError;

  String? _gpuRendererId;
  File? _gpuSourceFile;
  Future<String>? _gpuRendererFuture;
  bool _gpuPreviewActive = false;
  String? _gpuDraftKind;
  String? _gpuDraftKey;
  double _gpuDraftValue = 1;
  String? _gpuAdjustmentRecipeJson;
  String? _gpuOwnedDraftKind;
  String? _gpuOwnedDraftKey;
  int _gpuActivationSerial = 0;
  int _gpuRendererEpoch = 0;

  bool get _gpuIntegrationEligible =>
      _gpuEditorIntegration &&
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    Future.microtask(_initializeEditor);
  }

  @override
  void dispose() {
    _gpuActivationSerial++;
    _gpuRendererEpoch++;
    final rendererId = _gpuRendererId;
    _gpuRendererId = null;
    _gpuRendererFuture = null;
    if (rendererId != null) {
      _gpuBridge.destroyRenderer(rendererId).ignore();
    }
    _gpuSourceFile?.delete().ignore();
    super.dispose();
  }

  Future<void> _initializeEditor() async {
    try {
      final Uint8List bytes;
      final path = widget.imagePath;
      if (path != null) {
        bytes = await ref.read(imageFileLoaderProvider)(path);
      } else {
        final source = widget.imageBytes!;
        bytes = source is Uint8List ? source : Uint8List.fromList(source);
      }

      final controller = ref.read(editorProvider.notifier);
      final recipe = widget.recoveryRecipe;
      if (recipe != null) {
        await controller.restore(bytes, recipe);
      } else {
        await controller.load(bytes);
      }

      if (!mounted) return;
      setState(() => _isPreparingSource = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isPreparingSource = false;
        _sourceError = '$error';
      });
    }
  }

  bool _canUseGpuDraft(EditorState state, String kind, String key) {
    if (!_gpuIntegrationEligible || state.isBusy || state.isPreviewProcessing) {
      return false;
    }
    if (state.originalPreviewBytes == null || state.showOriginal) return false;

    if (kind == 'adjust') {
      return gpuAdjustFilterKeys.contains(key);
    }

    if (kind == 'creative') {
      if (!_gpuCreativeFilters.contains(key) ||
          state.selectedCreativeFilter != key) {
        return false;
      }
      return state.cursor <= 1;
    }

    if (kind == 'film') {
      return state.cursor <= 1 && state.selectedFilmProfile == key;
    }

    return false;
  }

  void _onGpuPreviewStart(String kind, String key, double value) {
    final state = ref.read(editorProvider);
    if (!_canUseGpuDraft(state, kind, key)) return;

    _gpuDraftKind = kind;
    _gpuDraftKey = key;
    _gpuDraftValue = value;
    final serial = ++_gpuActivationSerial;

    if (kind == 'adjust') {
      unawaited(_prepareAdjustGpuPreview(state, serial));
    } else {
      _gpuAdjustmentRecipeJson = null;
      unawaited(_activateGpuPreview(state, serial));
    }
  }

  Future<void> _prepareAdjustGpuPreview(EditorState state, int serial) async {
    try {
      final recipe =
          await ref.read(imageEngineProvider).exportSessionRecipeInBackground();
      if (!mounted || serial != _gpuActivationSerial) return;

      final key = _gpuDraftKey;
      if (key == null) return;
      final draft = GpuEditorAdjustmentDraft.fromRecipeJson(
        recipe,
        transientKey: key,
        transientValue: _gpuDraftValue,
      );
      if (!draft.isRepresentable) {
        debugPrint(
          '[G3 editor GPU] adjust fallback: ${draft.fallbackReason ?? 'unrepresentable draft'}',
        );
        _gpuAdjustmentRecipeJson = null;
        _gpuDraftKind = null;
        _gpuDraftKey = null;
        return;
      }

      _gpuAdjustmentRecipeJson = recipe;
      await _activateGpuPreview(state, serial);
    } catch (error) {
      debugPrint('[G3 editor GPU] adjust recipe unavailable: $error');
      if (mounted && serial == _gpuActivationSerial) {
        _gpuAdjustmentRecipeJson = null;
        _gpuDraftKind = null;
        _gpuDraftKey = null;
      }
    }
  }

  void _onGpuPreviewChanged(String kind, String key, double value) {
    if (_gpuDraftKind != kind || _gpuDraftKey != key) return;
    _gpuDraftValue = value;
    final rendererId = _gpuRendererId;
    if (rendererId != null && _gpuPreviewActive) {
      final serial = _gpuActivationSerial;
      unawaited(_applyGpuDraftSafely(rendererId, serial));
    }
  }

  void _onGpuPreviewCommit(String kind, String key, double value) {
    unawaited(_commitGpuPreview(kind, key, value));
  }

  void _invalidateGpuPreview({
    bool dropRenderer = false,
    bool clearOwnership = false,
    String? reason,
  }) {
    _gpuActivationSerial++;
    _gpuDraftKind = null;
    _gpuDraftKey = null;
    _gpuAdjustmentRecipeJson = null;
    if (clearOwnership) {
      _gpuOwnedDraftKind = null;
      _gpuOwnedDraftKey = null;
    }

    if (dropRenderer) {
      _gpuRendererEpoch++;
      final rendererId = _gpuRendererId;
      _gpuRendererId = null;
      _gpuRendererFuture = null;
      if (rendererId != null) {
        unawaited(_gpuBridge.destroyRenderer(rendererId).catchError((Object error) {
          debugPrint('[G2 editor GPU] renderer cleanup failed: $error');
        }));
      }
    }

    if (reason != null) {
      debugPrint('[G2 editor GPU] invalidated: $reason');
    }
    if (mounted && _gpuPreviewActive) {
      setState(() => _gpuPreviewActive = false);
    } else {
      _gpuPreviewActive = false;
    }
  }

  Future<String> _ensureGpuRenderer() {
    final id = _gpuRendererId;
    if (id != null) return Future.value(id);
    final pending = _gpuRendererFuture;
    if (pending != null) return pending;

    final epoch = _gpuRendererEpoch;
    final future = _gpuBridge.createRenderer().then((id) async {
      if (!mounted || epoch != _gpuRendererEpoch) {
        await _gpuBridge.destroyRenderer(id).catchError((Object error) {
          debugPrint('[G2 editor GPU] stale renderer cleanup failed: $error');
        });
        throw StateError('GPU renderer creation was superseded');
      }
      _gpuRendererId = id;
      _gpuRendererFuture = null;
      return id;
    }, onError: (Object error, StackTrace stack) {
      if (epoch == _gpuRendererEpoch) {
        _gpuRendererFuture = null;
      }
      Error.throwWithStackTrace(error, stack);
    });
    _gpuRendererFuture = future;
    return future;
  }

  Future<void> _activateGpuPreview(EditorState state, int serial) async {
    try {
      final checkpoint = state.originalPreviewBytes;
      if (checkpoint == null) return;

      final rendererId = await _ensureGpuRenderer();
      if (!mounted || serial != _gpuActivationSerial) return;

      final file = File(
        '${Directory.systemTemp.path}/pixelcraft-editor-gpu-${identityHashCode(this)}.png',
      );
      await file.writeAsBytes(checkpoint, flush: true);
      _gpuSourceFile = file;

      await _gpuBridge.setSourcePath(rendererId, file.path);
      if (!mounted || serial != _gpuActivationSerial) return;
      await _applyGpuDraft(rendererId);
      if (!mounted || serial != _gpuActivationSerial) return;

      setState(() => _gpuPreviewActive = true);
    } catch (error) {
      debugPrint('[G2 editor GPU] live preview unavailable: $error');
      if (mounted && serial == _gpuActivationSerial) {
        _invalidateGpuPreview(
          dropRenderer: true,
          reason: 'activation failure',
        );
      }
    }
  }

  Future<void> _applyGpuDraftSafely(String rendererId, int serial) async {
    try {
      await _applyGpuDraft(rendererId);
    } catch (error) {
      debugPrint('[G2 editor GPU] live update failed: $error');
      if (mounted && serial == _gpuActivationSerial) {
        _invalidateGpuPreview(
          dropRenderer: true,
          reason: 'live update failure',
        );
      }
    }
  }

  Future<void> _applyGpuDraft(String rendererId) async {
    final kind = _gpuDraftKind;
    final key = _gpuDraftKey;
    if (kind == null || key == null) return;
    final value = _gpuDraftValue;

    if (kind == 'adjust') {
      final recipe = _gpuAdjustmentRecipeJson;
      if (recipe == null) {
        throw StateError('No authoritative Adjust recipe is available');
      }
      final draft = GpuEditorAdjustmentDraft.fromRecipeJson(
        recipe,
        transientKey: key,
        transientValue: value,
      );
      if (!draft.isRepresentable) {
        throw StateError(
          'Adjust draft is not GPU-representable: ${draft.fallbackReason}',
        );
      }

      await _gpuBridge.setCreative(
        rendererId,
        filterId: '',
        intensity: 0,
      );
      await _gpuBridge.setFilm(
        rendererId,
        profileId: '',
        strength: 0,
      );
      await _gpuBridge.setAdjustments(rendererId, draft.adjustments);
      return;
    }

    if (kind == 'creative') {
      await _gpuBridge.setAdjustments(
        rendererId,
        const GpuEditorAdjustmentState(),
      );
      if (_gpuCreativeComputeFilters.contains(key)) {
        await _gpuBridge.setFilm(
          rendererId,
          profileId: '',
          strength: 0,
        );
        await _gpuBridge.setCreative(
          rendererId,
          filterId: key,
          intensity: value,
        );
      } else {
        await _gpuBridge.setCreative(
          rendererId,
          filterId: '',
          intensity: 0,
        );
        await _gpuBridge.setFilm(
          rendererId,
          profileId: 'creative_$key',
          strength: value,
        );
      }
      return;
    }

    if (kind == 'film') {
      await _gpuBridge.setAdjustments(
        rendererId,
        const GpuEditorAdjustmentState(),
      );
      await _gpuBridge.setCreative(
        rendererId,
        filterId: '',
        intensity: 0,
      );
      await _gpuBridge.setFilm(
        rendererId,
        profileId: key,
        strength: value,
      );
    }
  }

  Future<void> _waitForRustPreviewSettled() async {
    for (var tick = 0; tick < 300; tick++) {
      if (!mounted) return;
      if (!ref.read(editorProvider).isPreviewProcessing) return;
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
  }

  Future<void> _commitGpuPreview(String kind, String key, double value) async {
    final controller = ref.read(editorProvider.notifier);
    final serial = _gpuActivationSerial;
    final wasGpuActive = _gpuPreviewActive &&
        _gpuDraftKind == kind &&
        _gpuDraftKey == key;

    try {
      if (kind == 'adjust') {
        await controller.commitFilterValue(value);
      } else if (kind == 'creative') {
        await controller.updateCreativeFilterValue(value);
      } else if (kind == 'film') {
        await controller.updateFilmProfileStrength(value);
      }
      await _waitForRustPreviewSettled();
      if (!mounted || serial != _gpuActivationSerial) return;
      final settledState = ref.read(editorProvider);
      if (wasGpuActive && settledState.error == null) {
        _gpuOwnedDraftKind = kind;
        _gpuOwnedDraftKey = key;
      }
    } finally {
      if (mounted && wasGpuActive && serial == _gpuActivationSerial) {
        setState(() => _gpuPreviewActive = false);
      }
      if (serial == _gpuActivationSerial) {
        _gpuDraftKind = null;
        _gpuDraftKey = null;
        _gpuAdjustmentRecipeJson = null;
      }
    }
  }

  Future<void> _showExportDialog() async {
    var format = 'png';
    var quality = 92.0;
    final selection = await showDialog<({String format, int quality})>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Export full resolution'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Pixel Craft replays active edits against the original image.'),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                initialValue: format,
                decoration: const InputDecoration(
                  labelText: 'Format',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'png', child: Text('PNG')),
                  DropdownMenuItem(value: 'jpeg', child: Text('JPEG')),
                  DropdownMenuItem(value: 'webp', child: Text('WebP')),
                ],
                onChanged: (value) {
                  if (value != null) setDialogState(() => format = value);
                },
              ),
              if (format == 'jpeg') ...[
                const SizedBox(height: 16),
                Text('Quality ${quality.round()}'),
                Slider(
                  value: quality,
                  min: 40,
                  max: 100,
                  divisions: 12,
                  onChanged: (value) => setDialogState(() => quality = value),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(
                context,
                (format: format, quality: quality.round()),
              ),
              icon: const Icon(Icons.ios_share),
              label: const Text('Export'),
            ),
          ],
        ),
      ),
    );
    if (selection == null || !mounted) return;

    setState(() => _isSavingExport = true);
    try {
      final bytes = await ref.read(editorProvider.notifier).exportImage(
            format: selection.format,
            quality: selection.quality,
          );
      final file = await _fileService.save(bytes, format: selection.format);
      if (!mounted) return;

      final share = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(file.savedToGallery ? 'Saved to Gallery' : 'Export complete'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (file.savedToGallery) ...[
                const Text('The exported image was added to your device photo gallery.'),
                const SizedBox(height: 8),
                const Text('Android album: Pictures/PixelCraft'),
              ] else ...[
                const Text('The image was exported, but Pixel Craft could not add it to the device gallery.'),
                if (file.galleryError != null) ...[
                  const SizedBox(height: 8),
                  Text(file.galleryError!),
                ],
              ],
              const SizedBox(height: 12),
              Text('App backup: ${file.path}', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Done'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.share),
              label: const Text('Share'),
            ),
          ],
        ),
      );
      if (share == true) await _fileService.share(file);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _isSavingExport = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(editorProvider);
    final controller = ref.read(editorProvider.notifier);
    final isProcessing = state.isBusy || _isSavingExport;
    final actionsBlocked = isProcessing || state.isPreviewProcessing;

    ref.listen<EditorState>(editorProvider, (previous, next) {
      if (previous == null) return;
      final toolChanged = previous.selectedTool != next.selectedTool;
      final checkpointChanged =
          !identical(previous.originalPreviewBytes, next.originalPreviewBytes);
      final enteredOriginal = !previous.showOriginal && next.showOriginal;
      final becameBusy = !previous.isBusy && next.isBusy;
      final failed = next.error != null && next.error != previous.error;
      if (!toolChanged &&
          !checkpointChanged &&
          !enteredOriginal &&
          !becameBusy &&
          !failed) {
        return;
      }

      _invalidateGpuPreview(
        clearOwnership: checkpointChanged,
        reason: checkpointChanged
            ? 'Rust checkpoint changed'
            : toolChanged
                ? 'editor tool changed'
                : enteredOriginal
                    ? 'original preview requested'
                    : becameBusy
                        ? 'editor entered busy state'
                        : 'editor reported an error',
      );
    });

    return Scaffold(
      appBar: AppBar(
        title: Text('Editor · ${state.cursor}/${state.operationCount} edits'),
        actions: [
          if (_gpuIntegrationEligible)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Chip(
                avatar: const Icon(Icons.memory_rounded, size: 16),
                label: Text(_gpuPreviewActive ? 'GPU LIVE' : 'GPU READY'),
              ),
            ),
          IconButton(
            onPressed: state.canUndo && !actionsBlocked ? controller.undo : null,
            tooltip: 'Undo',
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            onPressed: state.canRedo && !actionsBlocked ? controller.redo : null,
            tooltip: 'Redo',
            icon: const Icon(Icons.redo),
          ),
          IconButton(
            onPressed: state.previewBytes == null || state.isExporting || actionsBlocked
                ? null
                : _showExportDialog,
            tooltip: 'Export',
            icon: state.isExporting || _isSavingExport
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.ios_share),
          ),
        ],
      ),
      body: SafeArea(
        child: _isPreparingSource
            ? _PreparingPhotoView(
                imagePath: widget.imagePath,
                imageBytes: widget.imageBytes,
              )
            : _sourceError != null
                ? Center(child: Text(_sourceError!))
                : state.previewBytes == null
                    ? Center(
                        child: state.error == null
                            ? const CircularProgressIndicator()
                            : Text(state.error!),
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final canvas = _EditorCanvas(
                            state: state,
                            controller: controller,
                            gpuRendererId: _gpuRendererId,
                            gpuPreviewActive: _gpuPreviewActive,
                          );
                          final tools = EditorToolPanel(
                            state: state,
                            controller: controller,
                            onGpuPreviewStart:
                                _gpuIntegrationEligible ? _onGpuPreviewStart : null,
                            onGpuPreviewChanged:
                                _gpuIntegrationEligible ? _onGpuPreviewChanged : null,
                            onGpuPreviewCommit:
                                _gpuIntegrationEligible ? _onGpuPreviewCommit : null,
                          );
                          final content = constraints.maxWidth >= 900
                              ? Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    children: [
                                      Expanded(flex: 3, child: canvas),
                                      const SizedBox(width: 20),
                                      SizedBox(
                                        width: 360,
                                        child: SingleChildScrollView(child: tools),
                                      ),
                                    ],
                                  ),
                                )
                              : Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                                  child: Column(
                                    children: [
                                      Expanded(child: canvas),
                                      const SizedBox(height: 12),
                                      SingleChildScrollView(child: tools),
                                    ],
                                  ),
                                );

                          return Stack(
                            children: [
                              content,
                              if (isProcessing)
                                Positioned.fill(
                                  child: IgnorePointer(
                                    child: ColoredBox(
                                      color: const Color(0x22000000),
                                      child: Center(
                                        child: Card(
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 20,
                                              vertical: 14,
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const SizedBox.square(
                                                  dimension: 20,
                                                  child: CircularProgressIndicator(strokeWidth: 2),
                                                ),
                                                const SizedBox(width: 12),
                                                Text(
                                                  _isSavingExport
                                                      ? 'Saving to Gallery…'
                                                      : 'Processing image…',
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
      ),
    );
  }
}

class _PreparingPhotoView extends StatelessWidget {
  const _PreparingPhotoView({
    required this.imagePath,
    required this.imageBytes,
  });

  final String? imagePath;
  final List<int>? imageBytes;

  @override
  Widget build(BuildContext context) {
    final image = _sourceImage(context);

    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerLowest,
          child: image,
        ),
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x00000000),
                  Color(0x00000000),
                  Color(0x66000000),
                ],
                stops: [0, 0.55, 1],
              ),
            ),
          ),
        ),
        const Positioned(
          left: 16,
          right: 16,
          bottom: 20,
          child: SafeArea(
            top: false,
            child: Card(
              color: Color(0xE61E1E1E),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Preparing photo…',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Your photo is ready. Setting up editing tools.',
                            style: TextStyle(color: Color(0xCCFFFFFF)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _sourceImage(BuildContext context) {
    final path = imagePath;
    if (path != null) {
      final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
      final logicalWidth = MediaQuery.sizeOf(context).width;
      final cacheWidth = (logicalWidth * devicePixelRatio).round().clamp(720, 1440);
      return Image.file(
        File(path),
        fit: BoxFit.contain,
        cacheWidth: cacheWidth,
        filterQuality: FilterQuality.low,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => const SizedBox.expand(),
      );
    }

    final source = imageBytes;
    if (source != null) {
      final bytes = source is Uint8List ? source : Uint8List.fromList(source);
      return Image.memory(
        bytes,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.low,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => const SizedBox.expand(),
      );
    }

    return const SizedBox.expand();
  }
}

class _EditorCanvas extends StatelessWidget {
  const _EditorCanvas({
    required this.state,
    required this.controller,
    required this.gpuRendererId,
    required this.gpuPreviewActive,
  });

  final EditorState state;
  final EditorController controller;
  final String? gpuRendererId;
  final bool gpuPreviewActive;

  @override
  Widget build(BuildContext context) {
    final rendererId = gpuRendererId;
    final showGpu = gpuPreviewActive && rendererId != null && !state.showOriginal;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPressStart: state.isBusy
          ? null
          : (_) => controller.setShowOriginal(true),
      onLongPressEnd: state.isBusy
          ? null
          : (_) => controller.setShowOriginal(false),
      onLongPressCancel:
          state.isBusy ? null : () => controller.setShowOriginal(false),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ImagePreview(bytes: state.visiblePreview!),
          if (showGpu)
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  color: Colors.black,
                  child: IosGpuEditorPreview(rendererId: rendererId),
                ),
              ),
            ),
          if (showGpu)
            const Positioned(
              top: 12,
              right: 12,
              child: Chip(
                avatar: Icon(Icons.bolt_rounded, size: 16),
                label: Text('Metal live draft'),
              ),
            ),
          Positioned(
            top: 12,
            left: 12,
            child: AnimatedOpacity(
              opacity: state.showOriginal ? 1 : 0,
              duration: const Duration(milliseconds: 120),
              child: const Chip(label: Text('Original')),
            ),
          ),
        ],
      ),
    );
  }
}
