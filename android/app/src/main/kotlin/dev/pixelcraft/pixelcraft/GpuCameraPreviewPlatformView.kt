package dev.pixelcraft.pixelcraft

import android.content.Context
import android.view.SurfaceHolder
import android.view.SurfaceView
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
) : PlatformView, SurfaceHolder.Callback {
    private val surfaceView = SurfaceView(context).apply {
        holder.addCallback(this@GpuCameraPreviewPlatformView)
        setZOrderMediaOverlay(false)
    }

    override fun getView(): View = surfaceView

    override fun surfaceCreated(holder: SurfaceHolder) = Unit

    override fun surfaceChanged(
        holder: SurfaceHolder,
        format: Int,
        width: Int,
        height: Int,
    ) {
        if (width <= 0 || height <= 0) return
        val rotation = surfaceView.display?.rotation ?: 0
        sessions.attachOutputSurface(
            rendererId,
            holder.surface,
            width,
            height,
            rotation,
        )
    }

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        sessions.clearOutputSurface(rendererId)
    }

    override fun dispose() {
        surfaceView.holder.removeCallback(this)
        sessions.clearOutputSurface(rendererId)
    }
}
