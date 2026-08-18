package dev.pixelcraft.pixelcraft

import android.content.Context
import android.graphics.SurfaceTexture
import android.view.OrientationEventListener
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
    private var physicalRotation: Int? = null
    private var lastWidth = 0
    private var lastHeight = 0

    // The Flutter Activity is deliberately portrait-locked. Capture orientation
    // therefore must come from the physical sensor rather than Display.rotation.
    // Use the application context so the listener is not coupled to Flutter's
    // PlatformView context wrapper or Activity configuration orientation.
    private val orientationListener = object : OrientationEventListener(context.applicationContext) {
        override fun onOrientationChanged(orientation: Int) {
            if (orientation == ORIENTATION_UNKNOWN) return
            val nextRotation = when {
                orientation >= 315 || orientation < 45 -> Surface.ROTATION_0
                orientation < 135 -> Surface.ROTATION_270
                orientation < 225 -> Surface.ROTATION_180
                else -> Surface.ROTATION_90
            }
            if (nextRotation == physicalRotation) return
            physicalRotation = nextRotation
            val surfaceTexture = textureView.surfaceTexture ?: return
            if (!textureView.isAvailable || lastWidth <= 0 || lastHeight <= 0) return
            attach(surfaceTexture, lastWidth, lastHeight)
        }
    }

    init {
        if (orientationListener.canDetectOrientation()) {
            orientationListener.enable()
        }
    }

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
        lastWidth = 0
        lastHeight = 0
        return true
    }

    override fun onSurfaceTextureUpdated(surfaceTexture: SurfaceTexture) = Unit

    override fun dispose() {
        orientationListener.disable()
        textureView.surfaceTextureListener = null
        sessions.clearOutputSurface(rendererId)
        outputSurface?.release()
        outputSurface = null
        lastWidth = 0
        lastHeight = 0
    }

    private fun attach(surfaceTexture: SurfaceTexture, width: Int, height: Int) {
        if (width <= 0 || height <= 0) return
        lastWidth = width
        lastHeight = height
        outputSurface?.release()
        val surface = Surface(surfaceTexture)
        outputSurface = surface
        val rotation = physicalRotation
            ?: textureView.display?.rotation
            ?: Surface.ROTATION_0
        sessions.attachOutputSurface(
            rendererId,
            surface,
            width,
            height,
            rotation,
        )
    }
}
