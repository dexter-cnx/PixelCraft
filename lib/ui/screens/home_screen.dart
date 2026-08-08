import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/editor_session_store.dart';
import 'camera_film_preview_screen.dart';
import 'editor_screen.dart';
import 'gpu_diagnostics_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.recoverLostPickerData = true,
  });

  /// Android can recreate the app while the external camera is open. Keep
  /// this enabled in production so accepted captures are recovered through
  /// image_picker. Tests that are not exercising that platform handoff can
  /// disable it to stay deterministic and avoid a real platform-channel call.
  final bool recoverLostPickerData;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const double _cameraMaxDimension = 2560;

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
        builder: (_) => EditorScreen(imagePath: picked.path),
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

  Future<void> _openGpuDiagnostics() async {
    if (!kDebugMode || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const GpuDiagnosticsScreen()),
    );
  }

  Future<void> _openBytes(Future<List<int>> bytesFuture) async {
    final bytes = await bytesFuture;
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => EditorScreen(imageBytes: bytes)),
    );
    await _refreshRecovery();
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
        builder: (_) => EditorScreen(
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
      final picked = await _picker.pickImage(
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

  Future<void> _showImageSourceSheet() async {
    if (_isRecovering) return;

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.filter_vintage_outlined),
              title: const Text('Film Camera'),
              subtitle: const Text('Preview Film Profiles live before capture'),
              onTap: () {
                Navigator.of(context).pop();
                Future.microtask(_openFilmCamera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              subtitle: const Text('Fast system camera capture'),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              subtitle: const Text('Open an existing image on this device'),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (source != null && mounted) {
      await _pickImage(source);
    }
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

    const samples = [
      'sample_1.png',
      'sample_2.png',
      'sample_3.png',
      'sample_4.png',
    ];
    final blocked = _isRecovering;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pixel Craft'),
        actions: [
          if (kDebugMode)
            IconButton(
              tooltip: 'GPU Diagnostics',
              onPressed: blocked ? null : _openGpuDiagnostics,
              icon: const Icon(Icons.developer_mode_rounded),
            ),
        ],
      ),
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                sliver: SliverList.list(
                  children: [
                    Text(
                      'Edit locally. Move fast.',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Capture or import a photo, then edit it locally with Rust-powered processing.',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    if (_recoverableSession != null) ...[
                      const SizedBox(height: 20),
                      Card.filled(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              const Icon(Icons.history_rounded),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Resume last edit',
                                      style: TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                    SizedBox(height: 2),
                                    Text('Restore the original image and its edit recipe.'),
                                  ],
                                ),
                              ),
                              TextButton(
                                onPressed: blocked ? null : _discardRecovery,
                                child: const Text('Discard'),
                              ),
                              const SizedBox(width: 4),
                              FilledButton(
                                onPressed: blocked ? null : _resumeLastSession,
                                child: const Text('Resume'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                  ],
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverGrid.builder(
                  itemCount: samples.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemBuilder: (context, index) => InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: blocked
                        ? null
                        : () => _openBytes(
                              DefaultAssetBundle.of(context)
                                  .load('assets/samples/${samples[index]}')
                                  .then((data) => data.buffer.asUint8List()),
                            ),
                    child: Hero(
                      tag: samples[index],
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Image.asset(
                          'assets/samples/${samples[index]}',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
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
        icon: const Icon(Icons.add_a_photo_outlined),
        label: const Text('Add Photo'),
        onPressed: blocked ? null : _showImageSourceSheet,
      ),
    );
  }
}
