import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../camera/camera_film_presets.dart';
import '../../camera/camera_recent_thumbnail.dart';

const _accent = Color(0xFFFF6A00);

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
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      unawaited(_LivePreviewSnapshotSource.instance.refresh());
    }

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
      return _buildPreviewImage(preview);
    }

    return ValueListenableBuilder<Uint8List?>(
      valueListenable: _LivePreviewSnapshotSource.instance.bytes,
      builder: (context, liveBytes, _) {
        if (liveBytes != null && liveBytes.isNotEmpty) {
          return _buildFallbackPreview(liveBytes);
        }
        return ValueListenableBuilder<Uint8List?>(
          valueListenable: CameraRecentThumbnail.instance.bytes,
          builder: (context, recentBytes, _) {
            if (recentBytes != null && recentBytes.isNotEmpty) {
              return _buildFallbackPreview(recentBytes);
            }
            return _buildFallbackPreview(null);
          },
        );
      },
    );
  }

  Widget _buildFallbackPreview(Uint8List? sourceBytes) {
    final Widget image = sourceBytes != null && sourceBytes.isNotEmpty
        ? _buildPreviewImage(sourceBytes)
        : const ColoredBox(
            color: Color(0xFF202020),
            child: Center(
              child: Icon(
                Icons.photo_camera_outlined,
                color: Colors.white38,
                size: 24,
              ),
            ),
          );
    final filter = _fallbackColorFilter(item.id);

    return Stack(
      fit: StackFit.expand,
      children: [
        if (filter == null)
          image
        else
          ColorFiltered(colorFilter: filter, child: image),
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

  Widget _buildPreviewImage(Uint8List bytes) => Image.memory(
    bytes,
    fit: BoxFit.cover,
    gaplessPlayback: true,
    filterQuality: FilterQuality.low,
    cacheWidth: 180,
    cacheHeight: 180,
  );
}

class _LivePreviewSnapshotSource {
  _LivePreviewSnapshotSource._();

  static final instance = _LivePreviewSnapshotSource._();
  static const _channel = MethodChannel('dev.pixelcraft/gpu_preview_snapshot_v1');
  static const _minimumRefreshInterval = Duration(milliseconds: 180);

  final ValueNotifier<Uint8List?> bytes = ValueNotifier<Uint8List?>(null);
  Future<void>? _pending;
  DateTime? _lastRequestedAt;

  Future<void> refresh() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return Future<void>.value();
    }
    final pending = _pending;
    if (pending != null) return pending;
    final now = DateTime.now();
    final lastRequestedAt = _lastRequestedAt;
    if (lastRequestedAt != null &&
        now.difference(lastRequestedAt) < _minimumRefreshInterval) {
      return Future<void>.value();
    }
    _lastRequestedAt = now;
    final future = _request();
    _pending = future;
    return future.whenComplete(() {
      if (identical(_pending, future)) _pending = null;
    });
  }

  Future<void> _request() async {
    try {
      final snapshot = await _channel.invokeMethod<Uint8List>(
        'snapshot',
        const <String, Object?>{
          'maxEdge': 180,
          'jpegQuality': 0.72,
        },
      );
      if (snapshot != null && snapshot.isNotEmpty) {
        bytes.value = Uint8List.fromList(snapshot);
      }
    } on PlatformException catch (error) {
      if (kDebugMode) {
        debugPrint('[PF3][LookPreview] live snapshot unavailable: $error');
      }
    } on MissingPluginException catch (error) {
      if (kDebugMode) {
        debugPrint('[PF3][LookPreview] live snapshot channel unavailable: $error');
      }
    }
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
