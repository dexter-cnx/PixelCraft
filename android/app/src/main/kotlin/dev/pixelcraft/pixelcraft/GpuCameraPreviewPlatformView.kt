package dev.pixelcraft.pixelcraft

import android.content.Context
import android.graphics.SurfaceTexture
import android.view.Surface
import android.view.TextureView
import android.view.View
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

internal const val GPU_CAMERA_PREVIEW_VIEW_TYPE =
    "dev.pixelcraft/gpu_camera_preview_v1"

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
        attach(surfaceTexture, width, height)
    }

    override fun onSurfaceTextureSizeChanged(
        surfaceTexture: SurfaceTexture,
        width: Int,
        height: Int,
    ) {
        attach(surfaceTexture, width, height)
    }

    override fun onSurfaceTextureDestroyed(surfaceTexture: SurfaceTexture): Boolean {
        sessions.clearOutputSurface(rendererId)
        outputSurface?.release()
        outputSurface = null
        return true
    }

    override fun onSurfaceTextureUpdated(surfaceTexture: SurfaceTexture) = Unit

    override fun dispose() {
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
