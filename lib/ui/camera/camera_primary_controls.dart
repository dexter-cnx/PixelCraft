import 'dart:async';

import 'package:flutter/material.dart';

import '../../camera/camera_recent_thumbnail.dart';

enum CameraPrimaryTool { film, filter, adjust }

class CameraPrimaryControls extends StatelessWidget {
  const CameraPrimaryControls({
    required this.selectedTool,
    required this.onToolSelected,
    required this.onGalleryPressed,
    required this.onShutterPressed,
    required this.onControlsPressed,
    required this.galleryLabel,
    required this.filmLabel,
    required this.filterLabel,
    required this.adjustLabel,
    required this.controlsLabel,
    required this.shutterSemanticLabel,
    this.isToolPanelExpanded = true,
    this.filmSummary = '',
    this.filterSummary = '',
    this.zoomFactor = 1,
    this.zoomQuarterTurns = 0,
    this.isCapturing = false,
    super.key,
  });

  final CameraPrimaryTool selectedTool;
  final bool isToolPanelExpanded;
  final ValueChanged<CameraPrimaryTool> onToolSelected;
  final VoidCallback? onGalleryPressed;
  final VoidCallback? onShutterPressed;
  final VoidCallback? onControlsPressed;
  final String galleryLabel;
  final String filmLabel;
  final String filterLabel;
  final String adjustLabel;
  final String filmSummary;
  final String filterSummary;
  final String controlsLabel;
  final String shutterSemanticLabel;
  final double zoomFactor;
  final int zoomQuarterTurns;
  final bool isCapturing;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0, 0.30, 1],
          colors: [Color(0x33000000), Color(0xCC000000), Color(0xFA000000)],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IgnorePointer(
              child: RotatedBox(
                quarterTurns: zoomQuarterTurns,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.62),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    child: Text(
                      '${zoomFactor.toStringAsFixed(zoomFactor < 2 ? 1 : 1)}×',
                      key: const Key('camera-zoom-indicator'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 2),
            _ToolSelector(
              selectedTool: selectedTool,
              isExpanded: isToolPanelExpanded,
              onSelected: onToolSelected,
              filmLabel: filmLabel,
              filterLabel: filterLabel,
              adjustLabel: adjustLabel,
              filmSummary: filmSummary,
              filterSummary: filterSummary,
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: _GalleryAction(
                    label: galleryLabel,
                    onPressed: isCapturing ? null : onGalleryPressed,
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Semantics(
                      button: true,
                      label: shutterSemanticLabel,
                      child: GestureDetector(
                        key: const Key('camera-shutter'),
                        onTap: isCapturing ? null : onShutterPressed,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                            border: Border.all(color: Colors.white70, width: 4),
                            boxShadow: const [
                              BoxShadow(color: Colors.black87, blurRadius: 14),
                            ],
                          ),
                          child: Center(
                            child: isCapturing
                                ? const SizedBox.square(
                                    dimension: 26,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.black,
                                    ),
                                  )
                                : Container(
                                    width: 60,
                                    height: 60,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.black12),
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: _SideAction(
                    icon: Icons.tune,
                    label: controlsLabel,
                    onPressed: isCapturing ? null : onControlsPressed,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolSelector extends StatelessWidget {
  const _ToolSelector({
    required this.selectedTool,
    required this.isExpanded,
    required this.onSelected,
    required this.filmLabel,
    required this.filterLabel,
    required this.adjustLabel,
    required this.filmSummary,
    required this.filterSummary,
  });

  static const _accent = Color(0xFFFF6A00);
  static const _textShadow = [
    Shadow(color: Colors.black, blurRadius: 5),
    Shadow(color: Colors.black87, offset: Offset(0, 1), blurRadius: 2),
  ];

  final CameraPrimaryTool selectedTool;
  final bool isExpanded;
  final ValueChanged<CameraPrimaryTool> onSelected;
  final String filmLabel;
  final String filterLabel;
  final String adjustLabel;
  final String filmSummary;
  final String filterSummary;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      child: Row(
        key: const Key('camera-tool-selector'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _item(
              CameraPrimaryTool.film,
              filmLabel,
              summary: filmSummary,
            ),
          ),
          Expanded(
            child: _item(
              CameraPrimaryTool.filter,
              filterLabel,
              summary: filterSummary,
            ),
          ),
          Expanded(child: _item(CameraPrimaryTool.adjust, adjustLabel)),
        ],
      ),
    );
  }

  Widget _item(CameraPrimaryTool tool, String label, {String? summary}) {
    final selected = selectedTool == tool && isExpanded;
    final hasSummary = summary != null && summary.isNotEmpty;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onSelected(tool),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(5, 8, 5, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              style: TextStyle(
                color: selected ? _accent : Colors.white,
                fontSize: 14,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                shadows: _textShadow,
              ),
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            if (hasSummary) ...[
              const SizedBox(height: 2),
              Text(
                summary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white70,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  shadows: _textShadow,
                ),
              ),
            ] else
              const SizedBox(height: 14),
            const SizedBox(height: 4),
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: selected ? 24 : 0,
              height: 2.5,
              decoration: BoxDecoration(
                color: _accent,
                borderRadius: BorderRadius.circular(99),
                boxShadow: const [
                  BoxShadow(color: Colors.black87, blurRadius: 3),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GalleryAction extends StatefulWidget {
  const _GalleryAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  State<_GalleryAction> createState() => _GalleryActionState();
}

class _GalleryActionState extends State<_GalleryAction> {
  @override
  void initState() {
    super.initState();
    unawaited(CameraRecentThumbnail.instance.ensureLoaded());
  }

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: widget.onPressed,
      style: TextButton.styleFrom(foregroundColor: Colors.white),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ValueListenableBuilder(
            valueListenable: CameraRecentThumbnail.instance.bytes,
            builder: (context, bytes, _) {
              if (bytes == null) {
                return const Icon(Icons.photo_library_outlined, size: 26);
              }
              return Container(
                width: 34,
                height: 34,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: Colors.white70, width: 1.5),
                ),
                child: Image.memory(
                  bytes,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                ),
              );
            },
          ),
          const SizedBox(height: 4),
          Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              shadows: [Shadow(color: Colors.black, blurRadius: 4)],
            ),
          ),
        ],
      ),
    );
  }
}

class _SideAction extends StatelessWidget {
  const _SideAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(foregroundColor: Colors.white),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.tune,
            size: 26,
            shadows: [Shadow(color: Colors.black, blurRadius: 4)],
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              shadows: [Shadow(color: Colors.black, blurRadius: 4)],
            ),
          ),
        ],
      ),
    );
  }
}
