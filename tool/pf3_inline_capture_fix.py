from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f"{label}: pattern not found")
    return text.replace(old, new, 1)


screen = Path("lib/ui/screens/camera_film_preview_screen_g1.dart")
s = screen.read_text()
s = replace_once(s, "import 'dart:async';\n", "import 'dart:async';\nimport 'dart:io';\n", "dart io import")
s = replace_once(
    s,
    "import '../../camera/camera_capture_save_handoff.dart';\n",
    "import '../../camera/camera_capture_pipeline.dart';\n",
    "capture import",
)
s = replace_once(
    s,
    "  final _lookCoordinator = CameraLookPreviewCoordinator();\n",
    "  final _lookCoordinator = CameraLookPreviewCoordinator();\n"
    "  final _capturePipeline = CameraCapturePipeline(\n"
    "    renderer: const RustCameraCaptureRenderer(),\n"
    "    saveService: const GalleryMediaSaveService(),\n"
    "  );\n"
    "  final PermissionService _permissionService =\n"
    "      const PlatformPermissionService();\n",
    "pipeline fields",
)
s = replace_once(
    s,
    "  bool _isCapturing = false;\n  String? _error;\n",
    "  bool _isCapturing = false;\n"
    "  PermissionDecision? _galleryWritePermission;\n"
    "  String? _pendingCapturePath;\n"
    "  CameraLookState? _pendingCaptureLook;\n"
    "  String? _error;\n",
    "state fields",
)
s = replace_once(
    s,
    "    unawaited(_discoverAndInitialize());\n  }\n",
    "    unawaited(_initializeStartup());\n  }\n\n"
    "  Future<void> _initializeStartup() async {\n"
    "    await _requestStartupGalleryPermission();\n"
    "    if (!mounted) return;\n"
    "    await _discoverAndInitialize();\n"
    "  }\n\n"
    "  Future<void> _requestStartupGalleryPermission() async {\n"
    "    final decision = await _permissionService.requestGalleryWrite();\n"
    "    if (!mounted) return;\n"
    "    setState(() => _galleryWritePermission = decision);\n"
    "    if (decision != PermissionDecision.granted) {\n"
    "      _showCameraSnack('camera.gallery_permission_required'.tr());\n"
    "    }\n"
    "  }\n",
    "startup",
)
s = replace_once(
    s,
    "    final controller = _controller;\n"
    "    _controller = null;\n"
    "    if (controller != null) unawaited(controller.dispose());\n"
    "    super.dispose();\n",
    "    final controller = _controller;\n"
    "    _controller = null;\n"
    "    if (controller != null) unawaited(controller.dispose());\n"
    "    final pendingCapturePath = _pendingCapturePath;\n"
    "    _pendingCapturePath = null;\n"
    "    _pendingCaptureLook = null;\n"
    "    if (pendingCapturePath != null) {\n"
    "      unawaited(_deleteCaptureBestEffort(pendingCapturePath));\n"
    "    }\n"
    "    super.dispose();\n",
    "dispose cleanup",
)
old_capture = '''  Future<void> _capture() async {
    if (_isCapturing) return;
    setState(() => _isCapturing = true);
    try {
      if (_useNativeGpu && _gpuRendererId != null) {
        await _captureNative(_gpuRendererId!);
      } else {
        await _captureFallback();
      }
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  Future<void> _captureNative(String rendererId) async {
    await _lookCoordinator.flush();
    final look = _cameraLook;
    final path = await _nativeCameraBridge.capturePhoto(rendererId);
    if (!mounted) return;
    await _gpuBridge.pause(rendererId);
    if (!mounted) return;
    await _saveCapture(path, look: look);
    if (!mounted || rendererId != _gpuRendererId) return;
    await _gpuBridge.resume(rendererId);
  }

  Future<void> _captureFallback() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        controller.value.isTakingPicture) {
      return;
    }
    final capture = await controller.takePicture();
    if (!mounted) return;
    final camera = _activeCamera;
    final look = _cameraLook;
    await _detachAndDisposeController(showLoading: true);
    if (!mounted) return;
    await _saveCapture(capture.path, look: look);
    if (!mounted) return;
    if (camera != null) await _initializeCamera(camera);
  }
'''
new_capture = '''  Future<void> _capture() async {
    if (_isCapturing) return;
    final galleryPermission = _galleryWritePermission;
    if (galleryPermission == null) {
      _showCameraSnack('camera.gallery_permission_pending'.tr());
      return;
    }
    if (galleryPermission != PermissionDecision.granted) {
      _showCameraSnack('camera.gallery_permission_required'.tr());
      return;
    }

    await _discardPendingCapture();
    if (!mounted) return;
    setState(() => _isCapturing = true);
    try {
      if (_useNativeGpu && _gpuRendererId != null) {
        await _captureNative(_gpuRendererId!);
      } else {
        await _captureFallback();
      }
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  Future<void> _captureNative(String rendererId) async {
    await _lookCoordinator.flush();
    final path = await _nativeCameraBridge.capturePhoto(rendererId);
    if (!mounted) return;
    await _processAndSaveCapture(path, look: _cameraLook);
  }

  Future<void> _captureFallback() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        controller.value.isTakingPicture) {
      return;
    }
    final capture = await controller.takePicture();
    if (!mounted) return;
    await _processAndSaveCapture(capture.path, look: _cameraLook);
  }
'''
s = replace_once(s, old_capture, new_capture, "capture flow")
old_save = '''  Future<void> _saveCapture(
    String imagePath, {
    required CameraLookState look,
  }) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => CameraCaptureSaveHandoff(
        imagePath: imagePath,
        look: look,
      ),
    ),
  );

'''
new_save = '''  void _showCameraSnack(
    String message, {
    Duration duration = const Duration(seconds: 2),
    SnackBarAction? action,
  }) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text(message), duration: duration, action: action),
    );
  }

  Future<void> _processAndSaveCapture(
    String imagePath, {
    required CameraLookState look,
  }) async {
    _pendingCapturePath = imagePath;
    _pendingCaptureLook = look;
    _showCameraSnack(
      'camera.processing_photo'.tr(),
      duration: const Duration(minutes: 2),
    );

    try {
      final sourceBytes = await File(imagePath).readAsBytes();
      await _capturePipeline.processAndSave(
        sourceJpeg: sourceBytes,
        look: look,
        onPhase: (phase) {
          if (phase == ProcessingJobPhase.saving) {
            _showCameraSnack(
              'camera.saving_photo'.tr(),
              duration: const Duration(minutes: 2),
            );
          }
        },
      );
      await _deleteCaptureBestEffort(imagePath);
      if (_pendingCapturePath == imagePath) {
        _pendingCapturePath = null;
        _pendingCaptureLook = null;
      }
      _showCameraSnack('camera.capture_saved'.tr());
    } catch (_) {
      _showCameraSnack(
        'camera.capture_failed'.tr(),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: 'camera.try_again'.tr(),
          onPressed: () => unawaited(_retryPendingCapture()),
        ),
      );
    }
  }

  Future<void> _retryPendingCapture() async {
    if (_isCapturing) return;
    final path = _pendingCapturePath;
    final look = _pendingCaptureLook;
    if (path == null || look == null) return;
    setState(() => _isCapturing = true);
    try {
      await _processAndSaveCapture(path, look: look);
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  Future<void> _discardPendingCapture() async {
    final path = _pendingCapturePath;
    _pendingCapturePath = null;
    _pendingCaptureLook = null;
    if (path != null) await _deleteCaptureBestEffort(path);
  }

  Future<void> _deleteCaptureBestEffort(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Temporary capture cleanup must not replace the user-visible save result.
    }
  }

'''
s = replace_once(s, old_save, new_save, "inline save")
overlay = '''            if (_isCapturing)
              const Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(color: Color(0x22000000)),
                ),
              ),
'''
s = replace_once(s, overlay, "", "capture overlay")
screen.write_text(s)

services = Path("lib/app/platform_media_services.dart")
p = services.read_text()
p = replace_once(p, "import 'dart:typed_data';\n", "import 'dart:io';\nimport 'dart:typed_data';\n", "services io")
p = replace_once(
    p,
    "import 'package:flutter_riverpod/flutter_riverpod.dart';\n",
    "import 'package:device_info_plus/device_info_plus.dart';\n"
    "import 'package:flutter/foundation.dart';\n"
    "import 'package:flutter_riverpod/flutter_riverpod.dart';\n",
    "services imports",
)
p = replace_once(
    p,
    "import 'package:image_picker/image_picker.dart';\n",
    "import 'package:image_picker/image_picker.dart';\n"
    "import 'package:permission_handler/permission_handler.dart' as permissions;\n",
    "permission import",
)
provider_marker = "final mediaPickerServiceProvider = Provider<MediaPickerService>(\n"
implementation = '''class PlatformPermissionService implements PermissionService {
  const PlatformPermissionService();

  @override
  Future<PermissionDecision> requestCamera() =>
      _request(permissions.Permission.camera);

  @override
  Future<PermissionDecision> requestGalleryRead() async {
    if (kIsWeb) return PermissionDecision.denied;
    if (Platform.isIOS) return _request(permissions.Permission.photos);
    if (Platform.isAndroid) return PermissionDecision.granted;
    return PermissionDecision.denied;
  }

  @override
  Future<PermissionDecision> requestGalleryWrite() async {
    if (kIsWeb) return PermissionDecision.denied;
    if (Platform.isIOS) {
      return _request(permissions.Permission.photosAddOnly);
    }
    if (Platform.isAndroid) {
      final sdkInt = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
      if (sdkInt >= 29) return PermissionDecision.granted;
      return _request(permissions.Permission.storage);
    }
    return PermissionDecision.denied;
  }

  Future<PermissionDecision> _request(permissions.Permission permission) async {
    final status = await permission.request();
    if (status.isGranted || status.isLimited) {
      return PermissionDecision.granted;
    }
    if (status.isRestricted || status.isPermanentlyDenied) {
      return PermissionDecision.restricted;
    }
    return PermissionDecision.denied;
  }
}

'''
p = replace_once(p, provider_marker, implementation + provider_marker, "permission service")
p += "\nfinal permissionServiceProvider = Provider<PermissionService>(\n  (ref) => const PlatformPermissionService(),\n);\n"
services.write_text(p)

pubspec = Path("pubspec.yaml")
t = pubspec.read_text()
t = replace_once(
    t,
    "  image_picker: ^1.1.2\n",
    "  image_picker: ^1.1.2\n  permission_handler: ^12.0.3\n  device_info_plus: ^12.4.0\n",
    "pubspec dependencies",
)
pubspec.write_text(t)

podfile = Path("ios/Podfile")
q = podfile.read_text()
q = replace_once(
    q,
    "  installer.pods_project.targets.each do |target|\n"
    "    flutter_additional_ios_build_settings(target)\n"
    "  end\n",
    "  installer.pods_project.targets.each do |target|\n"
    "    flutter_additional_ios_build_settings(target)\n"
    "    target.build_configurations.each do |config|\n"
    "      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= ['$(inherited)']\n"
    "      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] += [\n"
    "        'PERMISSION_CAMERA=1',\n"
    "        'PERMISSION_PHOTOS=1',\n"
    "        'PERMISSION_PHOTOS_ADD_ONLY=1',\n"
    "      ]\n"
    "    end\n"
    "  end\n",
    "permission macros",
)
podfile.write_text(q)

for path, old, new in [
    (
        "assets/translations/en.json",
        '    "capture_failed": "Could not process or save this photo.",\n',
        '    "capture_failed": "Could not process or save this photo.",\n'
        '    "gallery_permission_pending": "Preparing Gallery access…",\n'
        '    "gallery_permission_required": "Allow photo-library access in Settings before taking a photo.",\n',
    ),
    (
        "assets/translations/th.json",
        '    "capture_failed": "ไม่สามารถประมวลผลหรือบันทึกรูปนี้ได้",\n',
        '    "capture_failed": "ไม่สามารถประมวลผลหรือบันทึกรูปนี้ได้",\n'
        '    "gallery_permission_pending": "กำลังเตรียมสิทธิ์สำหรับแกลเลอรี…",\n'
        '    "gallery_permission_required": "กรุณาอนุญาตสิทธิ์คลังรูปภาพใน Settings ก่อนถ่ายรูป",\n',
    ),
]:
    f = Path(path)
    x = f.read_text()
    f.write_text(replace_once(x, old, new, path))

handoff = Path("lib/camera/camera_capture_save_handoff.dart")
if handoff.exists():
    handoff.unlink()
