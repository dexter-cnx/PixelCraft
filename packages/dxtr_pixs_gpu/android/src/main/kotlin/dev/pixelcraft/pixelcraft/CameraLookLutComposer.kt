package dev.pixelcraft.pixelcraft

import android.content.Context
import kotlin.math.floor
import kotlin.math.roundToInt

/**
 * PF2 control-rate LUT composer for the Android live camera path.
 *
 * Composition is evaluated only when CameraLook state changes. The 60 fps
 * renderer continues sampling one 33^3 LUT atlas per frame, preserving the
 * proven OES hot path. Saved pixels remain Rust-authoritative.
 *
 * Canonical order:
 *   Adjust -> Film -> Creative
 */
internal class CameraLookLutComposer(context: Context) {
    companion object {
        const val LUT_SIZE = 33
        const val TILES = 6
        const val ATLAS_SIZE = LUT_SIZE * TILES
        private const val MIDPOINT = 128f / 255f
    }

    private val appContext = context.applicationContext

    fun compose(look: NativeGpuCameraLook): ByteArray {
        val film = if (look.hasFilm) loadAtlas(look.filmProfileId) else null
        val creativeAsset = NativeGpuCameraLook.creativeLutAssetId(look.creativeFilterId)
        val creative = if (look.hasCreative && creativeAsset != null) loadAtlas(creativeAsset) else null
        val output = ByteArray(ATLAS_SIZE * ATLAS_SIZE * 4)

        for (blue in 0 until LUT_SIZE) {
            for (green in 0 until LUT_SIZE) {
                for (red in 0 until LUT_SIZE) {
                    var color = floatArrayOf(
                        red.toFloat() / (LUT_SIZE - 1),
                        green.toFloat() / (LUT_SIZE - 1),
                        blue.toFloat() / (LUT_SIZE - 1),
                    )

                    color = applyAdjustments(color, look)

                    if (film != null) {
                        color = mix(color, sampleAtlas(film, color), look.filmStrength)
                    }

                    if (look.hasCreative) {
                        color = when (look.creativeFilterId) {
                            "grayscale", "invert" -> applyExactCreative(
                                color,
                                look.creativeFilterId,
                                look.creativeFilterStrength,
                            )
                            else -> {
                                check(creative != null) {
                                    "Missing canonical creative LUT for ${look.creativeFilterId}"
                                }
                                mix(color, sampleAtlas(creative, color), look.creativeFilterStrength)
                            }
                        }
                    }

                    writeAtlasTexel(output, red, green, blue, color)
                }
            }
        }
        return output
    }

    private fun applyAdjustments(
        source: FloatArray,
        look: NativeGpuCameraLook,
    ): FloatArray {
        var r = clamp01(source[0] + (look.brightness - 1f))
        var g = clamp01(source[1] + (look.brightness - 1f))
        var b = clamp01(source[2] + (look.brightness - 1f))

        r = clamp01((r - MIDPOINT) * look.contrast + MIDPOINT)
        g = clamp01((g - MIDPOINT) * look.contrast + MIDPOINT)
        b = clamp01((b - MIDPOINT) * look.contrast + MIDPOINT)

        val luminance = r * 0.2126f + g * 0.7152f + b * 0.0722f
        r = clamp01(luminance + (r - luminance) * look.saturation)
        g = clamp01(luminance + (g - luminance) * look.saturation)
        b = clamp01(luminance + (b - luminance) * look.saturation)
        return floatArrayOf(r, g, b)
    }

    /** Mirrors the existing Metal editor parity path: rounded u8 math. */
    private fun applyExactCreative(
        source: FloatArray,
        filterId: String,
        strength: Float,
    ): FloatArray {
        val source8 = IntArray(3) { channel ->
            (clamp01(source[channel]) * 255f).roundToInt().coerceIn(0, 255)
        }
        val effected8 = when (filterId) {
            "grayscale" -> {
                val average = (source8[0] + source8[1] + source8[2]) / 3
                intArrayOf(average, average, average)
            }
            "invert" -> intArrayOf(255 - source8[0], 255 - source8[1], 255 - source8[2])
            else -> error("Unsupported exact creative filter: $filterId")
        }
        val amount = strength.coerceIn(0f, 1f)
        return FloatArray(3) { channel ->
            val blended = (
                source8[channel] +
                    (effected8[channel] - source8[channel]) * amount
                ).roundToInt().coerceIn(0, 255)
            blended / 255f
        }
    }

    private fun loadAtlas(assetId: String): ByteArray =
        appContext.assets.open("gpu_luts/$assetId.rgba8").use { stream ->
            stream.readBytes().also { bytes ->
                check(bytes.size == ATLAS_SIZE * ATLAS_SIZE * 4) {
                    "Unexpected LUT atlas size for $assetId: ${bytes.size}"
                }
            }
        }

    private fun sampleAtlas(atlas: ByteArray, color: FloatArray): FloatArray {
        val r = clamp01(color[0]) * (LUT_SIZE - 1)
        val g = clamp01(color[1]) * (LUT_SIZE - 1)
        val b = clamp01(color[2]) * (LUT_SIZE - 1)
        val r0 = floor(r).toInt()
        val g0 = floor(g).toInt()
        val b0 = floor(b).toInt()
        val r1 = (r0 + 1).coerceAtMost(LUT_SIZE - 1)
        val g1 = (g0 + 1).coerceAtMost(LUT_SIZE - 1)
        val b1 = (b0 + 1).coerceAtMost(LUT_SIZE - 1)
        val rf = r - r0
        val gf = g - g0
        val bf = b - b0

        fun slice(blue: Int): FloatArray {
            val c00 = texel(atlas, r0, g0, blue)
            val c10 = texel(atlas, r1, g0, blue)
            val c01 = texel(atlas, r0, g1, blue)
            val c11 = texel(atlas, r1, g1, blue)
            return FloatArray(3) { channel ->
                val top = c00[channel] + (c10[channel] - c00[channel]) * rf
                val bottom = c01[channel] + (c11[channel] - c01[channel]) * rf
                top + (bottom - top) * gf
            }
        }

        val low = slice(b0)
        val high = slice(b1)
        return FloatArray(3) { channel -> low[channel] + (high[channel] - low[channel]) * bf }
    }

    private fun texel(atlas: ByteArray, red: Int, green: Int, blue: Int): FloatArray {
        val tileX = blue % TILES
        val tileY = blue / TILES
        val x = tileX * LUT_SIZE + red
        val y = tileY * LUT_SIZE + green
        val offset = (y * ATLAS_SIZE + x) * 4
        return floatArrayOf(
            (atlas[offset].toInt() and 0xff) / 255f,
            (atlas[offset + 1].toInt() and 0xff) / 255f,
            (atlas[offset + 2].toInt() and 0xff) / 255f,
        )
    }

    private fun writeAtlasTexel(
        atlas: ByteArray,
        red: Int,
        green: Int,
        blue: Int,
        color: FloatArray,
    ) {
        val tileX = blue % TILES
        val tileY = blue / TILES
        val x = tileX * LUT_SIZE + red
        val y = tileY * LUT_SIZE + green
        val offset = (y * ATLAS_SIZE + x) * 4
        atlas[offset] = channelByte(color[0])
        atlas[offset + 1] = channelByte(color[1])
        atlas[offset + 2] = channelByte(color[2])
        atlas[offset + 3] = 0xff.toByte()
    }

    private fun mix(source: FloatArray, effected: FloatArray, amount: Float): FloatArray {
        val t = amount.coerceIn(0f, 1f)
        return FloatArray(3) { channel ->
            clamp01(source[channel] + (effected[channel] - source[channel]) * t)
        }
    }

    private fun channelByte(value: Float): Byte =
        (clamp01(value) * 255f).roundToInt().coerceIn(0, 255).toByte()

    private fun clamp01(value: Float): Float = value.coerceIn(0f, 1f)
}
