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

    try {
      final bytes = ref.read(editorProvider.notifier).exportImage(
            format: selection.format,
            quality: selection.quality,
          );
      final file = await _fileService.save(bytes, format: selection.format);
      if (!mounted) return;
      final share = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Export complete'),
          content: SelectableText(file.path),
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
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(editorProvider);
    final controller = ref.read(editorProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text('Editor · ${state.cursor}/${state.operationCount} edits'),
        actions: [
          IconButton(
            onPressed: state.canUndo ? controller.undo : null,
            tooltip: 'Undo',
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            onPressed: state.canRedo ? controller.redo : null,
            tooltip: 'Redo',
            icon: const Icon(Icons.redo),
          ),
          IconButton(
            onPressed: state.previewBytes == null || state.isExporting
                ? null
                : _showExportDialog,
            tooltip: 'Export',
            icon: const Icon(Icons.ios_share),
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
                  if (constraints.maxWidth >= 900) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(flex: 3, child: canvas),
                          const SizedBox(width: 20),
                          SizedBox(width: 360, child: SingleChildScrollView(child: tools)),
                        ],
                      ),
                    );
                  }
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: Column(
                      children: [
                        Expanded(child: canvas),
                        const SizedBox(height: 12),
                        SingleChildScrollView(child: tools),
                      ],
                    ),
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
      onLongPressStart: (_) => controller.setShowOriginal(true),
      onLongPressEnd: (_) => controller.setShowOriginal(false),
      onLongPressCancel: () => controller.setShowOriginal(false),
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
