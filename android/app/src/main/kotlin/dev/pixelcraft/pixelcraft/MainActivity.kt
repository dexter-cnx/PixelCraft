package dev.pixelcraft.pixelcraft

import android.Manifest
import android.content.ContentUris
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import android.provider.MediaStore
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

/** App shell only. Native GPU registration lives in pixelcraft_gpu. */
class MainActivity : FlutterActivity() {
    companion object {
        private const val PERMISSION_CHANNEL = "dev.cnxdev.pixelcraft/permissions"
        private const val CAMERA_REQUEST = 4300
        private const val GALLERY_WRITE_REQUEST = 4301
        private const val GALLERY_READ_REQUEST = 4302
    }

    private var pendingCameraPermissionResult: MethodChannel.Result? = null
    private var pendingGalleryWritePermissionResult: MethodChannel.Result? = null
    private var pendingGalleryReadPermissionResult: MethodChannel.Result? = null

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
                "requestGalleryRead" -> requestGalleryReadPermission(result)
                "requestGalleryWrite" -> requestGalleryWritePermission(result)
                "loadLatestGalleryThumbnail" -> loadLatestGalleryThumbnail(result)
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

    private fun requestGalleryReadPermission(result: MethodChannel.Result) {
        val permission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Manifest.permission.READ_MEDIA_IMAGES
        } else {
            Manifest.permission.READ_EXTERNAL_STORAGE
        }
        if (ContextCompat.checkSelfPermission(this, permission) == PackageManager.PERMISSION_GRANTED) {
            result.success("granted")
            return
        }
        if (pendingGalleryReadPermissionResult != null) {
            result.success("denied")
            return
        }
        pendingGalleryReadPermissionResult = result
        ActivityCompat.requestPermissions(this, arrayOf(permission), GALLERY_READ_REQUEST)
    }

    private fun requestGalleryWritePermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
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
        if (pendingGalleryWritePermissionResult != null) {
            result.success("denied")
            return
        }
        pendingGalleryWritePermissionResult = result
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
            GALLERY_WRITE_REQUEST,
        )
    }

    private fun loadLatestGalleryThumbnail(result: MethodChannel.Result) {
        try {
            val projection = arrayOf(MediaStore.Images.Media._ID)
            contentResolver.query(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                projection,
                null,
                null,
                "${MediaStore.Images.Media.DATE_ADDED} DESC",
            )?.use { cursor ->
                if (!cursor.moveToFirst()) {
                    result.success(null)
                    return
                }
                val id = cursor.getLong(cursor.getColumnIndexOrThrow(MediaStore.Images.Media._ID))
                val uri = ContentUris.withAppendedId(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, id)
                val bitmap = contentResolver.openInputStream(uri)?.use(BitmapFactory::decodeStream)
                if (bitmap == null) {
                    result.success(null)
                    return
                }
                val scaled = Bitmap.createScaledBitmap(bitmap, 160, 160, true)
                if (scaled !== bitmap) bitmap.recycle()
                val output = ByteArrayOutputStream()
                scaled.compress(Bitmap.CompressFormat.JPEG, 82, output)
                scaled.recycle()
                result.success(output.toByteArray())
                return
            }
            result.success(null)
        } catch (_: SecurityException) {
            result.success(null)
        } catch (_: Exception) {
            result.success(null)
        }
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
                result = pendingGalleryWritePermissionResult,
                permission = Manifest.permission.WRITE_EXTERNAL_STORAGE,
                grantResults = grantResults,
                clear = { pendingGalleryWritePermissionResult = null },
            )
            GALLERY_READ_REQUEST -> {
                val permission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    Manifest.permission.READ_MEDIA_IMAGES
                } else {
                    Manifest.permission.READ_EXTERNAL_STORAGE
                }
                completePermissionRequest(
                    result = pendingGalleryReadPermissionResult,
                    permission = permission,
                    grantResults = grantResults,
                    clear = { pendingGalleryReadPermissionResult = null },
                )
            }
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
