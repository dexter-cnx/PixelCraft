package dev.pixelcraft.pixelcraft

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

internal class GpuPreviewChannel(
    flutterEngine: FlutterEngine,
    private val context: Context,
) : MethodChannel.MethodCallHandler {
    companion object {
        const val PROTOCOL_VERSION = 1
        private const val CHANNEL = "dev.pixelcraft/gpu_preview_v1"
        private const val MAX_LUT_SIZE = 33
    }

    private val channel = MethodChannel(
        flutterEngine.dartExecutor.binaryMessenger,
        CHANNEL,
    )

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "probe" -> handleProbe(result)
            "runReferenceHarness" -> handleReferenceHarness(call, result)
            "runFilmProfileHarness" -> handleFilmProfileHarness(call, result)
            else -> result.notImplemented()
        }
    }

    private fun handleProbe(result: MethodChannel.Result) {
        try {
            val harness = GpuLutShaderHarness.run()
            result.success(
                mapOf(
                    "protocolVersion" to PROTOCOL_VERSION,
                    "backend" to "androidOpenGl",
                    "available" to harness.passed,
                    "supportsLut33" to harness.passed,
                    "maxLutSize" to MAX_LUT_SIZE,
                    "renderer" to harness.renderer,
                    "version" to harness.version,
                ),
            )
        } catch (error: Throwable) {
            result.success(
                mapOf(
                    "protocolVersion" to PROTOCOL_VERSION,
                    "backend" to "fallback",
                    "available" to false,
                    "supportsLut33" to false,
                    "maxLutSize" to 0,
                    "renderer" to "",
                    "version" to "",
                    "error" to (error.message ?: error.javaClass.simpleName),
                ),
            )
        }
    }

    private fun handleReferenceHarness(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        if (!validateProtocol(call, result)) return

        try {
            result.success(GpuLutShaderHarness.run().toChannelMap())
        } catch (error: Throwable) {
            result.error(
                "gpu_harness_failed",
                error.message ?: error.javaClass.simpleName,
                null,
            )
        }
    }

    private fun handleFilmProfileHarness(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        if (!validateProtocol(call, result)) return
        val profileId = call.argument<String>("profileId").orEmpty()
        if (profileId.isBlank()) {
            result.error("gpu_invalid_profile", "profileId is required", null)
            return
        }

        try {
            result.success(
                GpuLutShaderHarness
                    .runFilmProfile(context, profileId)
                    .toChannelMap(),
            )
        } catch (error: IllegalArgumentException) {
            result.error(
                "gpu_invalid_profile",
                error.message ?: "Invalid Film Profile",
                null,
            )
        } catch (error: Throwable) {
            result.error(
                "gpu_film_harness_failed",
                error.message ?: error.javaClass.simpleName,
                null,
            )
        }
    }

    private fun validateProtocol(
        call: MethodCall,
        result: MethodChannel.Result,
    ): Boolean {
        val requestedVersion = call.argument<Int>("protocolVersion") ?: 0
        if (requestedVersion == PROTOCOL_VERSION) return true
        result.error(
            "gpu_protocol_mismatch",
            "Native GPU protocol is $PROTOCOL_VERSION, requested $requestedVersion",
            null,
        )
        return false
    }

    private fun GpuHarnessResult.toChannelMap(): Map<String, Any> = mapOf(
        "passed" to passed,
        "maxChannelError" to maxChannelError,
        "samples" to samples,
        "renderer" to renderer,
        "version" to version,
        "profileId" to profileId,
    )
}
