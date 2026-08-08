package dev.pixelcraft.pixelcraft

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

internal class GpuPreviewChannel(
    flutterEngine: FlutterEngine,
    context: Context,
) : MethodChannel.MethodCallHandler {
    companion object {
        const val PROTOCOL_VERSION = 1
        private const val CHANNEL = "dev.pixelcraft/gpu_preview_v1"
        private const val MAX_LUT_SIZE = 33

        /** Serialize EGL test work away from Android's platform/UI thread. */
        private val gpuExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    }

    private val appContext = context.applicationContext
    private val capabilityProbe = GpuCapabilityProbe(appContext)
    private val sessions = GpuPreviewRendererSessionRegistry()
    private val mainHandler = Handler(Looper.getMainLooper())

    private val channel = MethodChannel(
        flutterEngine.dartExecutor.binaryMessenger,
        CHANNEL,
    )

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "probe" -> handleProbe(call, result)
            "invalidateCapabilityCache" -> handleInvalidateCapabilityCache(result)
            "runReferenceHarness" -> handleReferenceHarness(call, result)
            "runFilmProfileHarness" -> handleFilmProfileHarness(call, result)
            "createRenderer" -> handleCreateRenderer(call, result)
            "configureSurface" -> handleConfigureSurface(call, result)
            "setFilm" -> handleSetFilm(call, result)
            "setStrength" -> handleSetStrength(call, result)
            "setViewport" -> handleSetViewport(call, result)
            "setEnabled" -> handleSetEnabled(call, result)
            "pause" -> handlePause(call, result)
            "resume" -> handleResume(call, result)
            "destroyRenderer" -> handleDestroyRenderer(call, result)
            else -> result.notImplemented()
        }
    }

    private fun handleProbe(call: MethodCall, result: MethodChannel.Result) {
        val forceSelfTest = call.argument<Boolean>("forceSelfTest") ?: false
        gpuExecutor.execute {
            val probe = capabilityProbe.probe(forceSelfTest)
            mainHandler.post {
                result.success(probe.toChannelMap(PROTOCOL_VERSION, MAX_LUT_SIZE))
            }
        }
    }

    private fun handleInvalidateCapabilityCache(result: MethodChannel.Result) {
        capabilityProbe.invalidate()
        result.success(null)
    }

    private fun handleReferenceHarness(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        if (!validateProtocol(call, result)) return

        gpuExecutor.execute {
            try {
                val harness = GpuLutShaderHarness.run().toChannelMap()
                mainHandler.post { result.success(harness) }
            } catch (error: Throwable) {
                mainHandler.post {
                    result.error(
                        "gpu_harness_failed",
                        error.message ?: error.javaClass.simpleName,
                        null,
                    )
                }
            }
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

        gpuExecutor.execute {
            try {
                val harness = GpuLutShaderHarness
                    .runFilmProfile(appContext, profileId)
                    .toChannelMap()
                mainHandler.post { result.success(harness) }
            } catch (error: IllegalArgumentException) {
                mainHandler.post {
                    result.error(
                        "gpu_invalid_profile",
                        error.message ?: "Invalid Film Profile",
                        null,
                    )
                }
            } catch (error: Throwable) {
                mainHandler.post {
                    result.error(
                        "gpu_film_harness_failed",
                        error.message ?: error.javaClass.simpleName,
                        null,
                    )
                }
            }
        }
    }

    private fun handleCreateRenderer(call: MethodCall, result: MethodChannel.Result) {
        if (!validateProtocol(call, result)) return
        try {
            val session = sessions.create()
            result.success(
                mapOf(
                    "protocolVersion" to PROTOCOL_VERSION,
                    "rendererId" to session.id,
                    "state" to session.state.name.lowercase(),
                ),
            )
        } catch (error: Throwable) {
            capabilityProbe.invalidate()
            result.error(
                "gpu_renderer_init_failed",
                error.message ?: error.javaClass.simpleName,
                null,
            )
        }
    }

    private fun handleConfigureSurface(call: MethodCall, result: MethodChannel.Result) =
        handleRendererControl(call, result) { rendererId ->
            sessions.configureSurface(
                rendererId,
                NativeGpuSurfaceConfig(
                    kind = call.argument<String>("kind").orEmpty(),
                    width = number(call, "width").toInt(),
                    height = number(call, "height").toInt(),
                    devicePixelRatio = number(call, "devicePixelRatio").toDouble(),
                    surfaceId = call.argument<String>("surfaceId"),
                ),
            )
        }

    private fun handleSetFilm(call: MethodCall, result: MethodChannel.Result) =
        handleRendererControl(call, result) { rendererId ->
            sessions.setFilm(
                rendererId,
                call.argument<String>("profileId").orEmpty(),
                number(call, "strength").toDouble(),
            )
        }

    private fun handleSetStrength(call: MethodCall, result: MethodChannel.Result) =
        handleRendererControl(call, result) { rendererId ->
            sessions.setStrength(rendererId, number(call, "strength").toDouble())
        }

    private fun handleSetViewport(call: MethodCall, result: MethodChannel.Result) =
        handleRendererControl(call, result) { rendererId ->
            sessions.setViewport(
                rendererId,
                NativeGpuViewport(
                    width = number(call, "width").toDouble(),
                    height = number(call, "height").toDouble(),
                    devicePixelRatio = number(call, "devicePixelRatio").toDouble(),
                ),
            )
        }

    private fun handleSetEnabled(call: MethodCall, result: MethodChannel.Result) =
        handleRendererControl(call, result) { rendererId ->
            sessions.setEnabled(
                rendererId,
                call.argument<Boolean>("enabled") ?: false,
            )
        }

    private fun handlePause(call: MethodCall, result: MethodChannel.Result) =
        handleRendererControl(call, result, sessions::pause)

    private fun handleResume(call: MethodCall, result: MethodChannel.Result) =
        handleRendererControl(call, result, sessions::resume)

    private fun handleDestroyRenderer(call: MethodCall, result: MethodChannel.Result) =
        handleRendererControl(call, result, sessions::destroy)

    private fun handleRendererControl(
        call: MethodCall,
        result: MethodChannel.Result,
        action: (String) -> Unit,
    ) {
        if (!validateProtocol(call, result)) return
        val rendererId = call.argument<String>("rendererId").orEmpty()
        if (rendererId.isBlank()) {
            result.error("gpu_renderer_invalid", "rendererId is required", null)
            return
        }

        try {
            action(rendererId)
            result.success(null)
        } catch (error: IllegalArgumentException) {
            result.error(
                "gpu_renderer_invalid",
                error.message ?: error.javaClass.simpleName,
                null,
            )
        } catch (error: IllegalStateException) {
            result.error(
                "gpu_renderer_state",
                error.message ?: error.javaClass.simpleName,
                null,
            )
        } catch (error: Throwable) {
            result.error(
                "gpu_renderer_failed",
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

    private fun number(call: MethodCall, key: String): Number =
        call.argument<Number>(key)
            ?: throw IllegalArgumentException("$key is required")

    private fun GpuHarnessResult.toChannelMap(): Map<String, Any> = mapOf(
        "passed" to passed,
        "maxChannelError" to maxChannelError,
        "samples" to samples,
        "renderer" to renderer,
        "version" to version,
        "profileId" to profileId,
    )
}
