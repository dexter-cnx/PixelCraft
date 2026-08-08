package dev.pixelcraft.pixelcraft

import android.graphics.SurfaceTexture
import android.view.Surface

/**
 * Native-only Camera -> external OES -> Film LUT -> output surface contract.
 *
 * G0.3 defines the ownership/lifecycle boundary only. G1 will provide the
 * OpenGL ES implementation and connect Camera directly to [SurfaceTexture].
 * No frame payload is allowed to cross MethodChannel or Flutter Rust Bridge.
 */
internal interface GpuCameraOesRenderer {
    /**
     * Native Camera producer input. Implementations create/own the external OES
     * texture and expose its [SurfaceTexture] to the Camera layer.
     */
    fun cameraInputSurfaceTexture(): SurfaceTexture

    /** Attach or recreate the renderer output after route/surface changes. */
    fun configureOutputSurface(surface: Surface, width: Int, height: Int)

    /** Detach the current output surface without destroying the renderer. */
    fun clearOutputSurface()

    /** Update Film state through uniforms/texture state only. */
    fun setFilm(profileId: String, strength: Float)

    fun setEnabled(enabled: Boolean)

    /** Stop rendering/release transient EGL surface state while app is paused. */
    fun pause()

    /** Recreate transient EGL state after pause/context loss as needed. */
    fun resume()

    /** Release OES texture, EGL objects, LUT textures and native surfaces. */
    fun release()
}
