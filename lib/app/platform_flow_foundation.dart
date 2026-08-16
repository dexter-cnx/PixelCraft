import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Source metadata that is independent from edit semantics and DAM identity.
@immutable
class MediaSourceDescriptor {
  const MediaSourceDescriptor({
    required this.uri,
    required this.provenance,
    this.mimeType,
    this.externalId,
  });

  final Uri uri;
  final MediaSourceProvenance provenance;
  final String? mimeType;
  final String? externalId;
}

enum MediaSourceProvenance {
  gallery,
  systemCamera,
  filmCamera,
  desktopOpen,
  desktopDrop,
  externalEdit,
}

enum ProcessingJobPhase { idle, processing, saving, completed, failed }

enum ProcessingFailure {
  cameraUnavailable,
  permissionDenied,
  permissionRestricted,
  decodeFailed,
  unsupportedSource,
  renderFailed,
  saveFailed,
}

@immutable
class ProcessingJobState {
  const ProcessingJobState._(this.phase, this.failure);

  const ProcessingJobState.idle() : this._(ProcessingJobPhase.idle, null);
  const ProcessingJobState.processing()
      : this._(ProcessingJobPhase.processing, null);
  const ProcessingJobState.saving() : this._(ProcessingJobPhase.saving, null);
  const ProcessingJobState.completed()
      : this._(ProcessingJobPhase.completed, null);
  const ProcessingJobState.failed(ProcessingFailure failure)
      : this._(ProcessingJobPhase.failed, failure);

  final ProcessingJobPhase phase;
  final ProcessingFailure? failure;

  bool get isBusy =>
      phase == ProcessingJobPhase.processing || phase == ProcessingJobPhase.saving;
}

class ProcessingJobController extends StateNotifier<ProcessingJobState> {
  ProcessingJobController() : super(const ProcessingJobState.idle());

  void beginProcessing() => state = const ProcessingJobState.processing();
  void beginSaving() => state = const ProcessingJobState.saving();
  void complete() => state = const ProcessingJobState.completed();
  void fail(ProcessingFailure failure) => state = ProcessingJobState.failed(failure);
  void reset() => state = const ProcessingJobState.idle();
}

final processingJobProvider =
    StateNotifierProvider<ProcessingJobController, ProcessingJobState>(
  (ref) => ProcessingJobController(),
);

abstract interface class AppPreferencesStore {
  String? getString(String key);
  bool? getBool(String key);
  Future<void> setString(String key, String value);
  Future<void> setBool(String key, bool value);
  Future<void> remove(String key);
}

/// Replaceable PF0 backend. Persistence can be introduced without changing UI APIs.
class MemoryAppPreferencesStore implements AppPreferencesStore {
  final Map<String, Object> _values = <String, Object>{};

  @override
  String? getString(String key) => _values[key] as String?;

  @override
  bool? getBool(String key) => _values[key] as bool?;

  @override
  Future<void> setString(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> setBool(String key, bool value) async {
    _values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }
}

final appPreferencesStoreProvider = Provider<AppPreferencesStore>(
  (ref) => MemoryAppPreferencesStore(),
);

abstract interface class MediaPickerService {
  Future<MediaSourceDescriptor?> pickImage();
}

abstract interface class MediaSaveService {
  Future<Uri> saveJpeg({required Uint8List bytes, String? suggestedName});
}

enum PermissionDecision { granted, denied, restricted }

abstract interface class PermissionService {
  Future<PermissionDecision> requestCamera();
  Future<PermissionDecision> requestGalleryRead();
  Future<PermissionDecision> requestGalleryWrite();
}

@immutable
class CapabilityRegistry {
  const CapabilityRegistry({
    required this.nativeCameraGpuPreview,
    required this.realtimeFilmPreview,
    required this.realtimeCreativeFilterPreview,
  });

  final bool nativeCameraGpuPreview;
  final bool realtimeFilmPreview;
  final bool realtimeCreativeFilterPreview;

  factory CapabilityRegistry.forCurrentPlatform() {
    final mobile = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    return CapabilityRegistry(
      nativeCameraGpuPreview: mobile,
      realtimeFilmPreview: mobile,
      realtimeCreativeFilterPreview: mobile,
    );
  }
}

final capabilityRegistryProvider = Provider<CapabilityRegistry>(
  (ref) => CapabilityRegistry.forCurrentPlatform(),
);

enum AppRouteIntent { camera, desktopHome, editor }

abstract interface class AppRouter {
  AppRouteIntent initialIntent();
}

class PlatformAppRouter implements AppRouter {
  const PlatformAppRouter();

  @override
  AppRouteIntent initialIntent() {
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      return AppRouteIntent.camera;
    }
    return AppRouteIntent.desktopHome;
  }
}

final appRouterProvider = Provider<AppRouter>((ref) => const PlatformAppRouter());
