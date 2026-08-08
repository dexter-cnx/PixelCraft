package dev.pixelcraft.pixelcraft

import android.content.Context
import android.os.Build

internal data class GpuCapabilityResult(
    val available: Boolean,
    val supportsLut33: Boolean,
    val selfTestPassed: Boolean,
    val assetsLoaded: Boolean,
    val blacklisted: Boolean,
    val renderer: String,
    val version: String,
    val cached: Boolean,
    val failureCode: String? = null,
    val failureDetail: String? = null,
) {
    fun toChannelMap(protocolVersion: Int, maxLutSize: Int): Map<String, Any?> = mapOf(
        "protocolVersion" to protocolVersion,
        "backend" to if (available) "androidOpenGl" else "fallback",
        "available" to available,
        "supportsLut33" to supportsLut33,
        "maxLutSize" to if (supportsLut33) maxLutSize else 0,
        "renderer" to renderer,
        "version" to version,
        "selfTestPassed" to selfTestPassed,
        "assetsLoaded" to assetsLoaded,
        "blacklisted" to blacklisted,
        "cached" to cached,
        "failureCode" to failureCode,
        "failureDetail" to failureDetail,
    )
}

/**
 * Production capability probe for G0.3.
 *
 * The expensive EGL/shader self-test is expected to be called from a
 * background executor. Results are cached per app version + device build so
 * normal Camera startup does not recreate an EGL context repeatedly.
 */
internal class GpuCapabilityProbe(private val context: Context) {
    companion object {
        private const val PREFS = "gpu_preview_capability_v1"
        private const val CACHE_KEY = "result"
        private const val CACHE_SCHEMA = 1

        private val requiredAssets = listOf(
            "gpu_luts/manifest.json",
            "gpu_luts/native_parity.json",
            "gpu_luts/provia_inspired.rgba8",
            "gpu_luts/velvia_inspired.rgba8",
            "gpu_luts/astia_inspired.rgba8",
            "gpu_luts/e100_inspired.rgba8",
            "gpu_luts/ektar_inspired.rgba8",
            "gpu_luts/chrome64_inspired.rgba8",
        )
    }

    private val preferences = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun probe(forceSelfTest: Boolean): GpuCapabilityResult {
        if (!forceSelfTest) {
            readCached()?.let { return it.copy(cached = true) }
        }

        val deviceBlacklistReason = GpuPreviewBlacklist.deviceReason()
        if (deviceBlacklistReason != null) {
            return GpuCapabilityResult(
                available = false,
                supportsLut33 = false,
                selfTestPassed = false,
                assetsLoaded = hasRequiredAssets(),
                blacklisted = true,
                renderer = "",
                version = "",
                cached = false,
                failureCode = "blacklisted",
                failureDetail = deviceBlacklistReason,
            ).also(::writeCached)
        }

        val assetsLoaded = hasRequiredAssets()
        if (!assetsLoaded) {
            return GpuCapabilityResult(
                available = false,
                supportsLut33 = false,
                selfTestPassed = false,
                assetsLoaded = false,
                blacklisted = false,
                renderer = "",
                version = "",
                cached = false,
                failureCode = "assets_unavailable",
                failureDetail = "One or more generated GPU LUT assets are missing",
            ).also(::writeCached)
        }

        return try {
            val harness = GpuLutShaderHarness.run()
            val rendererBlacklistReason = GpuPreviewBlacklist.rendererReason(harness.renderer)
            val blacklisted = rendererBlacklistReason != null
            val passed = harness.passed && !blacklisted
            GpuCapabilityResult(
                available = true,
                supportsLut33 = passed,
                selfTestPassed = harness.passed,
                assetsLoaded = true,
                blacklisted = blacklisted,
                renderer = harness.renderer,
                version = harness.version,
                cached = false,
                failureCode = when {
                    blacklisted -> "blacklisted"
                    !harness.passed -> "shader_self_test_failed"
                    else -> null
                },
                failureDetail = rendererBlacklistReason,
            ).also(::writeCached)
        } catch (error: Throwable) {
            GpuCapabilityResult(
                available = false,
                supportsLut33 = false,
                selfTestPassed = false,
                assetsLoaded = true,
                blacklisted = false,
                renderer = "",
                version = "",
                cached = false,
                failureCode = "backend_unavailable",
                failureDetail = error.message ?: error.javaClass.simpleName,
            ).also(::writeCached)
        }
    }

    fun invalidate() {
        preferences.edit().clear().apply()
    }

    private fun hasRequiredAssets(): Boolean = requiredAssets.all { path ->
        try {
            context.assets.open(path).use { stream -> stream.read() >= 0 }
        } catch (_: Throwable) {
            false
        }
    }

    @Suppress("DEPRECATION")
    private fun cacheIdentity(): String {
        val packageInfo = context.packageManager.getPackageInfo(context.packageName, 0)
        return listOf(
            CACHE_SCHEMA.toString(),
            packageInfo.versionName.orEmpty(),
            packageInfo.versionCode.toString(),
            Build.FINGERPRINT,
            Build.VERSION.SDK_INT.toString(),
        ).joinToString("|")
    }

    private fun readCached(): GpuCapabilityResult? {
        if (preferences.getString("identity", null) != cacheIdentity()) return null
        if (!preferences.contains(CACHE_KEY)) return null

        return GpuCapabilityResult(
            available = preferences.getBoolean("available", false),
            supportsLut33 = preferences.getBoolean("supportsLut33", false),
            selfTestPassed = preferences.getBoolean("selfTestPassed", false),
            assetsLoaded = preferences.getBoolean("assetsLoaded", false),
            blacklisted = preferences.getBoolean("blacklisted", false),
            renderer = preferences.getString("renderer", "").orEmpty(),
            version = preferences.getString("version", "").orEmpty(),
            cached = true,
            failureCode = preferences.getString("failureCode", null),
            failureDetail = preferences.getString("failureDetail", null),
        )
    }

    private fun writeCached(result: GpuCapabilityResult) {
        preferences.edit()
            .putString("identity", cacheIdentity())
            .putBoolean(CACHE_KEY, true)
            .putBoolean("available", result.available)
            .putBoolean("supportsLut33", result.supportsLut33)
            .putBoolean("selfTestPassed", result.selfTestPassed)
            .putBoolean("assetsLoaded", result.assetsLoaded)
            .putBoolean("blacklisted", result.blacklisted)
            .putString("renderer", result.renderer)
            .putString("version", result.version)
            .putString("failureCode", result.failureCode)
            .putString("failureDetail", result.failureDetail)
            .apply()
    }
}

/**
 * Central extension point for explicit device/GPU exclusions.
 *
 * Keep entries narrow and evidence-based. An empty list means no device is
 * blacklisted yet, while preserving a production failure mode distinct from
 * generic capability failure.
 */
internal object GpuPreviewBlacklist {
    private val blockedDeviceKeys = setOf<String>()
    private val blockedRendererSubstrings = setOf<String>()

    fun deviceReason(): String? {
        val key = "${Build.MANUFACTURER}/${Build.MODEL}".lowercase()
        return if (key in blockedDeviceKeys) "Device explicitly blacklisted: $key" else null
    }

    fun rendererReason(renderer: String): String? {
        val normalized = renderer.lowercase()
        val match = blockedRendererSubstrings.firstOrNull { it in normalized }
        return match?.let { "GPU renderer explicitly blacklisted: $renderer ($it)" }
    }
}
