package dev.pixelcraft.pixelcraft

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    companion object {
        private const val CAMERA_PERMISSION_REQUEST = 2401
    }

    private var pendingCameraPermission: ((Boolean) -> Unit)? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val sessions = GpuPreviewRendererSessionRegistry(applicationContext)
        GpuPreviewChannel(
            flutterEngine = flutterEngine,
            context = applicationContext,
            sessions = sessions,
            requestCameraPermission = ::requestCameraPermission,
        )
        flutterEngine.platformViewsController.registry.registerViewFactory(
            GPU_CAMERA_PREVIEW_VIEW_TYPE,
            GpuCameraPreviewViewFactory(sessions),
        )
    }

    private fun requestCameraPermission(callback: (Boolean) -> Unit) {
        if (
            Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
            checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
        ) {
            callback(true)
            return
        }

        if (pendingCameraPermission != null) {
            callback(false)
            return
        }
        pendingCameraPermission = callback
        requestPermissions(
            arrayOf(Manifest.permission.CAMERA),
            CAMERA_PERMISSION_REQUEST,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != CAMERA_PERMISSION_REQUEST) return
        val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
        pendingCameraPermission?.invoke(granted)
        pendingCameraPermission = null
    }
}
