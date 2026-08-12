import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/image_engine.dart';
import '../../state/editor_controller.dart';
import '../../state/editor_recipe_summary.dart';
import 'filter_slider.dart';
import 'histogram_widget.dart';

typedef EditorGpuPreviewCallback = void Function(
  String kind,
  String key,
  double value,
);

typedef EditorResetAdjustmentCallback = Future<void> Function(String filter);
typedef EditorResetCallback = Future<void> Function();

class EditorToolPanel extends StatelessWidget {
  const EditorToolPanel({
    super.key,
    required this.state,
    required this.controller,
    required this.recipeSummary,
    this.onGpuPreviewStart,
    this.onGpuPreviewChanged,
    this.onGpuPreviewCommit,
    this.onResetAdjustment,
    this.onResetAdjustments,
    this.onResetCreative,
    this.onResetFilm,
  });

  final EditorState state;
  final EditorController controller;
  final EditorRecipeSummary recipeSummary;
  final EditorGpuPreviewCallback? onGpuPreviewStart;
  final EditorGpuPreviewCallback? onGpuPreviewChanged;
  final EditorGpuPreviewCallback? onGpuPreviewCommit;
  final EditorResetAdjustmentCallback? onResetAdjustment;
  final EditorResetCallback? onResetAdjustments;
  final EditorResetCallback? onResetCreative;
  final EditorResetCallback? onResetFilm;

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
              segments: [
                ButtonSegment(
                  value: EditorTool.adjust,
                  icon: _ToolIcon(
                    icon: Icons.tune,
                    changed: recipeSummary.hasAdjustChanges,
                  ),
                  label: const Text('Adjust'),
                ),
                ButtonSegment(
                  value: EditorTool.filters,
                  icon: _ToolIcon(
                    icon: Icons.auto_awesome,
                    changed: recipeSummary.hasCreativeChange,
                  ),
                  label: const Text('Filters'),
                ),
                ButtonSegment(
                  value: EditorTool.film,
                  icon: _ToolIcon(
                    icon: Icons.camera_roll_outlined,
                    changed: recipeSummary.hasFilmChange,
                  ),
                  label: const Text('Film'),
                ),
                const ButtonSegment(
                  value: EditorTool.crop,
                  icon: Icon(Icons.crop),
                  label: Text('Crop'),
                ),
                const ButtonSegment(
                  value: EditorTool.rotate,
                  icon: Icon(Icons.rotate_90_degrees_ccw),
                  label: Text('Rotate'),
                ),
                const ButtonSegment(
                  value: EditorTool.details,
                  icon: Icon(Icons.analytics_outlined),
                  label: Text('Details'),
                ),
              ],
              selected: {state.selectedTool},
              onSelectionChanged: (selection) =>
                  controller.selectTool(selection.first),
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
                  recipeSummary: recipeSummary,
                  onGpuPreviewStart: onGpuPreviewStart,
                  onGpuPreviewChanged: onGpuPreviewChanged,
                  onGpuPreviewCommit: onGpuPreviewCommit,
                  onResetAdjustment: onResetAdjustment,
                  onResetAdjustments: onResetAdjustments,
                ),
              EditorTool.filters => _FilterPanel(
                  state: state,
                  controller: controller,
                  recipeSummary: recipeSummary,
                  onGpuPreviewStart: onGpuPreviewStart,
                  onGpuPreviewChanged: onGpuPreviewChanged,
                  onGpuPreviewCommit: onGpuPreviewCommit,
                  onResetCreative: onResetCreative,
                ),
              EditorTool.film => _FilmPanel(
                  state: state,
                  controller: controller,
                  recipeSummary: recipeSummary,
                  onGpuPreviewStart: onGpuPreviewStart,
                  onGpuPreviewChanged: onGpuPreviewChanged,
                  onGpuPreviewCommit: onGpuPreviewCommit,
                  onResetFilm: onResetFilm,
                ),
              EditorTool.crop => const _CropPanel(),
              EditorTool.rotate =>
                _RotatePanel(state: state, controller: controller),
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

class _ToolIcon extends StatelessWidget {
  const _ToolIcon({required this.icon, required this.changed});

  final IconData icon;
  final bool changed;

  @override
  Widget build(BuildContext context) {
    return Badge(
      isLabelVisible: changed,
      smallSize: 7,
      child: Icon(icon),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              Icons.compare_rounded,
              size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Press and hold the photo to compare with the last Apply checkpoint.',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('cancel_edits_button'),
              onPressed: enabled ? controller.cancelEdits : null,
              icon: const Icon(Icons.restart_alt_rounded),
              label: const Text('Discard Draft'),
            ),
            FilledButton.icon(
              key: const ValueKey('apply_edits_button'),
              onPressed: enabled ? controller.applyEdits : null,
              icon: const Icon(Icons.check),
              label: const Text('Apply'),
            ),
          ],
        ),
      ],
    );
  }
}

class _AdjustPanel extends StatelessWidget {
  const _AdjustPanel({
    required this.state,
    required this.controller,
    required this.recipeSummary,
    this.onGpuPreviewStart,
    this.onGpuPreviewChanged,
    this.onGpuPreviewCommit,
    this.onResetAdjustment,
    this.onResetAdjustments,
  });

  final EditorState state;
  final EditorController controller;
  final EditorRecipeSummary recipeSummary;
  final EditorGpuPreviewCallback? onGpuPreviewStart;
  final EditorGpuPreviewCallback? onGpuPreviewChanged;
  final EditorGpuPreviewCallback? onGpuPreviewCommit;
  final EditorResetAdjustmentCallback? onResetAdjustment;
  final EditorResetCallback? onResetAdjustments;

  @override
  Widget build(BuildContext context) {
    final filter = state.selectedFilter;
    final spec = adjustmentSpec(filter);
    final useGpuCallbacks = spec.gpuPreview && onGpuPreviewChanged != null;
    final neutral = spec.neutral;
    final currentChanged = recipeSummary.isAdjustmentChanged(filter);
    final resetBlocked = state.isBusy || state.isPreviewProcessing;

    return Column(
      key: const ValueKey('adjust'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 42,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: coreFilters.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final item = coreFilters[index];
              final itemSpec = adjustmentSpec(item);
              return ChoiceChip(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(itemSpec.label),
                    if (recipeSummary.isAdjustmentChanged(item)) ...[
                      const SizedBox(width: 6),
                      Container(
                        key: ValueKey('adjust_changed_$item'),
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                ),
                selected: filter == item,
                onSelected: (_) => controller.selectFilter(item),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                '${spec.label} · ${spec.group} · neutral ${neutral.toStringAsFixed(1)}${spec.unit.isEmpty ? '' : ' ${spec.unit}'}',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
            TextButton.icon(
              key: const ValueKey('reset_adjustment_button'),
              onPressed: currentChanged && !resetBlocked && onResetAdjustment != null
                  ? () => onResetAdjustment!(filter)
                  : null,
              icon: const Icon(Icons.restart_alt_rounded, size: 18),
              label: const Text('Reset'),
            ),
          ],
        ),
        FilterSlider(
          value: state.value,
          min: spec.min,
          max: spec.max,
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
        if (!spec.gpuPreview)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Rust authoritative preview updates on release until a verified GPU path is available.',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        if (recipeSummary.hasAdjustChanges) ...[
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const ValueKey('reset_adjust_section_button'),
              onPressed: !resetBlocked && onResetAdjustments != null
                  ? onResetAdjustments
                  : null,
              child: const Text('Reset Adjust'),
            ),
          ),
        ],
      ],
    );
  }
}

class _FilterPanel extends StatelessWidget {
  const _FilterPanel({
    required this.state,
    required this.controller,
    required this.recipeSummary,
    this.onGpuPreviewStart,
    this.onGpuPreviewChanged,
    this.onGpuPreviewCommit,
    this.onResetCreative,
  });

  final EditorState state;
  final EditorController controller;
  final EditorRecipeSummary recipeSummary;
  final EditorGpuPreviewCallback? onGpuPreviewStart;
  final EditorGpuPreviewCallback? onGpuPreviewChanged;
  final EditorGpuPreviewCallback? onGpuPreviewCommit;
  final EditorResetCallback? onResetCreative;

  @override
  Widget build(BuildContext context) {
    final selected = state.selectedCreativeFilter;
    final gpuSupported = creativeFilters.contains(selected);
    final useGpuCallbacks = gpuSupported && onGpuPreviewChanged != null;
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
          Row(
            children: [
              Expanded(
                child: Text(
                  '${selected.replaceAll('_', ' ')} intensity',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              TextButton.icon(
                onPressed: recipeSummary.hasCreativeChange &&
                        !state.isPreviewProcessing &&
                        onResetCreative != null
                    ? onResetCreative
                    : null,
                icon: const Icon(Icons.restart_alt_rounded, size: 18),
                label: const Text('Reset Filter'),
              ),
            ],
          ),
          FilterSlider(
            value: state.creativeFilterValue,
            min: 0,
            max: 1,
            enabled: !state.isBusy,
            onChangeStart: useGpuCallbacks
                ? (value) => onGpuPreviewStart?.call('creative', selected, value)
                : null,
            onChanged: useGpuCallbacks
                ? (value) => onGpuPreviewChanged?.call('creative', selected, value)
                : null,
            onChangeEnd: (value) {
              if (useGpuCallbacks && onGpuPreviewCommit != null) {
                onGpuPreviewCommit!.call('creative', selected, value);
              } else {
                controller.updateCreativeFilterValue(value);
              }
            },
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
    required this.recipeSummary,
    this.onGpuPreviewStart,
    this.onGpuPreviewChanged,
    this.onGpuPreviewCommit,
    this.onResetFilm,
  });

  final EditorState state;
  final EditorController controller;
  final EditorRecipeSummary recipeSummary;
  final EditorGpuPreviewCallback? onGpuPreviewStart;
  final EditorGpuPreviewCallback? onGpuPreviewChanged;
  final EditorGpuPreviewCallback? onGpuPreviewCommit;
  final EditorResetCallback? onResetFilm;

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
          Text(
            selectedProfile.description,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${selectedProfile.name} strength',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              TextButton.icon(
                onPressed: recipeSummary.hasFilmChange &&
                        !state.isPreviewProcessing &&
                        onResetFilm != null
                    ? onResetFilm
                    : null,
                icon: const Icon(Icons.restart_alt_rounded, size: 18),
                label: const Text('Reset Film'),
              ),
            ],
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 7,
                  ),
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
  const _CropPanel();

  @override
  Widget build(BuildContext context) {
    return const Card.filled(
      key: ValueKey('crop'),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.touch_app_rounded),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Adjust the crop directly on the image. Choose an aspect ratio, drag or resize the frame, then tap Apply Crop.',
              ),
            ),
          ],
        ),
      ),
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
            IconButton.filledTonal(
              onPressed: controller.rotateLeft,
              tooltip: 'Rotate left',
              icon: const Icon(Icons.rotate_left),
            ),
            IconButton.filledTonal(
              onPressed: controller.rotateRight,
              tooltip: 'Rotate right',
              icon: const Icon(Icons.rotate_right),
            ),
            IconButton.filledTonal(
              onPressed: controller.flipHorizontal,
              tooltip: 'Flip horizontal',
              icon: const Icon(Icons.flip),
            ),
            IconButton.filledTonal(
              onPressed: controller.flipVertical,
              tooltip: 'Flip vertical',
              icon: const RotatedBox(quarterTurns: 1, child: Icon(Icons.flip)),
            ),
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
        Text(
          'Rust ${state.processingMs.toStringAsFixed(2)} ms · '
          '${state.cursor}/${state.operationCount} edits',
        ),
      ],
    );
  }
}
