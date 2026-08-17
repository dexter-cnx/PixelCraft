package dev.pixelcraft.pixelcraft

import android.content.Context
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.view.Surface
import java.util.UUID

internal enum class NativeGpuSessionState {
    CREATED,
    SURFACE_CONFIGURED,
    PAUSED,
    DESTROYED,
}

internal data class NativeGpuSurfaceConfig(
    val kind: String,
    val width: Int,
    val height: Int,
    val devicePixelRatio: Double,
    val surfaceId: String?,
)

internal data class NativeGpuViewport(
    val width: Double,
    val height: Double,
    val devicePixelRatio: Double,
)

internal class NativeGpuRendererSession(
    val id: String,
    val renderer: AndroidGpuCameraOesRenderer,
    var state: NativeGpuSessionState = NativeGpuSessionState.CREATED,
    var surface: NativeGpuSurfaceConfig? = null,
    var profileId: String = "",
    var strength: Double = 0.0,
    var cameraLook: NativeGpuCameraLook = NativeGpuCameraLook(),
    var viewport: NativeGpuViewport? = null,
    var enabled: Boolean = true,
)

/**
 * G1 native renderer/session registry.
 *
 * Each session owns one Camera2/OES renderer. Actual output Surfaces arrive
 * directly from the Android PlatformView; no Surface or frame payload crosses
 * MethodChannel.
 */
internal class GpuPreviewRendererSessionRegistry(context: Context) {
    private val appContext = context.applicationContext
    private val cameraManager =
        appContext.getSystemService(Context.CAMERA_SERVICE) as CameraManager
    private val sessions = mutableMapOf<String, NativeGpuRendererSession>()

    @Volatile
    var runtimeFailureListener: ((rendererId: String, message: String) -> Unit)? = null

    @Synchronized
    fun create(): NativeGpuRendererSession {
        val id = UUID.randomUUID().toString()
        val renderer = AndroidGpuCameraOesRenderer(appContext) { message ->
            runtimeFailureListener?.invoke(id, message)
        }
        val session = NativeGpuRendererSession(id = id, renderer = renderer)
        sessions[id] = session
        return session
    }

    @Synchronized
    fun configureSurface(id: String, config: NativeGpuSurfaceConfig) {
        require(config.width > 0 && config.height > 0) { "Surface dimensions must be positive" }
        require(config.devicePixelRatio > 0.0) { "devicePixelRatio must be positive" }
        require(
            config.kind in setOf("cameraExternalOes", "flutterTexture", "nativeSurface"),
        ) { "Unsupported GPU surface kind: ${config.kind}" }

        session(id).apply {
            surface = config
            state = NativeGpuSessionState.SURFACE_CONFIGURED
        }
    }

    @Synchronized
    fun attachOutputSurface(
        id: String,
        surface: Surface,
        width: Int,
        height: Int,
        displayRotation: Int,
    ) {
        require(width > 0 && height > 0) { "Output surface dimensions must be positive" }
        session(id).apply {
            this.surface = NativeGpuSurfaceConfig(
                kind = "nativeSurface",
                width = width,
                height = height,
                devicePixelRatio = 1.0,
                surfaceId = null,
            )
            renderer.configureOutputSurface(surface, width, height, displayRotation)
            state = NativeGpuSessionState.SURFACE_CONFIGURED
        }
    }

    @Synchronized
    fun clearOutputSurface(id: String) {
        sessions[id]?.apply {
            renderer.clearOutputSurface()
            surface = null
            if (state != NativeGpuSessionState.DESTROYED) {
                state = NativeGpuSessionState.CREATED
            }
        }
    }

    @Synchronized
    fun setFilm(id: String, profileId: String, strength: Double) {
        require(profileId.isNotBlank()) { "profileId is required" }
        session(id).apply {
            this.profileId = profileId
            this.strength = strength.coerceIn(0.0, 1.0)
            renderer.setFilm(profileId, this.strength.toFloat())
        }
    }

    @Synchronized
    fun setStrength(id: String, strength: Double) {
        session(id).apply {
            this.strength = strength.coerceIn(0.0, 1.0)
            renderer.setStrength(this.strength.toFloat())
        }
    }

    @Synchronized
    fun setCameraLook(id: String, look: NativeGpuCameraLook) {
        session(id).apply {
            cameraLook = look
            renderer.setCameraLook(look)
        }
    }

    @Synchronized
    fun setViewport(id: String, viewport: NativeGpuViewport) {
        require(viewport.width > 0.0 && viewport.height > 0.0) {
            "Viewport dimensions must be positive"
        }
        require(viewport.devicePixelRatio > 0.0) { "devicePixelRatio must be positive" }
        session(id).viewport = viewport
    }

    @Synchronized
    fun setEnabled(id: String, enabled: Boolean) {
        session(id).apply {
            this.enabled = enabled
            renderer.setEnabled(enabled)
        }
    }

    @Synchronized
    fun cameraControlState(id: String): Map<String, Any> = session(id).renderer.cameraControlState()

    @Synchronized
    fun setFlashMode(id: String, mode: String): Map<String, Any> =
        session(id).renderer.setFlashMode(mode)

    @Synchronized
    fun setTorchEnabled(id: String, enabled: Boolean): Map<String, Any> =
        session(id).renderer.setTorchEnabled(enabled)

    @Synchronized
    fun setMirrorEnabled(id: String, enabled: Boolean): Map<String, Any> =
        session(id).renderer.setMirrorEnabled(enabled)

    @Synchronized
    fun pause(id: String) {
        session(id).apply {
            renderer.pause()
            state = NativeGpuSessionState.PAUSED
        }
    }

    @Synchronized
    fun resume(id: String) {
        val target = session(id)
        target.renderer.resume()
        target.state = if (target.surface != null) {
            NativeGpuSessionState.SURFACE_CONFIGURED
        } else {
            NativeGpuSessionState.CREATED
        }
    }

    fun capturePhoto(id: String, callback: (Result<String>) -> Unit) {
        val renderer = synchronized(this) { session(id).renderer }
        renderer.capturePhoto(callback)
    }

    fun switchCamera(id: String, callback: (Result<String>) -> Unit) {
        val renderer = synchronized(this) { session(id).renderer }
        renderer.switchCamera(callback)
    }

    fun availableLenses(): List<String> = buildList {
        if (hasLens(CameraCharacteristics.LENS_FACING_BACK)) add("back")
        if (hasLens(CameraCharacteristics.LENS_FACING_FRONT)) add("front")
    }

    @Synchronized
    fun destroy(id: String) {
        sessions.remove(id)?.apply {
            state = NativeGpuSessionState.DESTROYED
            renderer.release()
        }
    }

    @Synchronized
    private fun session(id: String): NativeGpuRendererSession =
        sessions[id] ?: throw IllegalStateException("Unknown GPU renderer session: $id")

    private fun hasLens(facing: Int): Boolean = cameraManager.cameraIdList.any { id ->
        cameraManager.getCameraCharacteristics(id).get(CameraCharacteristics.LENS_FACING) == facing
    }
}
