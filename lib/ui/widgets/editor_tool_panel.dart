import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/image_engine.dart';
import '../../state/editor_controller.dart';
import 'filter_slider.dart';
import 'histogram_widget.dart';

typedef EditorGpuPreviewCallback = void Function(
  String kind,
  String key,
  double value,
);

class EditorToolPanel extends StatelessWidget {
  const EditorToolPanel({
    super.key,
    required this.state,
    required this.controller,
    this.onGpuPreviewStart,
    this.onGpuPreviewChanged,
    this.onGpuPreviewCommit,
  });

  final EditorState state;
  final EditorController controller;
  final EditorGpuPreviewCallback? onGpuPreviewStart;
  final EditorGpuPreviewCallback? onGpuPreviewChanged;
  final EditorGpuPreviewCallback? onGpuPreviewCommit;

  @override
  Widget build(BuildContext context) {
    final editingTool = state.selectedTool != EditorTool.details;
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
                ButtonSegment(value: EditorTool.film, icon: Icon(Icons.camera_roll_outlined), label: Text('Film')),
                ButtonSegment(value: EditorTool.crop, icon: Icon(Icons.crop), label: Text('Crop')),
                ButtonSegment(value: EditorTool.rotate, icon: Icon(Icons.rotate_90_degrees_ccw), label: Text('Rotate')),
                ButtonSegment(value: EditorTool.details, icon: Icon(Icons.analytics_outlined), label: Text('Details')),
              ],
              selected: {state.selectedTool},
              onSelectionChanged: (selection) => controller.selectTool(selection.first),
            ),
          ),
          if (state.isPreviewProcessing) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(minHeight: 2),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Updating preview…',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ],
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: switch (state.selectedTool) {
              EditorTool.adjust => _AdjustPanel(
                  state: state,
                  controller: controller,
                  onGpuPreviewStart: onGpuPreviewStart,
                  onGpuPreviewChanged: onGpuPreviewChanged,
                  onGpuPreviewCommit: onGpuPreviewCommit,
                ),
              EditorTool.filters => _FilterPanel(state: state, controller: controller),
              EditorTool.film => _FilmPanel(
                  state: state,
                  controller: controller,
                  onGpuPreviewStart: onGpuPreviewStart,
                  onGpuPreviewChanged: onGpuPreviewChanged,
                  onGpuPreviewCommit: onGpuPreviewCommit,
                ),
              EditorTool.crop => _CropPanel(controller: controller),
              EditorTool.rotate => _RotatePanel(state: state, controller: controller),
              EditorTool.details => _DetailsPanel(state: state),
            },
          ),
          if (editingTool) ...[
            const SizedBox(height: 12),
            _DraftActionBar(state: state, controller: controller),
          ],
        ],
      ),
    );
  }
}

class _DraftActionBar extends StatelessWidget {
  const _DraftActionBar({required this.state, required this.controller});

  final EditorState state;
  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final enabled = state.hasUnappliedEdits &&
        !state.isBusy &&
        !state.isPreviewProcessing;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        OutlinedButton.icon(
          key: const ValueKey('cancel_edits_button'),
          onPressed: enabled ? controller.cancelEdits : null,
          icon: const Icon(Icons.close),
          label: const Text('Cancel'),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          key: const ValueKey('apply_edits_button'),
          onPressed: enabled ? controller.applyEdits : null,
          icon: const Icon(Icons.check),
          label: const Text('Apply'),
        ),
      ],
    );
  }
}

class _AdjustPanel extends StatelessWidget {
  const _AdjustPanel({
    required this.state,
    required this.controller,
    this.onGpuPreviewStart,
    this.onGpuPreviewChanged,
    this.onGpuPreviewCommit,
  });

  final EditorState state;
  final EditorController controller;
  final EditorGpuPreviewCallback? onGpuPreviewStart;
  final EditorGpuPreviewCallback? onGpuPreviewChanged;
  final EditorGpuPreviewCallback? onGpuPreviewCommit;

  bool get _gpuSupported =>
      state.selectedFilter == 'brightness' ||
      state.selectedFilter == 'contrast' ||
      state.selectedFilter == 'saturation' ||
      state.selectedFilter == 'sharpen' ||
      state.selectedFilter == 'gaussian_blur';

  @override
  Widget build(BuildContext context) {
    final filter = state.selectedFilter;
    final useGpuCallbacks = _gpuSupported && onGpuPreviewChanged != null;
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
          onChangeStart: useGpuCallbacks
              ? (value) => onGpuPreviewStart?.call('adjust', filter, value)
              : null,
          onChanged: useGpuCallbacks
              ? (value) => onGpuPreviewChanged?.call('adjust', filter, value)
              : null,
          onChangeEnd: (value) {
            if (useGpuCallbacks && onGpuPreviewCommit != null) {
              onGpuPreviewCommit!.call('adjust', filter, value);
            } else {
              controller.commitFilterValue(value);
            }
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
    final selected = state.selectedCreativeFilter;
    return Column(
      key: const ValueKey('filters'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (state.isGeneratingFilterPreviews && state.filterPreviews.isEmpty)
          const _PreparingLabel(label: 'Preparing filter previews…'),
        SizedBox(
          height: 126,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: creativeFilters.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final filter = creativeFilters[index];
              return _PreviewCard(
                label: filter.replaceAll('_', ' '),
                previewBytes: state.filterPreviews[filter],
                selected: selected == filter,
                enabled: state.filterPreviews[filter] != null && !state.isBusy,
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

class _FilmPanel extends StatelessWidget {
  const _FilmPanel({
    required this.state,
    required this.controller,
    this.onGpuPreviewStart,
    this.onGpuPreviewChanged,
    this.onGpuPreviewCommit,
  });

  final EditorState state;
  final EditorController controller;
  final EditorGpuPreviewCallback? onGpuPreviewStart;
  final EditorGpuPreviewCallback? onGpuPreviewChanged;
  final EditorGpuPreviewCallback? onGpuPreviewCommit;

  @override
  Widget build(BuildContext context) {
    final selected = state.selectedFilmProfile;
    final selectedProfile = state.filmProfiles.cast<EngineFilmProfile?>().firstWhere(
          (profile) => profile?.id == selected,
          orElse: () => null,
        );
    final useGpuCallbacks = selectedProfile != null && onGpuPreviewChanged != null;

    return Column(
      key: const ValueKey('film'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (state.isGeneratingFilmPreviews && state.filmProfilePreviews.isEmpty)
          const _PreparingLabel(label: 'Preparing film previews…'),
        SizedBox(
          height: 132,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: state.filmProfiles.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final profile = state.filmProfiles[index];
              return _PreviewCard(
                label: profile.name,
                previewBytes: state.filmProfilePreviews[profile.id],
                selected: selected == profile.id,
                enabled: state.filmProfilePreviews[profile.id] != null && !state.isBusy,
                onTap: () => controller.selectFilmProfile(profile.id),
              );
            },
          ),
        ),
        if (selectedProfile != null) ...[
          const SizedBox(height: 10),
          Text(selectedProfile.description, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          Text(
            '${selectedProfile.name} strength',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          FilterSlider(
            value: state.filmProfileStrength,
            min: 0,
            max: 1,
            enabled: !state.isBusy,
            onChangeStart: useGpuCallbacks
                ? (value) => onGpuPreviewStart?.call('film', selected, value)
                : null,
            onChanged: useGpuCallbacks
                ? (value) => onGpuPreviewChanged?.call('film', selected, value)
                : null,
            onChangeEnd: (value) {
              if (useGpuCallbacks && onGpuPreviewCommit != null) {
                onGpuPreviewCommit!.call('film', selected, value);
              } else {
                controller.updateFilmProfileStrength(value);
              }
            },
          ),
        ],
      ],
    );
  }
}

class _PreparingLabel extends StatelessWidget {
  const _PreparingLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox.square(
            dimension: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
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
      width: 108,
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
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
