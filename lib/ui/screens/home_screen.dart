import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/editor_session_store.dart';
import 'camera_film_preview_screen.dart';
import 'film_profiles_screen.dart';
import 'gpu_diagnostics_screen.dart';
import 'product_editor_screen.dart';

typedef HomePickImage = Future<XFile?> Function({
  required ImageSource source,
  required CameraDevice preferredCameraDevice,
  double? maxWidth,
  double? maxHeight,
  int? imageQuality,
  required bool requestFullMetadata,
});

enum _AcquisitionAction {
  filmCamera,
  systemCamera,
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.recoverLostPickerData = true,
    this.showGpuDiagnostics = kDebugMode,
    this.pickImageForTesting,
  });

  final bool recoverLostPickerData;
  final bool showGpuDiagnostics;
  final HomePickImage? pickImageForTesting;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const double _cameraMaxDimension = 2560;
  static const double _recentThumbnailExtent = 88;

  final ImagePicker _picker = ImagePicker();
  final EditorSessionStore _sessionStore = EditorSessionStore();
  bool _isRecovering = false;
  bool _isRecoveringLostPickerData = false;
  bool _lostPickerRecoveryStarted = false;
  StoredEditorSession? _recoverableSession;

  @override
  void initState() {
    super.initState();
    _refreshRecovery();

    if (widget.recoverLostPickerData) {
      _isRecoveringLostPickerData = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _recoverLostPickerData();
      });
    }
  }

  Future<void> _refreshRecovery() async {
    final session = await _sessionStore.load();
    if (!mounted) return;
    setState(() => _recoverableSession = session);
  }

  Future<void> _recoverLostPickerData() async {
    if (_lostPickerRecoveryStarted) return;
    _lostPickerRecoveryStarted = true;

    try {
      final response = await _picker.retrieveLostData();
      if (!mounted) return;

      final files = response.files;
      if (files != null && files.isNotEmpty) {
        await _openPickedFile(files.first);
        return;
      }

      final exception = response.exception;
      if (exception != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera recovery failed: $exception')),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Camera recovery failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isRecoveringLostPickerData = false);
      }
    }
  }

  Future<void> _openPickedFile(XFile picked) async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProductEditorScreen(imagePath: picked.path),
      ),
    );
    await _refreshRecovery();
  }

  Future<void> _openFilmCamera() async {
    if (_isRecovering || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CameraFilmPreviewScreen()),
    );
    await _refreshRecovery();
  }

  Future<void> _openFilmProfiles() async {
    if (_isRecovering || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const FilmProfilesScreen()),
    );
  }

  Future<void> _openGpuDiagnostics() async {
    if (!widget.showGpuDiagnostics || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const GpuDiagnosticsScreen()),
    );
  }

  Future<void> _resumeLastSession() async {
    if (_isRecovering || _recoverableSession == null) return;
    setState(() => _isRecovering = true);
    final session = await _sessionStore.load();
    if (!mounted) return;
    if (session == null) {
      setState(() {
        _isRecovering = false;
        _recoverableSession = null;
      });
      return;
    }

    setState(() => _isRecovering = false);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProductEditorScreen(
          imageBytes: session.originalBytes,
          recoveryRecipe: session.recipeJson,
        ),
      ),
    );
    await _refreshRecovery();
  }

  Future<void> _discardRecovery() async {
    await _sessionStore.clear();
    if (!mounted) return;
    setState(() => _recoverableSession = null);
  }

  Future<void> _pickImage(ImageSource source) async {
    if (_isRecovering) return;

    final isCamera = source == ImageSource.camera;
    try {
      final pickImage = widget.pickImageForTesting;
      final picked = pickImage != null
          ? await pickImage(
              source: source,
              preferredCameraDevice: CameraDevice.rear,
              maxWidth: isCamera ? _cameraMaxDimension : null,
              maxHeight: isCamera ? _cameraMaxDimension : null,
              imageQuality: isCamera ? 90 : null,
              requestFullMetadata: false,
            )
          : await _picker.pickImage(
              source: source,
              preferredCameraDevice: CameraDevice.rear,
              maxWidth: isCamera ? _cameraMaxDimension : null,
              maxHeight: isCamera ? _cameraMaxDimension : null,
              imageQuality: isCamera ? 90 : null,
              requestFullMetadata: false,
            );
      if (picked == null || !mounted) return;

      await _openPickedFile(picked);
    } catch (error) {
      if (!mounted) return;
      final action = isCamera ? 'Camera capture' : 'Import';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$action failed: $error')),
      );
    }
  }

  Future<void> _handleAcquisitionAction(_AcquisitionAction action) async {
    switch (action) {
      case _AcquisitionAction.filmCamera:
        await _openFilmCamera();
      case _AcquisitionAction.systemCamera:
        await _pickImage(ImageSource.camera);
    }
  }

  String? _formatSavedAt(DateTime savedAt) {
    if (savedAt.millisecondsSinceEpoch <= 0) return null;

    final local = savedAt.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  Widget _buildWorkspaceBody(BuildContext context, {required bool blocked}) {
    final session = _recoverableSession;
    if (session != null) {
      final savedAtLabel = _formatSavedAt(session.savedAt);
      final thumbnailCacheSize =
          (_recentThumbnailExtent * MediaQuery.devicePixelRatioOf(context)).ceil();

      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 112),
        children: [
          Text('Recent edit', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Card.filled(
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(
                      session.originalBytes,
                      width: _recentThumbnailExtent,
                      height: _recentThumbnailExtent,
                      cacheWidth: thumbnailCacheSize,
                      cacheHeight: thumbnailCacheSize,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      errorBuilder: (context, error, stackTrace) => Container(
                        width: _recentThumbnailExtent,
                        height: _recentThumbnailExtent,
                        alignment: Alignment.center,
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.image_not_supported_outlined),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Last edit',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        if (savedAtLabel != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Saved $savedAtLabel',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.tonal(
                              onPressed: blocked ? null : _resumeLastSession,
                              child: const Text('Resume'),
                            ),
                            TextButton(
                              onPressed: blocked ? null : _discardRecovery,
                              child: const Text('Discard'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 32, 32, 112),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.photo_library_outlined,
                size: 44,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 18),
              Text(
                'Your workspace is empty',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Import a photo to start editing.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isRecoveringLostPickerData) {
      return const Scaffold(
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(
                  dimension: 28,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                SizedBox(height: 16),
                Text('Opening captured photo…'),
              ],
            ),
          ),
        ),
      );
    }

    final blocked = _isRecovering;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dextryx Pixels'),
        actions: [
          PopupMenuButton<_AcquisitionAction>(
            tooltip: 'More ways to add',
            enabled: !blocked,
            icon: const Icon(Icons.add_circle_outline_rounded),
            onSelected: _handleAcquisitionAction,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _AcquisitionAction.filmCamera,
                child: Row(
                  children: [
                    Icon(Icons.filter_vintage_outlined, size: 20),
                    SizedBox(width: 12),
                    Text('Film Camera'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: _AcquisitionAction.systemCamera,
                child: Row(
                  children: [
                    Icon(Icons.photo_camera_outlined, size: 20),
                    SizedBox(width: 12),
                    Text('Take Photo'),
                  ],
                ),
              ),
            ],
          ),
          IconButton(
            tooltip: 'Films',
            onPressed: blocked ? null : _openFilmProfiles,
            icon: const Icon(Icons.camera_roll_outlined),
          ),
          if (widget.showGpuDiagnostics)
            IconButton(
              tooltip: 'GPU Diagnostics',
              onPressed: blocked ? null : _openGpuDiagnostics,
              icon: const Icon(Icons.developer_mode_rounded),
            ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: _buildWorkspaceBody(context, blocked: blocked),
          ),
          if (blocked)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x33000000),
                child: Center(
                  child: Card(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          ),
                          SizedBox(width: 12),
                          Text('Recovering session…'),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.photo_library_outlined),
        label: const Text('Import'),
        onPressed: blocked ? null : () => _pickImage(ImageSource.gallery),
      ),
    );
  }
}
