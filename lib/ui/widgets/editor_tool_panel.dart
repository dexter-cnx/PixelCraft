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
          onChangeEnd: (value) {
            controller.commitFilterValue(value);
          },
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
    return Column(
      key: const ValueKey('filters'),
      children: [
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: creativeFilters.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, index) {
              final filter = creativeFilters[index];
              return ChoiceChip(
                label: Text(filter.replaceAll('_', ' ')),
                selected: state.selectedFilter == filter,
                onSelected: (_) => controller.selectFilter(filter),
              );
            },
          ),
        ),
        FilterSlider(
          value: state.value.clamp(0, 1).toDouble(),
          min: 0,
          max: 1,
          enabled: !state.isBusy,
          onChangeEnd: (value) {
            controller.commitFilterValue(value);
          },
        ),
      ],
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
                onChangeEnd: state.isBusy
                    ? null
                    : (value) {
                        controller.commitStraighten(value);
                      },
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
