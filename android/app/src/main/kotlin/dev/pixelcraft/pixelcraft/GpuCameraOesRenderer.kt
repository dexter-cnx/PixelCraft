package dev.pixelcraft.pixelcraft

import android.graphics.SurfaceTexture
import android.view.Surface

/**
 * Native-only Camera -> external OES -> Film LUT -> output surface contract.
 *
 * G1 owns Camera2 and the external OES texture natively. No frame payload is
 * allowed to cross MethodChannel or Flutter Rust Bridge.
 */
internal interface GpuCameraOesRenderer {
    /** Native Camera producer input owned by the renderer. */
    fun cameraInputSurfaceTexture(): SurfaceTexture

    /** Attach or recreate the renderer output after route/surface changes. */
    fun configureOutputSurface(surface: Surface, width: Int, height: Int)

    /** Detach the current output surface without destroying the renderer. */
    fun clearOutputSurface()

    /** Select/upload Film state. Profile changes may update the LUT texture. */
    fun setFilm(profileId: String, strength: Float)

    /** Strength-only updates must stay uniform/state-only. */
    fun setStrength(strength: Float)

    fun setEnabled(enabled: Boolean)

    /** Stop Camera2 while the app/route is paused. */
    fun pause()

    /** Re-open Camera2 and transient EGL state as needed. */
    fun resume()

    /** Release Camera2, OES texture, EGL objects, LUT textures and surfaces. */
    fun release()
}
