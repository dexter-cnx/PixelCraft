package dev.pixelcraft.pixelcraft

import android.content.Context
import android.graphics.Bitmap
import android.graphics.SurfaceTexture
import android.view.Surface
import android.view.TextureView
import android.view.View
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.io.ByteArrayOutputStream
import java.lang.ref.WeakReference

internal const val GPU_CAMERA_PREVIEW_VIEW_TYPE =
    "dev.pixelcraft/gpu_camera_preview_v1"

internal object GpuCameraPreviewSnapshotSource {
    private var activeView: WeakReference<TextureView>? = null

    fun attach(view: TextureView) {
        activeView = WeakReference(view)
    }

    fun detach(view: TextureView) {
        if (activeView?.get() === view) activeView = null
    }

    fun snapshot(maxEdge: Int, jpegQuality: Int): ByteArray {
        val view = activeView?.get()
            ?: throw IllegalStateException("Active Android GPU camera preview is unavailable")
        if (!view.isAvailable || view.width <= 1 || view.height <= 1) {
            throw IllegalStateException("Active Android GPU camera preview has invalid bounds")
        }

        val source = view.bitmap
            ?: throw IllegalStateException("Unable to read Android GPU camera preview frame")
        try {
            val side = minOf(source.width, source.height)
            if (side <= 1) throw IllegalStateException("Android live preview snapshot has invalid dimensions")
            val x = (source.width - side) / 2
            val y = (source.height - side) / 2
            val cropped = Bitmap.createBitmap(source, x, y, side, side)
            try {
                val boundedEdge = minOf(maxOf(maxEdge, 96), 512, side)
                val thumbnail = if (boundedEdge == side) {
                    cropped
                } else {
                    Bitmap.createScaledBitmap(cropped, boundedEdge, boundedEdge, true)
                }
                try {
                    val output = ByteArrayOutputStream()
                    if (!thumbnail.compress(Bitmap.CompressFormat.JPEG, jpegQuality, output)) {
                        throw IllegalStateException("Unable to encode Android live preview snapshot")
                    }
                    return output.toByteArray()
                } finally {
                    if (thumbnail !== cropped) thumbnail.recycle()
                }
            } finally {
                cropped.recycle()
            }
        } finally {
            source.recycle()
        }
    }
}

internal class GpuCameraPreviewViewFactory(
    private val sessions: GpuPreviewRendererSessionRegistry,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val params = args as? Map<*, *>
        val rendererId = params?.get("rendererId") as? String
            ?: throw IllegalArgumentException("rendererId is required")
        return GpuCameraPreviewPlatformView(context, rendererId, sessions)
    }
}

private class GpuCameraPreviewPlatformView(
    context: Context,
    private val rendererId: String,
    private val sessions: GpuPreviewRendererSessionRegistry,
) : PlatformView, TextureView.SurfaceTextureListener {
    private val textureView = TextureView(context).apply {
        surfaceTextureListener = this@GpuCameraPreviewPlatformView
        isOpaque = true
    }
    private var outputSurface: Surface? = null

    override fun getView(): View = textureView

    override fun onSurfaceTextureAvailable(
        surfaceTexture: SurfaceTexture,
        width: Int,
        height: Int,
    ) {
        GpuCameraPreviewSnapshotSource.attach(textureView)
        attach(surfaceTexture, width, height)
    }

    override fun onSurfaceTextureSizeChanged(
        surfaceTexture: SurfaceTexture,
        width: Int,
        height: Int,
    ) {
        GpuCameraPreviewSnapshotSource.attach(textureView)
        attach(surfaceTexture, width, height)
    }

    override fun onSurfaceTextureDestroyed(surfaceTexture: SurfaceTexture): Boolean {
        GpuCameraPreviewSnapshotSource.detach(textureView)
        sessions.clearOutputSurface(rendererId)
        outputSurface?.release()
        outputSurface = null
        return true
    }

    override fun onSurfaceTextureUpdated(surfaceTexture: SurfaceTexture) = Unit

    override fun dispose() {
        GpuCameraPreviewSnapshotSource.detach(textureView)
        textureView.surfaceTextureListener = null
        sessions.clearOutputSurface(rendererId)
        outputSurface?.release()
        outputSurface = null
    }

    private fun attach(surfaceTexture: SurfaceTexture, width: Int, height: Int) {
        if (width <= 0 || height <= 0) return
        outputSurface?.release()
        val surface = Surface(surfaceTexture)
        outputSurface = surface
        val rotation = textureView.display?.rotation ?: Surface.ROTATION_0
        sessions.attachOutputSurface(
            rendererId,
            surface,
            width,
            height,
            rotation,
        )
    }
}
