from pathlib import Path

path = Path('lib/ui/screens/camera_film_preview_screen_g1.dart')
text = path.read_text()

# Imports for exact Rust-authored look thumbnails from a clean camera snapshot.
text = text.replace(
    "import 'dart:async';\n",
    "import 'dart:async';\nimport 'dart:io';\nimport 'dart:isolate';\nimport 'dart:typed_data';\n",
    1,
)
if "import '../../core/bridge.dart';\n" not in text:
    text = text.replace(
        "import '../../camera/camera_look_state.dart';\n",
        "import '../../camera/camera_look_state.dart';\n"
        "import '../../core/bridge.dart';\n"
        "import '../../src/rust/api.dart' as rust;\n",
        1,
    )

state_anchor = (
    "  CameraPrimaryTool _selectedTool = CameraPrimaryTool.film;\n"
    "  CameraLookState _cameraLook = CameraLookState();\n"
)
assert state_anchor in text
text = text.replace(
    state_anchor,
    "  CameraPrimaryTool _selectedTool = CameraPrimaryTool.film;\n"
    "  bool _toolPanelExpanded = false;\n"
    "  CameraLookState _cameraLook = CameraLookState();\n"
    "  Map<String, Uint8List> _filmPreviewBytes = const {};\n"
    "  Map<String, Uint8List> _filterPreviewBytes = const {};\n"
    "  bool _isLoadingLookPreviews = false;\n"
    "  int _lookPreviewRequest = 0;\n",
    1,
)

# Replace tool selection behavior and add reset/preview helpers.
select_start = text.index('  void _selectTool(CameraPrimaryTool tool) {')
controls_start = text.index('  Future<void> _showCameraControls() async {', select_start)
helpers = r'''  bool _adjustmentChanged(String id) {
    final spec = cameraAdjustmentSpec(id);
    return (_cameraLook.adjustmentValue(id) - spec.neutral).abs() > 0.000001;
  }

  void _resetAdjustment(String id) {
    if (!_adjustmentChanged(id)) return;
    setState(() => _cameraLook = _cameraLook.resetAdjustment(id));
    _submitCameraLook();
  }

  void _resetAllAdjustments() {
    setState(() => _cameraLook = _cameraLook.resetAdjustments());
    _submitCameraLook();
  }

  Future<void> _refreshLookPreviews(CameraPrimaryTool tool) async {
    if (_isCapturing || !_useNativeGpu || _gpuRendererId == null) return;
    if (tool != CameraPrimaryTool.film && tool != CameraPrimaryTool.filter) {
      return;
    }

    final request = ++_lookPreviewRequest;
    if (mounted) setState(() => _isLoadingLookPreviews = true);
    String? snapshotPath;
    try {
      // Capture once when the chooser opens. The preview session stays alive;
      // the clean JPEG is temporary and is never written to the system Gallery.
      snapshotPath = await _nativeCameraBridge.capturePhoto(_gpuRendererId!);
      final source = await File(snapshotPath).readAsBytes();
      final previews = await Isolate.run(() async {
        await initializeRustBridge();
        if (tool == CameraPrimaryTool.film) {
          final ids = cameraFilmPresets
              .where((preset) => !preset.isOriginal)
              .map((preset) => preset.id)
              .toList(growable: false);
          final generated = rust.generateFilmProfilePreviews(
            imageBytes: source,
            profileIds: ids,
            maxEdge: 180,
          );
          return <String, Uint8List>{
            '': source,
            for (final preview in generated) preview.id: preview.bytes,
          };
        }
        final ids = cameraCreativeFilters
            .map((filter) => filter.id)
            .toList(growable: false);
        final generated = rust.generateFilterPreviews(
          imageBytes: source,
          filterNames: ids,
          maxEdge: 180,
        );
        return <String, Uint8List>{
          '': source,
          for (final preview in generated) preview.name: preview.bytes,
        };
      });
      if (!mounted || request != _lookPreviewRequest) return;
      setState(() {
        if (tool == CameraPrimaryTool.film) {
          _filmPreviewBytes = previews;
        } else {
          _filterPreviewBytes = previews;
        }
      });
    } catch (_) {
      // A preview snapshot is optional UX. Keep Film/Filter selection usable.
    } finally {
      if (snapshotPath != null) {
        try {
          await File(snapshotPath).delete();
        } catch (_) {}
      }
      if (mounted && request == _lookPreviewRequest) {
        setState(() => _isLoadingLookPreviews = false);
      }
    }
  }

  void _selectTool(CameraPrimaryTool tool) {
    if (tool != CameraPrimaryTool.film && !_useNativeGpu) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('camera.native_look_required'.tr())),
      );
      return;
    }
    final willExpand = tool != _selectedTool || !_toolPanelExpanded;
    setState(() {
      _selectedTool = tool;
      _toolPanelExpanded = willExpand;
    });
    if (willExpand &&
        (tool == CameraPrimaryTool.film || tool == CameraPrimaryTool.filter)) {
      unawaited(_refreshLookPreviews(tool));
    }
  }

  void _openAdjustment(String id) {
    setState(() {
      _selectedAdjustmentId = id;
      _selectedTool = CameraPrimaryTool.adjust;
      _toolPanelExpanded = true;
    });
  }

'''
text = text[:select_start] + helpers + text[controls_start:]

# Film selector uses exact Rust-generated previews.
film_item = (
    "          index: index,\n"
    "        ),\n"
    "    ];\n"
    "    return Positioned(\n"
)
assert film_item in text
text = text.replace(
    film_item,
    "          index: index,\n"
    "          previewBytes: _filmPreviewBytes[cameraFilmPresets[index].id],\n"
    "        ),\n"
    "    ];\n"
    "    return Positioned(\n",
    1,
)
film_call = (
    "              CameraLookFilmstrip(\n"
    "                items: items,\n"
    "                selectedId: _preset.id,\n"
    "                enabled: !_isCapturing,\n"
)
assert film_call in text
text = text.replace(
    film_call,
    film_call + "                isLoadingPreviews: _isLoadingLookPreviews,\n",
    1,
)

# Filter selector uses exact Rust-generated previews.
filter_items = """      CameraLookFilmstripItem(id: '', label: 'camera.original'.tr(), index: 0),
      for (var index = 0; index < cameraCreativeFilters.length; index++)
        CameraLookFilmstripItem(
          id: cameraCreativeFilters[index].id,
          label: 'camera.${cameraCreativeFilters[index].id}'.tr(),
          index: index + 1,
        ),
"""
assert filter_items in text
text = text.replace(
    filter_items,
    """      CameraLookFilmstripItem(
        id: '',
        label: 'camera.original'.tr(),
        index: 0,
        previewBytes: _filterPreviewBytes[''],
      ),
      for (var index = 0; index < cameraCreativeFilters.length; index++)
        CameraLookFilmstripItem(
          id: cameraCreativeFilters[index].id,
          label: 'camera.${cameraCreativeFilters[index].id}'.tr(),
          index: index + 1,
          previewBytes: _filterPreviewBytes[cameraCreativeFilters[index].id],
        ),
""",
    1,
)
filter_call = (
    "              CameraLookFilmstrip(\n"
    "                items: items,\n"
    "                selectedId: activeId,\n"
    "                enabled: !_isCapturing,\n"
)
assert filter_call in text
text = text.replace(
    filter_call,
    filter_call + "                isLoadingPreviews: _isLoadingLookPreviews,\n",
    1,
)

# Keep the camera idle view compact. Tapping Film/Filter/Adjust opens that tray;
# tapping the active tool again collapses it.
text = text.replace(
    "            if (_selectedTool == CameraPrimaryTool.film) _buildFilmControls(),\n",
    "            if (_toolPanelExpanded &&\n"
    "                _selectedTool == CameraPrimaryTool.film)\n"
    "              _buildFilmControls(),\n",
    1,
)
text = text.replace(
    "            if (_selectedTool == CameraPrimaryTool.filter)\n"
    "              _buildFilterControls(),\n",
    "            if (_toolPanelExpanded &&\n"
    "                _selectedTool == CameraPrimaryTool.filter)\n"
    "              _buildFilterControls(),\n",
    1,
)
text = text.replace(
    "            if (_selectedTool == CameraPrimaryTool.adjust)\n"
    "              _buildAdjustControls(),\n",
    "            if (_toolPanelExpanded &&\n"
    "                _selectedTool == CameraPrimaryTool.adjust)\n"
    "              _buildAdjustControls(),\n"
    "            _buildActiveAdjustmentIndicators(),\n",
    1,
)

controls_anchor = (
    "              child: CameraPrimaryControls(\n"
    "                selectedTool: _selectedTool,\n"
    "                onToolSelected: _selectTool,\n"
)
assert controls_anchor in text
text = text.replace(
    controls_anchor,
    "              child: CameraPrimaryControls(\n"
    "                selectedTool: _selectedTool,\n"
    "                isToolPanelExpanded: _toolPanelExpanded,\n"
    "                onToolSelected: _selectTool,\n",
    1,
)
labels_anchor = (
    "                adjustLabel: 'camera.adjust'.tr(),\n"
    "                controlsLabel: 'camera.controls'.tr(),\n"
)
assert labels_anchor in text
text = text.replace(
    labels_anchor,
    "                adjustLabel: 'camera.adjust'.tr(),\n"
    "                filmSummary: _preset.isOriginal\n"
    "                    ? 'Original'\n"
    "                    : '${_preset.name.replaceAll(' Inspired', '')} · ${(_strength * 100).round()}%',\n"
    "                filterSummary: _cameraLook.creativeFilterId.isEmpty\n"
    "                    ? 'Original'\n"
    "                    : '${'camera.${_cameraLook.creativeFilterId}'.tr()} · ${(_cameraLook.creativeFilterStrength * 100).round()}%',\n"
    "                controlsLabel: 'camera.controls'.tr(),\n",
    1,
)

# Replace Adjust tray with Reset All, per-adjustment reset, and compact active
# indicators on the right side of the viewfinder.
adjust_start = text.index('  Widget _buildAdjustControls() {')
class_end = text.rfind('\n}')
adjust = r'''  Widget _buildActiveAdjustmentIndicators() {
    final changed = _cameraAdjustmentIds
        .where(_adjustmentChanged)
        .toList(growable: false);
    if (changed.isEmpty) return const SizedBox.shrink();
    const shortLabels = <String, String>{
      'exposure': 'EV',
      'temperature': 'Temp',
      'tint': 'Tint',
      'brightness': 'Bright',
      'contrast': 'Contrast',
      'saturation': 'Sat',
      'vignette': 'Vign',
    };
    return Positioned(
      right: 10,
      top: 78,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final id in changed)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: GestureDetector(
                onTap: _isCapturing ? null : () => _openAdjustment(id),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.58),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    child: Text(
                      '${shortLabels[id]} ${_cameraLook.adjustmentValue(id).toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAdjustControls() {
    final spec = cameraAdjustmentSpec(_selectedAdjustmentId);
    final value = _cameraLook.adjustmentValue(_selectedAdjustmentId);
    final selectedChanged = _adjustmentChanged(_selectedAdjustmentId);
    return Positioned(
      left: 0,
      right: 0,
      bottom: 150,
      child: DecoratedBox(
        decoration: _lookPanelDecoration,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 30, 16, 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${'camera.$_selectedAdjustmentId'.tr()}  ${value.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Reset',
                    onPressed: selectedChanged && !_isCapturing
                        ? () => _resetAdjustment(_selectedAdjustmentId)
                        : null,
                    icon: const Icon(Icons.refresh_rounded),
                    color: Colors.white,
                    disabledColor: Colors.white24,
                  ),
                  TextButton.icon(
                    onPressed: _isCapturing ? null : _resetAllAdjustments,
                    icon: const Icon(Icons.restart_alt_rounded, size: 18),
                    label: const Text('Reset All'),
                    style: TextButton.styleFrom(foregroundColor: Colors.white70),
                  ),
                ],
              ),
              Slider(
                value: value,
                min: spec.min,
                max: spec.max,
                onChanged: _isCapturing ? null : _setAdjustment,
              ),
              SizedBox(
                height: 46,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _cameraAdjustmentIds.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final id = _cameraAdjustmentIds[index];
                    final selected = id == _selectedAdjustmentId;
                    final changed = _adjustmentChanged(id);
                    return InputChip(
                      selected: selected,
                      label: Text('camera.$id'.tr()),
                      onSelected: _isCapturing
                          ? null
                          : (_) => _selectAdjustment(id),
                      onDeleted: changed && !_isCapturing
                          ? () => _resetAdjustment(id)
                          : null,
                      deleteIcon: const Icon(Icons.refresh_rounded, size: 16),
                      deleteIconColor: const Color(0xFFFF6A00),
                      selectedColor: Colors.white,
                      backgroundColor: Colors.black54,
                      side: BorderSide(
                        color: changed
                            ? const Color(0xFFFF6A00)
                            : selected
                            ? Colors.white
                            : Colors.white38,
                      ),
                      labelStyle: TextStyle(
                        color: selected ? Colors.black : Colors.white,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                      showCheckmark: false,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
'''
text = text[:adjust_start] + adjust + text[class_end:]

path.write_text(text)
