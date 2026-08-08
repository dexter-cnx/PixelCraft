package dev.pixelcraft.pixelcraft

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

internal class GpuPreviewChannel(
    flutterEngine: FlutterEngine,
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
        val requestedVersion = call.argument<Int>("protocolVersion") ?: 0
        if (requestedVersion != PROTOCOL_VERSION) {
            result.error(
                "gpu_protocol_mismatch",
                "Native GPU protocol is $PROTOCOL_VERSION, requested $requestedVersion",
                null,
            )
            return
        }

        try {
            val harness = GpuLutShaderHarness.run()
            result.success(
                mapOf(
                    "passed" to harness.passed,
                    "maxChannelError" to harness.maxChannelError,
                    "samples" to harness.samples,
                    "renderer" to harness.renderer,
                    "version" to harness.version,
                ),
            )
        } catch (error: Throwable) {
            result.error(
                "gpu_harness_failed",
                error.message ?: error.javaClass.simpleName,
                null,
            )
        }
    }
}
