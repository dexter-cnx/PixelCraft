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
        private const val GALLERY_WRITE_REQUEST = 4301
    }

    private var pendingGalleryPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            PERMISSION_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestGalleryWrite" -> requestGalleryWritePermission(result)
                else -> result.notImplemented()
            }
        }
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
        if (requestCode != GALLERY_WRITE_REQUEST) return

        val result = pendingGalleryPermissionResult ?: return
        pendingGalleryPermissionResult = null
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        if (granted) {
            result.success("granted")
            return
        }

        val canAskAgain = ActivityCompat.shouldShowRequestPermissionRationale(
            this,
            Manifest.permission.WRITE_EXTERNAL_STORAGE,
        )
        result.success(if (canAskAgain) "denied" else "restricted")
    }
}
