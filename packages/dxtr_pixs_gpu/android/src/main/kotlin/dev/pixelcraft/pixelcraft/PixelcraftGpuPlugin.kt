package dev.pixelcraft.pixelcraft

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.PluginRegistry

/**
 * Native registration boundary for PixelCraft's preview-only Android GPU path.
 *
 * Camera frames stay in Camera2/OpenGL native memory. Dart receives only
 * control/state messages and clean capture paths.
 */
class PixelcraftGpuPlugin : FlutterPlugin,
    ActivityAware,
    PluginRegistry.RequestPermissionsResultListener {
    companion object {
        private const val CAMERA_PERMISSION_REQUEST = 2401
    }

    private var activityBinding: ActivityPluginBinding? = null
    private var pendingCameraPermission: ((Boolean) -> Unit)? = null
    private var channel: GpuPreviewChannel? = null
    private var sessions: GpuPreviewRendererSessionRegistry? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val registry = GpuPreviewRendererSessionRegistry(binding.applicationContext)
        sessions = registry
        channel = GpuPreviewChannel(
            messenger = binding.binaryMessenger,
            context = binding.applicationContext,
            sessions = registry,
            requestCameraPermission = ::requestCameraPermission,
        )
        binding.platformViewRegistry.registerViewFactory(
            GPU_CAMERA_PREVIEW_VIEW_TYPE,
            GpuCameraPreviewViewFactory(registry),
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        pendingCameraPermission?.invoke(false)
        pendingCameraPermission = null
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
