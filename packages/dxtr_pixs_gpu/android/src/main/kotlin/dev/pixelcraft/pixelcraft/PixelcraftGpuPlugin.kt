package dev.pixelcraft.pixelcraft

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.view.OrientationEventListener
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

/**
 * Native registration boundary for PixelCraft's preview-only Android GPU path.
 *
 * Camera frames stay in Camera2/OpenGL native memory. Dart receives only
 * control/state messages, bounded on-demand preview snapshots, and clean
 * capture paths.
 */
class PixelcraftGpuPlugin : FlutterPlugin,
    ActivityAware,
    PluginRegistry.RequestPermissionsResultListener {
    companion object {
        private const val CAMERA_PERMISSION_REQUEST = 2401
        private const val ORIENTATION_CHANNEL = "dev.pixelcraft/camera_orientation_v1"
        private const val PREVIEW_SNAPSHOT_CHANNEL = "dev.pixelcraft/gpu_preview_snapshot_v1"
    }

    private var activityBinding: ActivityPluginBinding? = null
    private var pendingCameraPermission: ((Boolean) -> Unit)? = null
    private var channel: GpuPreviewChannel? = null
    private var sessions: GpuPreviewRendererSessionRegistry? = null
    private var orientationChannel: MethodChannel? = null
    private var previewSnapshotChannel: MethodChannel? = null
    private var orientationListener: OrientationEventListener? = null
    @Volatile private var physicalOrientation: String = "portrait"

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val appContext = binding.applicationContext
        val registry = GpuPreviewRendererSessionRegistry(appContext)
        sessions = registry
        channel = GpuPreviewChannel(
            messenger = binding.binaryMessenger,
            context = appContext,
            sessions = registry,
            requestCameraPermission = ::requestCameraPermission,
        )
        binding.platformViewRegistry.registerViewFactory(
            GPU_CAMERA_PREVIEW_VIEW_TYPE,
            GpuCameraPreviewViewFactory(registry),
        )
        registerOrientationChannel(binding, appContext)
        registerPreviewSnapshotChannel(binding)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        pendingCameraPermission?.invoke(false)
        pendingCameraPermission = null
        orientationListener?.disable()
        orientationListener = null
        orientationChannel?.setMethodCallHandler(null)
        orientationChannel = null
        previewSnapshotChannel?.setMethodCallHandler(null)
        previewSnapshotChannel = null
        channel?.dispose()
        channel = null
        sessions = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        detachActivity()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        detachActivity()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != CAMERA_PERMISSION_REQUEST) return false
        val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
        pendingCameraPermission?.invoke(granted)
        pendingCameraPermission = null
        return true
    }

    private fun registerPreviewSnapshotChannel(binding: FlutterPlugin.FlutterPluginBinding) {
        previewSnapshotChannel = MethodChannel(
            binding.binaryMessenger,
            PREVIEW_SNAPSHOT_CHANNEL,
        ).also { snapshotChannel ->
            snapshotChannel.setMethodCallHandler { call, result ->
                if (call.method != "snapshot") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val maxEdge = (call.argument<Number>("maxEdge")?.toInt() ?: 180)
                    .coerceIn(96, 512)
                val qualityValue = call.argument<Number>("jpegQuality")?.toDouble() ?: 0.72
                val jpegQuality = (qualityValue.coerceIn(0.4, 0.95) * 100.0).toInt()
                try {
                    result.success(
                        GpuCameraPreviewSnapshotSource.snapshot(
                            maxEdge = maxEdge,
                            jpegQuality = jpegQuality,
                        ),
                    )
                } catch (error: Throwable) {
                    result.error(
                        "gpu_preview_snapshot_failed",
                        error.message ?: "Android live preview snapshot failed",
                        null,
                    )
                }
            }
        }
    }

    private fun registerOrientationChannel(
        binding: FlutterPlugin.FlutterPluginBinding,
        context: Context,
    ) {
        orientationChannel = MethodChannel(binding.binaryMessenger, ORIENTATION_CHANNEL).also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method == "orientation") {
                    result.success(physicalOrientation)
                } else {
                    result.notImplemented()
                }
            }
        }
        orientationListener = object : OrientationEventListener(context.applicationContext) {
            override fun onOrientationChanged(orientation: Int) {
                if (orientation == ORIENTATION_UNKNOWN) return
                physicalOrientation = when {
                    orientation >= 315 || orientation < 45 -> "portrait"
                    orientation < 135 -> "landscapeLeft"
                    orientation < 225 -> "portraitUpsideDown"
                    else -> "landscapeRight"
                }
            }
        }.also { listener ->
            if (listener.canDetectOrientation()) listener.enable()
        }
    }

    private fun requestCameraPermission(callback: (Boolean) -> Unit) {
        val activity = activityBinding?.activity
        if (activity == null) {
            callback(false)
            return
        }
        if (
            Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
            activity.checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
        ) {
            callback(true)
            return
        }
        if (pendingCameraPermission != null) {
            callback(false)
            return
        }
        pendingCameraPermission = callback
        activity.requestPermissions(
            arrayOf(Manifest.permission.CAMERA),
            CAMERA_PERMISSION_REQUEST,
        )
    }

    private fun detachActivity() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        pendingCameraPermission?.invoke(false)
        pendingCameraPermission = null
    }
}
