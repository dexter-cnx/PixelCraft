import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref
          .read(editorProvider.notifier)
          .load(Uint8List.fromList(widget.imageBytes)),
    );
  }

  Future<void> _showBenchmark() async {
    final state = ref.read(editorProvider);
    final input = state.previewBytes;
    if (input == null) return;
    final rustWatch = Stopwatch()..start();
    final rustResult = ref.read(editorProvider.notifier).benchmarkCurrentFilter();
    rustWatch.stop();

    // Deliberately simple Dart baseline: repeatedly scan bytes. It demonstrates
    // bridge/engine advantage without adding a Dart image-processing dependency.
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
        title: const Text('Editor'),
        actions: [
          IconButton(
            onPressed: controller.undo,
            tooltip: 'Undo',
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            onPressed: controller.redo,
            tooltip: 'Redo',
            icon: const Icon(Icons.redo),
          ),
          IconButton(
            onPressed: _showBenchmark,
            tooltip: 'Benchmark',
            icon: const Icon(Icons.speed),
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
                    Expanded(child: ImagePreview(bytes: state.previewBytes!)),
                    const SizedBox(height: 12),
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
