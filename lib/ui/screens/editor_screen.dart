import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/export_file_service.dart';
import '../../state/editor_controller.dart';
import '../widgets/filter_slider.dart';
import '../widgets/histogram_widget.dart';
import '../widgets/image_preview.dart';

class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({super.key, required this.imageBytes});
  final List<int> imageBytes;

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  static const filters = <String>[...coreFilters, ...creativeFilters];
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
              const Text(
                'PixelCraft replays every active edit against the original image.',
              ),
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
                  label: quality.round().toString(),
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

  Future<void> _showBenchmark() async {
    final state = ref.read(editorProvider);
    final input = state.previewBytes;
    if (input == null) return;
    final rustWatch = Stopwatch()..start();
    final rustResult = ref.read(editorProvider.notifier).benchmarkCurrentFilter();
    rustWatch.stop();

    final dartWatch = Stopwatch()..start();
    var checksum = 0;
    for (var pass = 0; pass < 20; pass++) {
      for (final byte in input) {
        checksum = (checksum + byte) & 0x7fffffff;
      }
    }
    dartWatch.stop();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Benchmark'),
        content: Text(
          'Rust filter: '
          '${(rustResult.elapsedMicros.toDouble() / 1000.0).toStringAsFixed(2)} ms\n'
          'Dart byte-loop baseline: ${dartWatch.elapsedMicroseconds / 1000} ms\n'
          'Bridge wall time: ${rustWatch.elapsedMicroseconds / 1000} ms\n'
          'Checksum: $checksum',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(editorProvider);
    final controller = ref.read(editorProvider.notifier);
    final withinBudget = state.processingMs <= 16;

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
            icon: state.isExporting
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.ios_share),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'benchmark') _showBenchmark();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'benchmark', child: Text('Benchmark')),
            ],
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
            : Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Column(
                  children: [
                    Expanded(
                      child: GestureDetector(
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
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text('Hold the image to compare with the original'),
                    const SizedBox(height: 8),
                    HistogramWidget(bins: state.histogram),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.memory, size: 16),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Rust ${state.processingMs.toStringAsFixed(2)} ms',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            withinBudget
                                ? 'Within frame budget'
                                : 'Preview over 16 ms',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 44,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: filters.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, index) {
                          final filter = filters[index];
                          return ChoiceChip(
                            label: Text(filter.replaceAll('_', ' ')),
                            selected: state.selectedFilter == filter,
                            onSelected: (_) => controller.selectFilter(filter),
                          );
                        },
                      ),
                    ),
                    FilterSlider(
                      value: state.value,
                      min: 0,
                      max: isCreativeFilter(state.selectedFilter) ? 1 : 2,
                      onChangeStart: controller.beginAdjustment,
                      onChanged: controller.previewValue,
                      onChangeEnd: controller.commitAdjustment,
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
