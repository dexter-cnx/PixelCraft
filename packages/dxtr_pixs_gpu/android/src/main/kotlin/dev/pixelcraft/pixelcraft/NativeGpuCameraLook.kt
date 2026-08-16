package dev.pixelcraft.pixelcraft

/**
 * PF2 native camera-look contract shared by the Android channel/session/renderer.
 *
 * This object is control-plane state only. Camera pixels remain entirely native
 * and Rust remains authoritative for the saved full-resolution result.
 */
internal data class NativeGpuCameraLook(
    val filmProfileId: String = "",
    val filmStrength: Float = 0f,
    val creativeFilterId: String = "",
    val creativeFilterStrength: Float = 0f,
    val brightness: Float = 1f,
    val contrast: Float = 1f,
    val saturation: Float = 1f,
) {
    companion object {
        private val exactCreativeFilters = setOf("grayscale", "invert")
        private val lutCreativeFilters = setOf(
            "vintage",
            "oceanic",
            "lofi",
            "dramatic",
            "golden",
            "pastel_pink",
        )
        val supportedCreativeFilters = exactCreativeFilters + lutCreativeFilters

        fun fromChannel(arguments: Map<*, *>): NativeGpuCameraLook {
            val creative = arguments["creativeFilterId"] as? String ?: ""
            require(creative.isEmpty() || creative in supportedCreativeFilters) {
                "Unsupported camera creative filter: $creative"
            }
            return NativeGpuCameraLook(
                filmProfileId = arguments["filmProfileId"] as? String ?: "",
                filmStrength = number(arguments, "filmStrength", 0f).coerceIn(0f, 1f),
                creativeFilterId = creative,
                creativeFilterStrength =
                    number(arguments, "creativeFilterStrength", 0f).coerceIn(0f, 1f),
                brightness = number(arguments, "brightness", 1f).coerceIn(0f, 2f),
                contrast = number(arguments, "contrast", 1f).coerceIn(0f, 2f),
                saturation = number(arguments, "saturation", 1f).coerceIn(0f, 2f),
            )
        }

        fun creativeLutAssetId(filterId: String): String? = when (filterId) {
            "vintage" -> "creative_vintage"
            "oceanic" -> "creative_oceanic"
            "lofi" -> "creative_lofi"
            "dramatic" -> "creative_dramatic"
            "golden" -> "creative_golden"
            "pastel_pink" -> "creative_pastel_pink"
            else -> null
        }

        private fun number(arguments: Map<*, *>, key: String, fallback: Float): Float =
            (arguments[key] as? Number)?.toFloat() ?: fallback
    }

    val hasFilm: Boolean
        get() = filmProfileId.isNotEmpty() && filmStrength > 0f

    val hasCreative: Boolean
        get() = creativeFilterId.isNotEmpty() && creativeFilterStrength > 0f

    val hasAdjustments: Boolean
        get() = brightness != 1f || contrast != 1f || saturation != 1f

    val isNeutral: Boolean
        get() = !hasFilm && !hasCreative && !hasAdjustments
}
