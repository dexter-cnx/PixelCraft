import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/export_file_service.dart';
import '../../gpu/gpu_editor_draft_session.dart';
import '../../gpu/gpu_editor_preview_bridge.dart';
import '../../gpu/gpu_editor_render_plan.dart';
import '../../gpu/ios_gpu_editor_preview.dart';
import '../../state/editor_controller.dart';
import '../../state/editor_recipe_summary.dart';
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

class _EditorScreenState extends ConsumerState<EditorScreen>
    with WidgetsBindingObserver {
  static const _fileService = ExportFileService();
  static const _gpuEditorIntegration = bool.fromEnvironment(
    'GPU_EDITOR_INTEGRATION',
    defaultValue: true,
  );
  static const _gpuBridge = GpuEditorPreviewBridge();

  bool _isSavingExport = false;
  bool _isPreparingSource = true;
  bool _exitApproved = false;
  String? _sourceError;
  EditorRecipeSummary _recipeSummary = const EditorRecipeSummary();
  int _recipeRefreshGeneration = 0;

  final _gpuSession = GpuEditorDraftSession();
  String? _gpuRendererId;
  File? _gpuSourceFile;
  Future<String>? _gpuRendererFuture;

  bool get _gpuPreviewActive => _gpuSession.isActive;

  bool get _gpuIntegrationEligible =>
      _gpuEditorIntegration &&
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(_initializeEditor);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_gpuIntegrationEligible) return;
    switch (state) {
      case AppLifecycleState.resumed:
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _invalidateGpuPreview(
          dropRenderer: true,
          reason: 'app lifecycle ${state.name}',
        );
    }
  }

  @override
  void didHaveMemoryPressure() {
    if (!_gpuIntegrationEligible) return;
    _invalidateGpuPreview(
      dropRenderer: true,
      reason: 'memory pressure',
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _recipeRefreshGeneration++;
    _gpuSession.invalidate(dropRenderer: true, reason: 'editor disposed');
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
      await _refreshRecipeSummary();

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

  Future<void> _refreshRecipeSummary() async {
    final generation = ++_recipeRefreshGeneration;
    try {
      final recipe =
          await ref.read(imageEngineProvider).exportSessionRecipeInBackground();
      final summary = EditorRecipeSummary.fromRecipeJson(recipe);
      if (!mounted || generation != _recipeRefreshGeneration) return;
      setState(() => _recipeSummary = summary);
    } catch (error) {
      debugPrint('[G4 editor] recipe summary unavailable: $error');
    }
  }

  Future<void> _rewriteDraftRecipe(
    String Function(String recipeJson) rewrite, {
    String? keepSelectedAdjustment,
  }) async {
    final state = ref.read(editorProvider);
    final original = state.originalBytes;
    if (original == null || state.isBusy || state.isPreviewProcessing) return;

    _invalidateGpuPreview(reason: 'G4 draft reset');
    try {
      final recipe =
          await ref.read(imageEngineProvider).exportSessionRecipeInBackground();
      final rewritten = rewrite(recipe);
      await ref.read(editorProvider.notifier).restore(original, rewritten);
      if (keepSelectedAdjustment != null) {
        ref
            .read(editorProvider.notifier)
            .selectFilter(keepSelectedAdjustment);
      }
      await ref.read(editorSessionStoreProvider).save(
            originalBytes: original,
            recipeJson: rewritten,
          );
      await _refreshRecipeSummary();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Reset failed: $error')),
      );
    }
  }

  Future<void> _resetAdjustment(String filter) => _rewriteDraftRecipe(
        (recipe) => EditorRecipeSummary.resetDraftAdjustment(recipe, filter),
        keepSelectedAdjustment: filter,
      );

  Future<void> _resetAdjustments() => _rewriteDraftRecipe(
        EditorRecipeSummary.resetDraftAdjustments,
        keepSelectedAdjustment: ref.read(editorProvider).selectedFilter,
      );

  Future<void> _resetCreative() =>
      _rewriteDraftRecipe(EditorRecipeSummary.resetDraftCreative);

  Future<void> _resetFilm() =>
      _rewriteDraftRecipe(EditorRecipeSummary.resetDraftFilm);

  bool _canUseGpuDraft(EditorState state, String kind, String key) {
    if (!_gpuIntegrationEligible || state.isBusy || state.isPreviewProcessing) {
      return false;
    }
    if (state.originalPreviewBytes == null || state.showOriginal) return false;

    if (kind == 'adjust') return gpuCoreAdjustmentKeys.contains(key);
    if (kind == 'creative') {
      return gpuCreativeFilterKeys.contains(key) &&
          state.selectedCreativeFilter == key;
    }
    if (kind == 'film') {
      return key.isNotEmpty && state.selectedFilmProfile == key;
    }
    return false;
  }

  GpuEditorTransientEdit? _transientEdit(
    String kind,
    String key,
    double value,
  ) {
    final draftKind = switch (kind) {
      'adjust' => GpuEditorDraftKind.adjust,
      'creative' => GpuEditorDraftKind.creative,
      'film' => GpuEditorDraftKind.film,
      _ => null,
    };
    if (draftKind == null) return null;
    return GpuEditorTransientEdit(
      kind: draftKind,
      key: key,
      value: value,
    );
  }

  void _onGpuPreviewStart(String kind, String key, double value) {
    final state = ref.read(editorProvider);
    if (!_canUseGpuDraft(state, kind, key)) return;
    final transient = _transientEdit(kind, key, value);
    if (transient == null) return;

    final generation = _gpuSession.begin(transient);
    unawaited(_prepareGpuPreview(state, generation));
  }

  Future<void> _prepareGpuPreview(EditorState state, int generation) async {
    try {
      final recipe =
          await ref.read(imageEngineProvider).exportSessionRecipeInBackground();
      if (!mounted || !_gpuSession.isCurrent(generation)) return;

      final transient = _gpuSession.transient;
      if (transient == null) return;
      final plan = GpuEditorRenderPlan.fromRecipeJson(
        recipe,
        transient: transient,
      );
      if (!_gpuSession.prepare(
        generation,
        recipeJson: recipe,
        plan: plan,
      )) {
        debugPrint(
          '[G3 editor GPU] faithful fallback: '
          '${plan.fallbackReason ?? 'unrepresentable draft'}',
        );
        return;
      }

      await _activateGpuPreview(state, generation);
    } catch (error) {
      debugPrint('[G3 editor GPU] render plan unavailable: $error');
      if (mounted && _gpuSession.isCurrent(generation)) {
        _gpuSession.fallback(generation, 'render plan unavailable: $error');
      }
    }
  }

  void _onGpuPreviewChanged(String kind, String key, double value) {
    final current = _gpuSession.transient;
    final next = _transientEdit(kind, key, value);
    if (current == null || next == null) return;
    if (current.kind != next.kind || current.key != next.key) return;

    _gpuSession.updateTransient(next);
    final rendererId = _gpuRendererId;
    if (rendererId != null && _gpuSession.isActive) {
      final generation = _gpuSession.activationGeneration;
      unawaited(_applyGpuDraftSafely(rendererId, generation));
    }
  }

  void _onGpuPreviewCommit(String kind, String key, double value) {
    unawaited(_commitGpuPreview(kind, key, value));
  }

  void _invalidateGpuPreview({
    bool dropRenderer = false,
    bool checkpointChanged = false,
    String? reason,
  }) {
    final wasActive = _gpuSession.isActive;
    _gpuSession.invalidate(
      checkpointChanged: checkpointChanged,
      dropRenderer: dropRenderer,
      reason: reason,
    );

    if (dropRenderer) {
      final rendererId = _gpuRendererId;
      _gpuRendererId = null;
      _gpuRendererFuture = null;
      if (rendererId != null) {
        unawaited(
          _gpuBridge.destroyRenderer(rendererId).catchError((Object error) {
            debugPrint('[G3 editor GPU] renderer cleanup failed: $error');
          }),
        );
      }
    }

    if (reason != null) {
      debugPrint('[G3 editor GPU] invalidated: $reason');
    }
    if (mounted && wasActive) setState(() {});
  }

  Future<String> _ensureGpuRenderer() {
    final id = _gpuRendererId;
    if (id != null) return Future.value(id);
    final pending = _gpuRendererFuture;
    if (pending != null) return pending;

    final generation = _gpuSession.rendererGeneration;
    final future = _gpuBridge.createRenderer().then((id) async {
      if (!mounted || generation != _gpuSession.rendererGeneration) {
        await _gpuBridge.destroyRenderer(id).catchError((Object error) {
          debugPrint('[G3 editor GPU] stale renderer cleanup failed: $error');
        });
        throw StateError('GPU renderer creation was superseded');
      }
      _gpuRendererId = id;
      _gpuRendererFuture = null;
      return id;
    }, onError: (Object error, StackTrace stack) {
      if (generation == _gpuSession.rendererGeneration) {
        _gpuRendererFuture = null;
      }
      Error.throwWithStackTrace(error, stack);
    });
    _gpuRendererFuture = future;
    return future;
  }

  Future<void> _activateGpuPreview(EditorState state, int generation) async {
    try {
      final checkpoint = state.originalPreviewBytes;
      if (checkpoint == null) return;

      final rendererId = await _ensureGpuRenderer();
      if (!mounted || !_gpuSession.isCurrent(generation)) return;

      final file = File(
        '${Directory.systemTemp.path}/pixelcraft-editor-gpu-${identityHashCode(this)}.png',
      );
      await file.writeAsBytes(checkpoint, flush: true);
      _gpuSourceFile = file;

      await _gpuBridge.setSourcePath(rendererId, file.path);
      if (!mounted || !_gpuSession.isCurrent(generation)) return;
      await _applyGpuDraft(rendererId);
      if (!mounted || !_gpuSession.isCurrent(generation)) return;
      if (!_gpuSession.activate(generation)) return;

      setState(() {});
    } catch (error) {
      debugPrint('[G3 editor GPU] live preview unavailable: $error');
      if (mounted && _gpuSession.isCurrent(generation)) {
        _invalidateGpuPreview(
          dropRenderer: true,
          reason: 'activation failure',
        );
      }
    }
  }

  Future<void> _applyGpuDraftSafely(String rendererId, int generation) async {
    try {
      await _applyGpuDraft(rendererId);
    } catch (error) {
      debugPrint('[G3 editor GPU] live update failed: $error');
      if (mounted && _gpuSession.isCurrent(generation)) {
        _invalidateGpuPreview(
          dropRenderer: true,
          reason: 'live update failure',
        );
      }
    }
  }

  Future<void> _applyGpuDraft(String rendererId) async {
    final recipe = _gpuSession.recipeJson;
    final transient = _gpuSession.transient;
    if (recipe == null || transient == null) {
      throw StateError('No authoritative GPU draft recipe is available');
    }

    final plan = GpuEditorRenderPlan.fromRecipeJson(
      recipe,
      transient: transient,
    );
    if (!plan.isRepresentable) {
      throw StateError(
        'GPU draft is not faithfully representable: ${plan.fallbackReason}',
      );
    }
    await _applyGpuRenderPlan(rendererId, plan);
  }

  Future<void> _applyGpuRenderPlan(
    String rendererId,
    GpuEditorRenderPlan plan,
  ) async {
    await _gpuBridge.setAdjustments(rendererId, plan.adjustments);

    if (plan.creativeUsesFilmSlot) {
      await _gpuBridge.setCreative(
        rendererId,
        filterId: '',
        intensity: 0,
      );
      await _gpuBridge.setFilm(
        rendererId,
        profileId: 'creative_${plan.creativeFilterId}',
        strength: plan.creativeIntensity,
      );
      return;
    }

    await _gpuBridge.setCreative(
      rendererId,
      filterId: plan.creativeFilterId,
      intensity: plan.creativeIntensity,
    );
    await _gpuBridge.setFilm(
      rendererId,
      profileId: plan.filmProfileId,
      strength: plan.filmStrength,
    );
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
    final generation = _gpuSession.activationGeneration;
    final transient = _gpuSession.transient;
    final expectedKind = _transientEdit(kind, key, value)?.kind;
    final wasGpuActive = _gpuSession.isActive &&
        transient != null &&
        transient.kind == expectedKind &&
        transient.key == key;

    try {
      if (kind == 'adjust') {
        await controller.commitFilterValue(value);
      } else if (kind == 'creative') {
        await controller.updateCreativeFilterValue(value);
      } else if (kind == 'film') {
        await controller.updateFilmProfileStrength(value);
      }
      await _waitForRustPreviewSettled();
      await _refreshRecipeSummary();
    } finally {
      if (_gpuSession.isCurrent(generation)) {
        _gpuSession.finish(generation);
        if (mounted && wasGpuActive) setState(() {});
      }
    }
  }

  Future<void> _showHistory() async {
    await _refreshRecipeSummary();
    if (!mounted) return;
    final state = ref.read(editorProvider);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        final entries = _recipeSummary.history;
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.65,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Edit History',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            Text(
                              '${_recipeSummary.checkpointCursor} applied · '
                              '${_recipeSummary.cursor - _recipeSummary.checkpointCursor} draft',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Undo',
                        onPressed: state.canUndo
                            ? () async {
                                Navigator.pop(context);
                                await ref.read(editorProvider.notifier).undo();
                                await _refreshRecipeSummary();
                              }
                            : null,
                        icon: const Icon(Icons.undo),
                      ),
                      IconButton(
                        tooltip: 'Redo',
                        onPressed: state.canRedo
                            ? () async {
                                Navigator.pop(context);
                                await ref.read(editorProvider.notifier).redo();
                                await _refreshRecipeSummary();
                              }
                            : null,
                        icon: const Icon(Icons.redo),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: entries.isEmpty
                      ? const Center(child: Text('No edits yet'))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: entries.length,
                          itemBuilder: (context, index) {
                            final entry = entries[index];
                            final startsDraft = index ==
                                    _recipeSummary.checkpointCursor &&
                                _recipeSummary.checkpointCursor > 0;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (startsDraft)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      20,
                                      10,
                                      20,
                                      6,
                                    ),
                                    child: Text(
                                      'CURRENT DRAFT',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                          ),
                                    ),
                                  ),
                                ListTile(
                                  dense: true,
                                  leading: Icon(
                                    entry.isApplied
                                        ? Icons.check_circle_outline
                                        : Icons.edit_outlined,
                                  ),
                                  title: Text(entry.label),
                                  subtitle: Text(
                                    entry.isApplied
                                        ? 'Applied checkpoint'
                                        : 'Unapplied draft',
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
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
              const Text(
                'Rust replays the complete active recipe against the untouched original source.',
              ),
              const SizedBox(height: 8),
              Text(
                ref.read(editorProvider).hasUnappliedEdits
                    ? 'Current draft edits are included in the export.'
                    : 'Export uses the latest applied checkpoint.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                initialValue: format,
                decoration: const InputDecoration(
                  labelText: 'Format',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'png', child: Text('PNG · lossless')),
                  DropdownMenuItem(value: 'jpeg', child: Text('JPEG · smaller')),
                  DropdownMenuItem(value: 'webp', child: Text('WEBP')),
                ],
                onChanged: (value) {
                  if (value != null) setDialogState(() => format = value);
                },
              ),
              if (format != 'png') ...[
                const SizedBox(height: 16),
                Text('Quality ${quality.round()}%'),
                Slider(
                  value: quality,
                  min: 40,
                  max: 100,
                  divisions: 12,
                  onChanged: (value) => setDialogState(() => quality = value),
                ),
              ],
              const SizedBox(height: 8),
              const Row(
                children: [
                  Icon(Icons.photo_size_select_large_outlined, size: 18),
                  SizedBox(width: 8),
                  Expanded(child: Text('Resolution: original source dimensions')),
                ],
              ),
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
          title: Text(
            file.savedToGallery ? 'Saved to Gallery' : 'Export complete',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (file.savedToGallery)
                const Text('The full-resolution export was saved to your device.')
              else ...[
                const Text(
                  'The export completed, but Pixel Craft could not add it to the device gallery.',
                ),
                if (file.galleryError != null) ...[
                  const SizedBox(height: 8),
                  Text(file.galleryError!),
                ],
              ],
              const SizedBox(height: 12),
              Text(
                'App backup: ${file.path}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
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

  Future<void> _confirmExit() async {
    final state = ref.read(editorProvider);
    if (state.isBusy || state.isPreviewProcessing || _isSavingExport) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Finish the current operation before leaving.')),
      );
      return;
    }
    if (!state.hasUnappliedEdits) {
      setState(() => _exitApproved = true);
      if (mounted) Navigator.of(context).pop();
      return;
    }

    final choice = await showDialog<_ExitChoice>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unapplied edits'),
        content: const Text(
          'Apply the current draft before leaving, or discard it and return to the last checkpoint.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _ExitChoice.continueEditing),
            child: const Text('Continue Editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _ExitChoice.discard),
            child: const Text('Discard'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _ExitChoice.apply),
            child: const Text('Apply & Exit'),
          ),
        ],
      ),
    );

    if (!mounted || choice == null || choice == _ExitChoice.continueEditing) {
      return;
    }
    final controller = ref.read(editorProvider.notifier);
    if (choice == _ExitChoice.apply) {
      await controller.applyEdits();
    } else {
      await controller.cancelEdits();
    }
    if (!mounted || ref.read(editorProvider).error != null) return;
    setState(() => _exitApproved = true);
    Navigator.of(context).pop();
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
      final recipeMayHaveChanged = previous.cursor != next.cursor ||
          previous.operationCount != next.operationCount ||
          checkpointChanged;

      if (recipeMayHaveChanged && !next.isPreviewProcessing && !next.isBusy) {
        unawaited(_refreshRecipeSummary());
      }

      if (!toolChanged &&
          !checkpointChanged &&
          !enteredOriginal &&
          !becameBusy &&
          !failed) {
        return;
      }

      _invalidateGpuPreview(
        checkpointChanged: checkpointChanged,
        reason: checkpointChanged
            ? 'Rust checkpoint changed'
            : toolChanged
                ? 'editor tool changed'
                : enteredOriginal
                    ? 'before preview requested'
                    : becameBusy
                        ? 'editor entered busy state'
                        : 'editor reported an error',
      );
    });

    final scaffold = Scaffold(
      appBar: AppBar(
        title: Text(
          state.hasUnappliedEdits
              ? 'Editor · Draft ${state.cursor} edits'
              : 'Editor · Applied',
        ),
        actions: [
          if (_gpuIntegrationEligible && kDebugMode)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Chip(
                avatar: const Icon(Icons.memory_rounded, size: 16),
                label: Text(_gpuPreviewActive ? 'GPU LIVE' : 'GPU READY'),
              ),
            ),
          IconButton(
            onPressed: actionsBlocked ? null : _showHistory,
            tooltip: 'History',
            icon: const Icon(Icons.history_rounded),
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
                            recipeSummary: _recipeSummary,
                            onGpuPreviewStart:
                                _gpuIntegrationEligible ? _onGpuPreviewStart : null,
                            onGpuPreviewChanged:
                                _gpuIntegrationEligible ? _onGpuPreviewChanged : null,
                            onGpuPreviewCommit:
                                _gpuIntegrationEligible ? _onGpuPreviewCommit : null,
                            onResetAdjustment: _resetAdjustment,
                            onResetAdjustments: _resetAdjustments,
                            onResetCreative: _resetCreative,
                            onResetFilm: _resetFilm,
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
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Text(
                                                  _isSavingExport
                                                      ? 'Exporting full resolution…'
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

    return PopScope(
      canPop: _exitApproved || !state.hasUnappliedEdits,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_confirmExit());
      },
      child: scaffold,
    );
  }
}

enum _ExitChoice { continueEditing, discard, apply }

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
                      child: Text(
                        'Preparing photo and editing tools…',
                        style: TextStyle(color: Colors.white),
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
      final cacheWidth =
          (logicalWidth * devicePixelRatio).round().clamp(720, 1440);
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
      onLongPressStart:
          state.isBusy ? null : (_) => controller.setShowOriginal(true),
      onLongPressEnd:
          state.isBusy ? null : (_) => controller.setShowOriginal(false),
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
          if (showGpu && kDebugMode)
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
              child: const Chip(
                avatar: Icon(Icons.compare_rounded, size: 16),
                label: Text('Before'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
