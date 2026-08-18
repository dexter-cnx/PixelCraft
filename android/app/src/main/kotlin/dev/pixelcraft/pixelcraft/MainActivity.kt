package dev.pixelcraft.pixelcraft

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** App shell only. Native GPU registration lives in pixelcraft_gpu. */
class MainActivity : FlutterActivity() {
    companion object {
        private const val PERMISSION_CHANNEL = "dev.cnxdev.pixelcraft/permissions"
        private const val CAMERA_REQUEST = 4300
        private const val GALLERY_WRITE_REQUEST = 4301
    }

    private var pendingCameraPermissionResult: MethodChannel.Result? = null
    private var pendingGalleryPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            PERMISSION_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestCamera" -> requestPermission(
                    permission = Manifest.permission.CAMERA,
                    requestCode = CAMERA_REQUEST,
                    result = result,
                )
                "requestGalleryWrite" -> requestGalleryWritePermission(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun requestPermission(
        permission: String,
        requestCode: Int,
        result: MethodChannel.Result,
    ) {
        if (ContextCompat.checkSelfPermission(this, permission) == PackageManager.PERMISSION_GRANTED) {
            result.success("granted")
            return
        }
        if (requestCode == CAMERA_REQUEST && pendingCameraPermissionResult != null) {
            result.success("denied")
            return
        }
        pendingCameraPermissionResult = result
        ActivityCompat.requestPermissions(this, arrayOf(permission), requestCode)
    }

    private fun requestGalleryWritePermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // MediaStore scoped storage can add a new image without storage permission.
            result.success("granted")
            return
        }

        if (
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.WRITE_EXTERNAL_STORAGE,
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success("granted")
            return
        }

        if (pendingGalleryPermissionResult != null) {
            result.success("denied")
            return
        }

        pendingGalleryPermissionResult = result
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
            GALLERY_WRITE_REQUEST,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        when (requestCode) {
            CAMERA_REQUEST -> completePermissionRequest(
                result = pendingCameraPermissionResult,
                permission = Manifest.permission.CAMERA,
                grantResults = grantResults,
                clear = { pendingCameraPermissionResult = null },
            )
            GALLERY_WRITE_REQUEST -> completePermissionRequest(
                result = pendingGalleryPermissionResult,
                permission = Manifest.permission.WRITE_EXTERNAL_STORAGE,
                grantResults = grantResults,
                clear = { pendingGalleryPermissionResult = null },
            )
        }
    }

    private fun completePermissionRequest(
        result: MethodChannel.Result?,
        permission: String,
        grantResults: IntArray,
        clear: () -> Unit,
    ) {
        result ?: return
        clear()
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        if (granted) {
            result.success("granted")
            return
        }
        val canAskAgain = ActivityCompat.shouldShowRequestPermissionRationale(this, permission)
        result.success(if (canAskAgain) "denied" else "restricted")
    }
}
