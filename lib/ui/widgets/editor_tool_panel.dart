import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../state/editor_controller.dart';
import 'filter_slider.dart';
import 'histogram_widget.dart';

class EditorToolPanel extends StatelessWidget {
  const EditorToolPanel({
    super.key,
    required this.state,
    required this.controller,
  });

  final EditorState state;
  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    return AbsorbPointer(
      absorbing: state.isBusy,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<EditorTool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: EditorTool.adjust, icon: Icon(Icons.tune), label: Text('Adjust')),
                ButtonSegment(value: EditorTool.filters, icon: Icon(Icons.auto_awesome), label: Text('Filters')),
                ButtonSegment(value: EditorTool.crop, icon: Icon(Icons.crop), label: Text('Crop')),
                ButtonSegment(value: EditorTool.rotate, icon: Icon(Icons.rotate_90_degrees_ccw), label: Text('Rotate')),
                ButtonSegment(value: EditorTool.details, icon: Icon(Icons.analytics_outlined), label: Text('Details')),
              ],
              selected: {state.selectedTool},
              onSelectionChanged: (selection) => controller.selectTool(selection.first),
            ),
          ),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: switch (state.selectedTool) {
              EditorTool.adjust => _AdjustPanel(state: state, controller: controller),
              EditorTool.filters => _FilterPanel(state: state, controller: controller),
              EditorTool.crop => _CropPanel(controller: controller),
              EditorTool.rotate => _RotatePanel(state: state, controller: controller),
              EditorTool.details => _DetailsPanel(state: state),
            },
          ),
        ],
      ),
    );
  }
}

class _AdjustPanel extends StatelessWidget {
  const _AdjustPanel({required this.state, required this.controller});
  final EditorState state;
  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('adjust'),
      children: [
        Wrap(
          spacing: 8,
          children: coreFilters.map((filter) => ChoiceChip(
            label: Text(filter.replaceAll('_', ' ')),
            selected: state.selectedFilter == filter,
            onSelected: (_) => controller.selectFilter(filter),
          )).toList(),
        ),
        FilterSlider(
          value: state.value,
          min: 0,
          max: 2,
          enabled: !state.isBusy,
          onChangeEnd: controller.commitFilterValue,
        ),
      ],
    );
  }
}

class _FilterPanel extends StatelessWidget {
  const _FilterPanel({required this.state, required this.controller});
  final EditorState state;
  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final selected = state.selectedCreativeFilter;
    return Column(
      key: const ValueKey('filters'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (state.isGeneratingFilterPreviews && state.filterPreviews.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text('Preparing filter previews…'),
              ],
            ),
          ),
        SizedBox(
          height: 126,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: creativeFilters.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final filter = creativeFilters[index];
              final preview = state.filterPreviews[filter];
              final isSelected = selected == filter;
              return _FilterPreviewCard(
                label: filter.replaceAll('_', ' '),
                previewBytes: preview,
                selected: isSelected,
                enabled: preview != null && !state.isBusy,
                onTap: () => controller.applyCreativeFilter(filter),
              );
            },
          ),
        ),
        if (selected.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            '${selected.replaceAll('_', ' ')} intensity',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          FilterSlider(
            value: state.creativeFilterValue,
            min: 0,
            max: 1,
            enabled: !state.isBusy,
            onChangeEnd: controller.updateCreativeFilterValue,
          ),
        ],
      ],
    );
  }
}

class _FilterPreviewCard extends StatelessWidget {
  const _FilterPreviewCard({
    required this.label,
    required this.previewBytes,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final Uint8List? previewBytes;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 104,
      child: Material(
        color: selected
            ? colorScheme.secondaryContainer
            : colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected ? colorScheme.primary : colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: previewBytes == null
                    ? ColoredBox(
                        color: colorScheme.surfaceContainerHighest,
                        child: const Center(
                          child: Icon(Icons.image_outlined, size: 24),
                        ),
                      )
                    : Image.memory(
                        previewBytes!,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CropPanel extends StatelessWidget {
  const _CropPanel({required this.controller});
  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      key: const ValueKey('crop'),
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        ActionChip(label: const Text('1:1'), onPressed: () => controller.applyCenteredCrop(1)),
        ActionChip(label: const Text('4:3'), onPressed: () => controller.applyCenteredCrop(4 / 3)),
        ActionChip(label: const Text('3:4'), onPressed: () => controller.applyCenteredCrop(3 / 4)),
        ActionChip(label: const Text('16:9'), onPressed: () => controller.applyCenteredCrop(16 / 9)),
        ActionChip(label: const Text('9:16'), onPressed: () => controller.applyCenteredCrop(9 / 16)),
      ],
    );
  }
}

class _RotatePanel extends StatelessWidget {
  const _RotatePanel({required this.state, required this.controller});
  final EditorState state;
  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('rotate'),
      children: [
        Wrap(
          spacing: 8,
          alignment: WrapAlignment.center,
          children: [
            IconButton.filledTonal(onPressed: controller.rotateLeft, tooltip: 'Rotate left', icon: const Icon(Icons.rotate_left)),
            IconButton.filledTonal(onPressed: controller.rotateRight, tooltip: 'Rotate right', icon: const Icon(Icons.rotate_right)),
            IconButton.filledTonal(onPressed: controller.flipHorizontal, tooltip: 'Flip horizontal', icon: const Icon(Icons.flip)),
            IconButton.filledTonal(onPressed: controller.flipVertical, tooltip: 'Flip vertical', icon: const RotatedBox(quarterTurns: 1, child: Icon(Icons.flip))),
          ],
        ),
        Row(
          children: [
            const Text('-15°'),
            Expanded(
              child: Slider(
                value: state.straightenDegrees,
                min: -15,
                max: 15,
                divisions: 60,
                label: '${state.straightenDegrees.toStringAsFixed(1)}°',
                onChanged: state.isBusy ? null : controller.setStraightenPreview,
                onChangeEnd: state.isBusy ? null : controller.commitStraighten,
              ),
            ),
            const Text('15°'),
          ],
        ),
      ],
    );
  }
}

class _DetailsPanel extends StatelessWidget {
  const _DetailsPanel({required this.state});
  final EditorState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('details'),
      children: [
        HistogramWidget(bins: state.histogram),
        const SizedBox(height: 8),
        Text('Rust ${state.processingMs.toStringAsFixed(2)} ms · ${state.cursor}/${state.operationCount} edits'),
      ],
    );
  }
}
