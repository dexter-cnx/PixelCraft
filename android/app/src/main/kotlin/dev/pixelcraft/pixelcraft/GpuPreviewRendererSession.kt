package dev.pixelcraft.pixelcraft

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

internal data class NativeGpuRendererSession(
    val id: String,
    var state: NativeGpuSessionState = NativeGpuSessionState.CREATED,
    var surface: NativeGpuSurfaceConfig? = null,
    var profileId: String = "",
    var strength: Double = 0.0,
    var viewport: NativeGpuViewport? = null,
    var enabled: Boolean = true,
)

/**
 * G0.3 control-plane session registry.
 *
 * This deliberately owns no Camera frame buffers. G1 can replace the stored
 * surface metadata with a concrete [GpuCameraOesRenderer] while preserving the
 * same MethodChannel lifecycle semantics.
 */
internal class GpuPreviewRendererSessionRegistry {
    private val sessions = mutableMapOf<String, NativeGpuRendererSession>()

    @Synchronized
    fun create(): NativeGpuRendererSession {
        val session = NativeGpuRendererSession(id = UUID.randomUUID().toString())
        sessions[session.id] = session
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
    fun setFilm(id: String, profileId: String, strength: Double) {
        require(profileId.isNotBlank()) { "profileId is required" }
        session(id).apply {
            this.profileId = profileId
            this.strength = strength.coerceIn(0.0, 1.0)
        }
    }

    @Synchronized
    fun setStrength(id: String, strength: Double) {
        session(id).strength = strength.coerceIn(0.0, 1.0)
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
        session(id).enabled = enabled
    }

    @Synchronized
    fun pause(id: String) {
        session(id).state = NativeGpuSessionState.PAUSED
    }

    @Synchronized
    fun resume(id: String) {
        val target = session(id)
        target.state = if (target.surface != null) {
            NativeGpuSessionState.SURFACE_CONFIGURED
        } else {
            NativeGpuSessionState.CREATED
        }
    }

    @Synchronized
    fun destroy(id: String) {
        sessions.remove(id)?.state = NativeGpuSessionState.DESTROYED
    }

    @Synchronized
    private fun session(id: String): NativeGpuRendererSession =
        sessions[id] ?: throw IllegalStateException("Unknown GPU renderer session: $id")
}
