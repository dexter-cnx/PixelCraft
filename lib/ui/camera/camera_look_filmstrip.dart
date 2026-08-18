import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../camera/camera_film_presets.dart';

const _accent = Color(0xFFFF6A00);
const _fallbackPreviewAsset = 'assets/samples/sample_1.png';

class CameraLookFilmstripItem {
  const CameraLookFilmstripItem({
    required this.id,
    required this.label,
    required this.index,
    this.previewBytes,
  });

  final String id;
  final String label;
  final int index;
  final Uint8List? previewBytes;
}

class CameraLookFilmstrip extends StatelessWidget {
  const CameraLookFilmstrip({
    required this.items,
    required this.selectedId,
    required this.onSelected,
    this.enabled = true,
    this.isLoadingPreviews = false,
    super.key,
  });

  final List<CameraLookFilmstripItem> items;
  final String selectedId;
  final ValueChanged<String> onSelected;
  final bool enabled;
  final bool isLoadingPreviews;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 126,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final item = items[index];
          final selected = item.id == selectedId;
          return Semantics(
            button: true,
            selected: selected,
            label: item.label,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: enabled ? () => onSelected(item.id) : null,
              child: AnimatedScale(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                scale: selected ? 1 : 0.94,
                child: SizedBox(
                  width: 94,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        width: selected ? 84 : 76,
                        height: selected ? 84 : 76,
                        decoration: BoxDecoration(
                          color: const Color(0xFF191919),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: selected ? _accent : Colors.white24,
                            width: selected ? 2.5 : 1,
                          ),
                          boxShadow: selected
                              ? const [
                                  BoxShadow(
                                    color: Color(0x55FF6A00),
                                    blurRadius: 14,
                                  ),
                                ]
                              : null,
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: _PreviewTile(
                          item: item,
                          isLoading: isLoadingPreviews,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: selected ? Colors.white : Colors.white70,
                          fontSize: 12,
                          fontWeight: selected
                              ? FontWeight.w800
                              : FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        width: selected ? 22 : 0,
                        height: 2.5,
                        decoration: BoxDecoration(
                          color: _accent,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PreviewTile extends StatelessWidget {
  const _PreviewTile({required this.item, required this.isLoading});

  final CameraLookFilmstripItem item;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final preview = item.previewBytes;
    if (preview != null) {
      return Image.memory(
        preview,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        filterQuality: FilterQuality.low,
        cacheWidth: 180,
        cacheHeight: 180,
      );
    }

    final fallback = Image.asset(
      _fallbackPreviewAsset,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.low,
      cacheWidth: 180,
      cacheHeight: 180,
      errorBuilder: (_, __, ___) => const ColoredBox(
        color: Color(0xFF202020),
        child: Center(
          child: Icon(
            Icons.photo_camera_outlined,
            color: Colors.white38,
            size: 24,
          ),
        ),
      ),
    );
    final filter = _fallbackColorFilter(item.id);

    return Stack(
      fit: StackFit.expand,
      children: [
        if (filter == null)
          fallback
        else
          ColorFiltered(colorFilter: filter, child: fallback),
        if (isLoading)
          const ColoredBox(
            color: Color(0x44000000),
            child: Center(
              child: SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white70,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

ColorFilter? _fallbackColorFilter(String id) {
  for (final preset in cameraFilmPresets) {
    if (preset.id == id) {
      return preset.isOriginal ? null : preset.colorFilter(1);
    }
  }

  return switch (id) {
    'grayscale' => const ColorFilter.matrix(<double>[
      0.3333,
      0.3333,
      0.3333,
      0,
      0,
      0.3333,
      0.3333,
      0.3333,
      0,
      0,
      0.3333,
      0.3333,
      0.3333,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ]),
    'invert' => const ColorFilter.matrix(<double>[
      -1,
      0,
      0,
      0,
      255,
      0,
      -1,
      0,
      0,
      255,
      0,
      0,
      -1,
      0,
      255,
      0,
      0,
      0,
      1,
      0,
    ]),
    _ => null,
  };
}
