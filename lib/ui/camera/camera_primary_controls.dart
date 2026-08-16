import 'package:flutter/material.dart';

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
    this.isCapturing = false,
    super.key,
  });

  final CameraPrimaryTool selectedTool;
  final ValueChanged<CameraPrimaryTool> onToolSelected;
  final VoidCallback? onGalleryPressed;
  final VoidCallback? onShutterPressed;
  final VoidCallback? onControlsPressed;
  final String galleryLabel;
  final String filmLabel;
  final String filterLabel;
  final String adjustLabel;
  final String controlsLabel;
  final String shutterSemanticLabel;
  final bool isCapturing;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Color(0xF2000000)],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 42, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ToolSelector(
              selectedTool: selectedTool,
              onSelected: onToolSelected,
              filmLabel: filmLabel,
              filterLabel: filterLabel,
              adjustLabel: adjustLabel,
            ),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: _SideAction(
                    icon: Icons.photo_library_outlined,
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
                              BoxShadow(color: Colors.black45, blurRadius: 12),
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
    required this.onSelected,
    required this.filmLabel,
    required this.filterLabel,
    required this.adjustLabel,
  });

  final CameraPrimaryTool selectedTool;
  final ValueChanged<CameraPrimaryTool> onSelected;
  final String filmLabel;
  final String filterLabel;
  final String adjustLabel;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<CameraPrimaryTool>(
      key: const Key('camera-tool-selector'),
      segments: [
        ButtonSegment(value: CameraPrimaryTool.film, label: Text(filmLabel)),
        ButtonSegment(value: CameraPrimaryTool.filter, label: Text(filterLabel)),
        ButtonSegment(value: CameraPrimaryTool.adjust, label: Text(adjustLabel)),
      ],
      selected: {selectedTool},
      onSelectionChanged: (selection) {
        if (selection.isNotEmpty) onSelected(selection.first);
      },
      showSelectedIcon: false,
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.black
              : Colors.white,
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : Colors.black54,
        ),
        side: WidgetStateProperty.all(
          const BorderSide(color: Colors.white38),
        ),
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
          Icon(icon, size: 26),
          const SizedBox(height: 4),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}
