import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/export_file_service.dart';
import '../../state/editor_controller.dart';
import '../widgets/editor_tool_panel.dart';
import '../widgets/image_preview.dart';

class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({super.key, required this.imageBytes});
  final List<int> imageBytes;

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  static const _fileService = ExportFileService();
  bool _isSavingExport = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref
          .read(editorProvider.notifier)
          .load(Uint8List.fromList(widget.imageBytes)),
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
              const Text('PixelCraft replays active edits against the original image.'),
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
          title: Text(
            file.savedToGallery
                ? 'Saved to Gallery'
                : 'Export complete',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (file.savedToGallery) ...[
                const Text(
                  'The exported image was added to your device photo gallery.',
                ),
                const SizedBox(height: 8),
                const Text('Android album: Pictures/PixelCraft'),
              ] else ...[
                const Text(
                  'The image was exported, but PixelCraft could not add it to the device gallery.',
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(editorProvider);
    final controller = ref.read(editorProvider.notifier);
    final isProcessing = state.isBusy || _isSavingExport;

    return Scaffold(
      appBar: AppBar(
        title: Text('Editor · ${state.cursor}/${state.operationCount} edits'),
        actions: [
          IconButton(
            onPressed: state.canUndo && !isProcessing ? controller.undo : null,
            tooltip: 'Undo',
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            onPressed: state.canRedo && !isProcessing ? controller.redo : null,
            tooltip: 'Redo',
            icon: const Icon(Icons.redo),
          ),
          IconButton(
            onPressed: state.previewBytes == null || state.isExporting || isProcessing
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
        child: state.previewBytes == null
            ? Center(
                child: state.error == null
                    ? const CircularProgressIndicator()
                    : Text(state.error!),
              )
            : LayoutBuilder(
                builder: (context, constraints) {
                  final canvas = _EditorCanvas(state: state, controller: controller);
                  final tools = EditorToolPanel(state: state, controller: controller);
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

class _EditorCanvas extends StatelessWidget {
  const _EditorCanvas({required this.state, required this.controller});

  final EditorState state;
  final EditorController controller;

  @override
  Widget build(BuildContext context) {
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
