package dev.pixelcraft.pixelcraft

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.ImageFormat
import android.graphics.SurfaceTexture
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.media.ImageReader
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLSurface
import android.opengl.GLES11Ext
import android.opengl.GLES20
import android.os.Handler
import android.os.HandlerThread
import android.util.Size
import android.view.Surface
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import kotlin.math.abs

/**
 * G1 Android renderer.
 *
 * Camera2 writes preview frames directly into an external OES texture. A GL
 * thread samples that texture, applies the canonical 33^3 Film LUT atlas, and
 * renders into the PlatformView Surface. Still capture goes to a separate JPEG
 * ImageReader and is saved unchanged; no preview pixels cross Dart.
 */
internal class AndroidGpuCameraOesRenderer(
    context: Context,
    private val onRuntimeFailure: (String) -> Unit = {},
) : GpuCameraOesRenderer {
    companion object {
        private const val LUT_SIZE = 33
        private const val LUT_TILES = 6
        private const val LUT_ATLAS_SIZE = LUT_SIZE * LUT_TILES
        private const val MAX_PREVIEW_AREA = 1920 * 1080

        private const val VERTEX_SHADER = """
            attribute vec2 aPosition;
            varying vec2 vTexCoord;
            void main() {
              gl_Position = vec4(aPosition, 0.0, 1.0);
              vTexCoord = aPosition * 0.5 + 0.5;
            }
        """

        private const val FRAGMENT_SHADER = """
            #extension GL_OES_EGL_image_external : require
            precision highp float;
            varying vec2 vTexCoord;
            uniform samplerExternalOES uCamera;
            uniform sampler2D uLut;
            uniform mat4 uSurfaceTextureMatrix;
            uniform vec2 uCropScale;
            uniform int uRotationSteps;
            uniform float uMirrorX;
            uniform float uUseLut;
            uniform float uStrength;

            const float LUT_SIZE_F = 33.0;
            const float TILES = 6.0;
            const float ATLAS_SIZE = 198.0;

            vec2 orientUv(vec2 uv) {
              vec2 p = (uv - vec2(0.5)) * uCropScale;
              if (uRotationSteps == 1) {
                p = vec2(p.y, -p.x);
              } else if (uRotationSteps == 2) {
                p = -p;
              } else if (uRotationSteps == 3) {
                p = vec2(-p.y, p.x);
              }
              p.x = mix(p.x, -p.x, uMirrorX);
              return p + vec2(0.5);
            }

            vec3 atlasTexel(float r, float g, float b) {
              float tileX = mod(b, TILES);
              float tileY = floor(b / TILES);
              float x = tileX * LUT_SIZE_F + r;
              float y = tileY * LUT_SIZE_F + g;
              vec2 uv = (vec2(x, y) + vec2(0.5)) / ATLAS_SIZE;
              return texture2D(uLut, uv).rgb;
            }

            vec3 sampleSlice(float b, float r, float g) {
              float r0 = floor(r);
              float g0 = floor(g);
              float r1 = min(r0 + 1.0, LUT_SIZE_F - 1.0);
              float g1 = min(g0 + 1.0, LUT_SIZE_F - 1.0);
              float rf = r - r0;
              float gf = g - g0;
              vec3 c00 = atlasTexel(r0, g0, b);
              vec3 c10 = atlasTexel(r1, g0, b);
              vec3 c01 = atlasTexel(r0, g1, b);
              vec3 c11 = atlasTexel(r1, g1, b);
              return mix(mix(c00, c10, rf), mix(c01, c11, rf), gf);
            }

            vec3 sampleLut(vec3 color) {
              vec3 scaled = clamp(color, 0.0, 1.0) * (LUT_SIZE_F - 1.0);
              float b0 = floor(scaled.b);
              float b1 = min(b0 + 1.0, LUT_SIZE_F - 1.0);
              float bf = scaled.b - b0;
              return mix(
                sampleSlice(b0, scaled.r, scaled.g),
                sampleSlice(b1, scaled.r, scaled.g),
                bf
              );
            }

            void main() {
              vec2 uv = orientUv(vTexCoord);
              uv = (uSurfaceTextureMatrix * vec4(uv, 0.0, 1.0)).xy;
              vec3 source = texture2D(uCamera, uv).rgb;
              vec3 film = sampleLut(source);
              float amount = clamp(uUseLut * uStrength, 0.0, 1.0);
              gl_FragColor = vec4(mix(source, film, amount), 1.0);
            }
        """
    }

    private val appContext = context.applicationContext
    private val cameraManager =
        appContext.getSystemService(Context.CAMERA_SERVICE) as CameraManager

    private val glThread = HandlerThread("PixelCraft-GpuCamera-GL").apply { start() }
    private val glHandler = Handler(glThread.looper)
    private val cameraThread = HandlerThread("PixelCraft-GpuCamera-Camera2").apply { start() }
    private val cameraHandler = Handler(cameraThread.looper)

    private val quad: FloatBuffer = ByteBuffer
        .allocateDirect(8 * 4)
        .order(ByteOrder.nativeOrder())
        .asFloatBuffer()
        .apply {
            put(floatArrayOf(-1f, -1f, 1f, -1f, -1f, 1f, 1f, 1f))
            position(0)
        }

    @Volatile private var released = false
    @Volatile private var paused = false
    @Volatile private var enabled = true
    @Volatile private var profileId = ""
    @Volatile private var strength = 0f
    @Volatile private var lensFacing = CameraCharacteristics.LENS_FACING_BACK

    private var outputSurface: Surface? = null
    private var outputWidth = 0
    private var outputHeight = 0
    private var displayRotation = Surface.ROTATION_0

    private var eglDisplay: EGLDisplay = EGL14.EGL_NO_DISPLAY
    private var eglContext: EGLContext = EGL14.EGL_NO_CONTEXT
    private var eglSurface: EGLSurface = EGL14.EGL_NO_SURFACE
    private var eglConfig: EGLConfig? = null
    private var program = 0
    private var oesTexture = 0
    private var lutTexture = 0
    private var inputSurfaceTexture: SurfaceTexture? = null
    private var inputSurface: Surface? = null
    private val surfaceTextureMatrix = FloatArray(16)

    private var cameraDevice: CameraDevice? = null
    private var captureSession: CameraCaptureSession? = null
    private var imageReader: ImageReader? = null
    private var previewSize: Size? = null
    private var sensorOrientation = 0
    private var pendingCapture: ((Result<String>) -> Unit)? = null

    override fun cameraInputSurfaceTexture(): SurfaceTexture =
        inputSurfaceTexture
            ?: throw IllegalStateException("Camera OES input is not initialized yet")

    fun configureOutputSurface(
        surface: Surface,
        width: Int,
        height: Int,
        rotation: Int,
    ) {
        outputSurface = surface
        outputWidth = width
        outputHeight = height
        displayRotation = rotation
        glHandler.post {
            try {
                ensureGl(surface)
                if (!paused) cameraHandler.post(::openCamera)
            } catch (error: Throwable) {
                fail("Unable to configure GPU camera surface", error)
            }
        }
    }

    override fun configureOutputSurface(surface: Surface, width: Int, height: Int) {
        configureOutputSurface(surface, width, height, displayRotation)
    }

    override fun clearOutputSurface() {
        outputSurface = null
        cameraHandler.post(::closeCamera)
        glHandler.post(::destroyWindowSurface)
    }

    override fun setFilm(profileId: String, strength: Float) {
        val changed = this.profileId != profileId
        this.profileId = profileId
        this.strength = strength.coerceIn(0f, 1f)
        if (!changed) return
        glHandler.post {
            try {
                uploadFilmLut(profileId)
            } catch (error: Throwable) {
                fail("Unable to load Film LUT: $profileId", error)
            }
        }
    }

    override fun setStrength(strength: Float) {
        this.strength = strength.coerceIn(0f, 1f)
    }

    override fun setEnabled(enabled: Boolean) {
        this.enabled = enabled
    }

    override fun pause() {
        paused = true
        cameraHandler.post(::closeCamera)
    }

    override fun resume() {
        if (released) return
        paused = false
        val surface = outputSurface ?: return
        glHandler.post {
            try {
                ensureGl(surface)
                cameraHandler.post(::openCamera)
            } catch (error: Throwable) {
                fail("Unable to resume GPU camera renderer", error)
            }
        }
    }

    fun capturePhoto(callback: (Result<String>) -> Unit) {
        cameraHandler.post {
            val device = cameraDevice
            val session = captureSession
            val reader = imageReader
            if (device == null || session == null || reader == null) {
                callback(Result.failure(IllegalStateException("Camera is not ready")))
                return@post
            }
            if (pendingCapture != null) {
                callback(Result.failure(IllegalStateException("Capture already in progress")))
                return@post
            }

            pendingCapture = callback
            try {
                val request = device.createCaptureRequest(CameraDevice.TEMPLATE_STILL_CAPTURE).apply {
                    addTarget(reader.surface)
                    set(CaptureRequest.CONTROL_MODE, CaptureRequest.CONTROL_MODE_AUTO)
                    set(
                        CaptureRequest.CONTROL_AF_MODE,
                        CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE,
                    )
                    set(CaptureRequest.JPEG_ORIENTATION, jpegOrientation())
                }.build()
                session.capture(request, object : CameraCaptureSession.CaptureCallback() {}, cameraHandler)
            } catch (error: Throwable) {
                pendingCapture = null
                callback(Result.failure(error))
            }
        }
    }

    fun switchCamera(callback: (Result<String>) -> Unit) {
        cameraHandler.post {
            val desired = if (lensFacing == CameraCharacteristics.LENS_FACING_BACK) {
                CameraCharacteristics.LENS_FACING_FRONT
            } else {
                CameraCharacteristics.LENS_FACING_BACK
            }
            if (cameraIdForLens(desired) == null) {
                callback(Result.failure(IllegalStateException("Requested camera lens is unavailable")))
                return@post
            }
            lensFacing = desired
            closeCamera()
            openCamera()
            callback(
                Result.success(
                    if (desired == CameraCharacteristics.LENS_FACING_FRONT) "front" else "back",
                ),
            )
        }
    }

    override fun release() {
        if (released) return
        released = true
        paused = true
        cameraHandler.post {
            closeCamera()
            cameraThread.quitSafely()
        }
        glHandler.post {
            releaseGl()
            glThread.quitSafely()
        }
    }

    @SuppressLint("MissingPermission")
    private fun openCamera() {
        if (released || paused || cameraDevice != null || outputSurface == null) return
        if (appContext.checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            fail("Camera permission is not granted", SecurityException("CAMERA permission missing"))
            return
        }
        val texture = inputSurfaceTexture ?: return
        val cameraId = cameraIdForLens(lensFacing) ?: run {
            fail("No camera for requested lens", IllegalStateException("Camera unavailable"))
            return
        }
        val characteristics = cameraManager.getCameraCharacteristics(cameraId)
        sensorOrientation = characteristics.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 0
        val map = characteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
            ?: throw IllegalStateException("Camera stream configuration is unavailable")
        val previews = map.getOutputSizes(SurfaceTexture::class.java).orEmpty()
        previewSize = choosePreviewSize(previews)
        val pictureSize = choosePictureSize(map.getOutputSizes(ImageFormat.JPEG).orEmpty())
        val selectedPreview = previewSize ?: throw IllegalStateException("No preview size available")
        texture.setDefaultBufferSize(selectedPreview.width, selectedPreview.height)

        imageReader?.close()
        imageReader = ImageReader.newInstance(
            pictureSize.width,
            pictureSize.height,
            ImageFormat.JPEG,
            2,
        ).apply {
            setOnImageAvailableListener({ reader ->
                val image = reader.acquireNextImage() ?: return@setOnImageAvailableListener
                try {
                    val buffer = image.planes[0].buffer
                    val bytes = ByteArray(buffer.remaining())
                    buffer.get(bytes)
                    val directory = File(appContext.cacheDir, "pixelcraft-camera").apply { mkdirs() }
                    val file = File(directory, "capture-${System.currentTimeMillis()}.jpg")
                    file.writeBytes(bytes)
                    pendingCapture?.invoke(Result.success(file.absolutePath))
                    pendingCapture = null
                } catch (error: Throwable) {
                    pendingCapture?.invoke(Result.failure(error))
                    pendingCapture = null
                } finally {
                    image.close()
                }
            }, cameraHandler)
        }

        cameraManager.openCamera(cameraId, object : CameraDevice.StateCallback() {
            override fun onOpened(camera: CameraDevice) {
                if (released || paused || outputSurface == null) {
                    camera.close()
                    return
                }
                cameraDevice = camera
                createCaptureSession(camera)
            }

            override fun onDisconnected(camera: CameraDevice) {
                camera.close()
                if (cameraDevice === camera) cameraDevice = null
            }

            override fun onError(camera: CameraDevice, error: Int) {
                camera.close()
                if (cameraDevice === camera) cameraDevice = null
                fail("Camera2 error $error", IllegalStateException("Camera2 error $error"))
            }
        }, cameraHandler)
    }

    private fun createCaptureSession(camera: CameraDevice) {
        val previewSurface = inputSurface ?: return
        val stillSurface = imageReader?.surface ?: return
        camera.createCaptureSession(
            listOf(previewSurface, stillSurface),
            object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(session: CameraCaptureSession) {
                    if (cameraDevice !== camera || released || paused) {
                        session.close()
                        return
                    }
                    captureSession = session
                    try {
                        val request = camera.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW).apply {
                            addTarget(previewSurface)
                            set(CaptureRequest.CONTROL_MODE, CaptureRequest.CONTROL_MODE_AUTO)
                            set(
                                CaptureRequest.CONTROL_AF_MODE,
                                CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE,
                            )
                        }.build()
                        session.setRepeatingRequest(request, null, cameraHandler)
                    } catch (error: Throwable) {
                        fail("Unable to start Camera2 preview", error)
                    }
                }

                override fun onConfigureFailed(session: CameraCaptureSession) {
                    fail(
                        "Unable to configure Camera2 capture session",
                        IllegalStateException("configure failed"),
                    )
                }
            },
            cameraHandler,
        )
    }

    private fun closeCamera() {
        captureSession?.close()
        captureSession = null
        cameraDevice?.close()
        cameraDevice = null
        imageReader?.close()
        imageReader = null
        pendingCapture?.invoke(Result.failure(IllegalStateException("Camera closed during capture")))
        pendingCapture = null
    }

    private fun ensureGl(surface: Surface) {
        if (eglDisplay == EGL14.EGL_NO_DISPLAY) initializeGlContext()
        if (eglSurface != EGL14.EGL_NO_SURFACE) destroyWindowSurface()
        val config = eglConfig ?: throw IllegalStateException("EGL config unavailable")
        eglSurface = EGL14.eglCreateWindowSurface(
            eglDisplay,
            config,
            surface,
            intArrayOf(EGL14.EGL_NONE),
            0,
        )
        check(eglSurface != EGL14.EGL_NO_SURFACE) { "eglCreateWindowSurface failed" }
        makeCurrent()
        GLES20.glViewport(0, 0, outputWidth, outputHeight)
    }

    private fun initializeGlContext() {
        eglDisplay = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
        check(eglDisplay != EGL14.EGL_NO_DISPLAY) { "eglGetDisplay failed" }
        check(EGL14.eglInitialize(eglDisplay, IntArray(2), 0, IntArray(2), 0)) {
            "eglInitialize failed"
        }
        val configs = arrayOfNulls<EGLConfig>(1)
        val count = IntArray(1)
        val attributes = intArrayOf(
            EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
            EGL14.EGL_SURFACE_TYPE, EGL14.EGL_WINDOW_BIT,
            EGL14.EGL_RED_SIZE, 8,
            EGL14.EGL_GREEN_SIZE, 8,
            EGL14.EGL_BLUE_SIZE, 8,
            EGL14.EGL_ALPHA_SIZE, 8,
            EGL14.EGL_NONE,
        )
        check(EGL14.eglChooseConfig(eglDisplay, attributes, 0, configs, 0, 1, count, 0)) {
            "eglChooseConfig failed"
        }
        eglConfig = configs[0] ?: throw IllegalStateException("No EGL config")
        eglContext = EGL14.eglCreateContext(
            eglDisplay,
            eglConfig,
            EGL14.EGL_NO_CONTEXT,
            intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE),
            0,
        )
        check(eglContext != EGL14.EGL_NO_CONTEXT) { "eglCreateContext failed" }

        program = linkProgram(VERTEX_SHADER, FRAGMENT_SHADER)
        oesTexture = createOesTexture()
        inputSurfaceTexture = SurfaceTexture(oesTexture).apply {
            setOnFrameAvailableListener({ renderFrame() }, glHandler)
        }
        inputSurface = Surface(inputSurfaceTexture)
        if (profileId.isNotEmpty()) uploadFilmLut(profileId)
    }

    private fun renderFrame() {
        if (released || paused || eglSurface == EGL14.EGL_NO_SURFACE) return
        val texture = inputSurfaceTexture ?: return
        try {
            makeCurrent()
            texture.updateTexImage()
            texture.getTransformMatrix(surfaceTextureMatrix)
            GLES20.glViewport(0, 0, outputWidth, outputHeight)
            GLES20.glClearColor(0f, 0f, 0f, 1f)
            GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)
            GLES20.glUseProgram(program)

            val position = GLES20.glGetAttribLocation(program, "aPosition")
            quad.position(0)
            GLES20.glEnableVertexAttribArray(position)
            GLES20.glVertexAttribPointer(position, 2, GLES20.GL_FLOAT, false, 0, quad)

            GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
            GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, oesTexture)
            GLES20.glUniform1i(GLES20.glGetUniformLocation(program, "uCamera"), 0)

            GLES20.glActiveTexture(GLES20.GL_TEXTURE1)
            GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, lutTexture)
            GLES20.glUniform1i(GLES20.glGetUniformLocation(program, "uLut"), 1)

            GLES20.glUniformMatrix4fv(
                GLES20.glGetUniformLocation(program, "uSurfaceTextureMatrix"),
                1,
                false,
                surfaceTextureMatrix,
                0,
            )
            val crop = cropScale()
            GLES20.glUniform2f(
                GLES20.glGetUniformLocation(program, "uCropScale"),
                crop.first,
                crop.second,
            )
            GLES20.glUniform1i(
                GLES20.glGetUniformLocation(program, "uRotationSteps"),
                relativeRotationDegrees() / 90,
            )
            GLES20.glUniform1f(
                GLES20.glGetUniformLocation(program, "uMirrorX"),
                if (lensFacing == CameraCharacteristics.LENS_FACING_FRONT) 1f else 0f,
            )
            GLES20.glUniform1f(
                GLES20.glGetUniformLocation(program, "uUseLut"),
                if (enabled && profileId.isNotEmpty() && lutTexture != 0) 1f else 0f,
            )
            GLES20.glUniform1f(
                GLES20.glGetUniformLocation(program, "uStrength"),
                strength.coerceIn(0f, 1f),
            )

            GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
            GLES20.glDisableVertexAttribArray(position)
            check(EGL14.eglSwapBuffers(eglDisplay, eglSurface)) { "eglSwapBuffers failed" }
        } catch (error: Throwable) {
            fail("GPU camera frame rendering failed", error)
        }
    }

    private fun uploadFilmLut(id: String) {
        if (id.isEmpty() || eglDisplay == EGL14.EGL_NO_DISPLAY) return
        makeCurrentIfPossible()
        if (eglSurface == EGL14.EGL_NO_SURFACE) return
        val bytes = appContext.assets.open("gpu_luts/$id.rgba8").use { it.readBytes() }
        check(bytes.size == LUT_ATLAS_SIZE * LUT_ATLAS_SIZE * 4) {
            "Unexpected LUT atlas size for $id: ${bytes.size}"
        }
        if (lutTexture == 0) {
            val ids = IntArray(1)
            GLES20.glGenTextures(1, ids, 0)
            lutTexture = ids[0]
        }
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, lutTexture)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_NEAREST)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_NEAREST)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
        val buffer = ByteBuffer.allocateDirect(bytes.size).apply {
            put(bytes)
            position(0)
        }
        GLES20.glTexImage2D(
            GLES20.GL_TEXTURE_2D,
            0,
            GLES20.GL_RGBA,
            LUT_ATLAS_SIZE,
            LUT_ATLAS_SIZE,
            0,
            GLES20.GL_RGBA,
            GLES20.GL_UNSIGNED_BYTE,
            buffer,
        )
    }

    private fun cropScale(): Pair<Float, Float> {
        val size = previewSize ?: return 1f to 1f
        if (outputWidth <= 0 || outputHeight <= 0) return 1f to 1f
        val rotated = relativeRotationDegrees() % 180 != 0
        val sourceWidth = if (rotated) size.height.toFloat() else size.width.toFloat()
        val sourceHeight = if (rotated) size.width.toFloat() else size.height.toFloat()
        val sourceAspect = sourceWidth / sourceHeight
        val outputAspect = outputWidth.toFloat() / outputHeight.toFloat()
        return if (sourceAspect > outputAspect) {
            (outputAspect / sourceAspect) to 1f
        } else {
            1f to (sourceAspect / outputAspect)
        }
    }

    private fun relativeRotationDegrees(): Int {
        val displayDegrees = when (displayRotation) {
            Surface.ROTATION_90 -> 90
            Surface.ROTATION_180 -> 180
            Surface.ROTATION_270 -> 270
            else -> 0
        }
        val rotation = if (lensFacing == CameraCharacteristics.LENS_FACING_FRONT) {
            (sensorOrientation + displayDegrees) % 360
        } else {
            (sensorOrientation - displayDegrees + 360) % 360
        }
        return ((rotation + 45) / 90 * 90) % 360
    }

    private fun jpegOrientation(): Int = relativeRotationDegrees()

    private fun choosePreviewSize(sizes: Array<out Size>): Size {
        require(sizes.isNotEmpty()) { "No Camera2 preview sizes" }
        val bounded = sizes.filter { it.width.toLong() * it.height <= MAX_PREVIEW_AREA }
        val candidates = if (bounded.isNotEmpty()) bounded else sizes.toList()
        val targetAspect = if (outputWidth > 0 && outputHeight > 0) {
            outputWidth.toDouble() / outputHeight.toDouble()
        } else {
            16.0 / 9.0
        }
        return candidates.minWithOrNull(
            compareBy<Size> {
                abs(it.width.toDouble() / it.height.toDouble() - targetAspect)
            }.thenByDescending { it.width.toLong() * it.height },
        ) ?: candidates.first()
    }

    private fun choosePictureSize(sizes: Array<out Size>): Size {
        require(sizes.isNotEmpty()) { "No Camera2 JPEG sizes" }
        return sizes.maxByOrNull { it.width.toLong() * it.height } ?: sizes.first()
    }

    private fun cameraIdForLens(facing: Int): String? = cameraManager.cameraIdList.firstOrNull { id ->
        cameraManager.getCameraCharacteristics(id).get(CameraCharacteristics.LENS_FACING) == facing
    }

    private fun createOesTexture(): Int {
        val ids = IntArray(1)
        GLES20.glGenTextures(1, ids, 0)
        val id = ids[0]
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, id)
        GLES20.glTexParameteri(
            GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
            GLES20.GL_TEXTURE_MIN_FILTER,
            GLES20.GL_LINEAR,
        )
        GLES20.glTexParameteri(
            GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
            GLES20.GL_TEXTURE_MAG_FILTER,
            GLES20.GL_LINEAR,
        )
        GLES20.glTexParameteri(
            GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
            GLES20.GL_TEXTURE_WRAP_S,
            GLES20.GL_CLAMP_TO_EDGE,
        )
        GLES20.glTexParameteri(
            GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
            GLES20.GL_TEXTURE_WRAP_T,
            GLES20.GL_CLAMP_TO_EDGE,
        )
        return id
    }

    private fun linkProgram(vertexSource: String, fragmentSource: String): Int {
        val vertex = compileShader(GLES20.GL_VERTEX_SHADER, vertexSource)
        val fragment = compileShader(GLES20.GL_FRAGMENT_SHADER, fragmentSource)
        val result = GLES20.glCreateProgram()
        GLES20.glAttachShader(result, vertex)
        GLES20.glAttachShader(result, fragment)
        GLES20.glLinkProgram(result)
        val status = IntArray(1)
        GLES20.glGetProgramiv(result, GLES20.GL_LINK_STATUS, status, 0)
        if (status[0] == 0) {
            val log = GLES20.glGetProgramInfoLog(result)
            GLES20.glDeleteProgram(result)
            throw IllegalStateException("GPU camera program link failed: $log")
        }
        GLES20.glDeleteShader(vertex)
        GLES20.glDeleteShader(fragment)
        return result
    }

    private fun compileShader(type: Int, source: String): Int {
        val shader = GLES20.glCreateShader(type)
        GLES20.glShaderSource(shader, source)
        GLES20.glCompileShader(shader)
        val status = IntArray(1)
        GLES20.glGetShaderiv(shader, GLES20.GL_COMPILE_STATUS, status, 0)
        if (status[0] == 0) {
            val log = GLES20.glGetShaderInfoLog(shader)
            GLES20.glDeleteShader(shader)
            throw IllegalStateException("GPU camera shader compile failed: $log")
        }
        return shader
    }

    private fun makeCurrent() {
        check(
            EGL14.eglMakeCurrent(
                eglDisplay,
                eglSurface,
                eglSurface,
                eglContext,
            ),
        ) { "eglMakeCurrent failed" }
    }

    private fun makeCurrentIfPossible() {
        if (eglSurface != EGL14.EGL_NO_SURFACE) makeCurrent()
    }

    private fun destroyWindowSurface() {
        if (eglDisplay != EGL14.EGL_NO_DISPLAY && eglSurface != EGL14.EGL_NO_SURFACE) {
            EGL14.eglMakeCurrent(
                eglDisplay,
                EGL14.EGL_NO_SURFACE,
                EGL14.EGL_NO_SURFACE,
                eglContext,
            )
            EGL14.eglDestroySurface(eglDisplay, eglSurface)
            eglSurface = EGL14.EGL_NO_SURFACE
        }
    }

    private fun releaseGl() {
        if (eglSurface != EGL14.EGL_NO_SURFACE) {
            makeCurrent()
            if (lutTexture != 0) GLES20.glDeleteTextures(1, intArrayOf(lutTexture), 0)
            if (oesTexture != 0) GLES20.glDeleteTextures(1, intArrayOf(oesTexture), 0)
            if (program != 0) GLES20.glDeleteProgram(program)
        }
        destroyWindowSurface()
        inputSurface?.release()
        inputSurface = null
        inputSurfaceTexture?.release()
        inputSurfaceTexture = null
        if (eglDisplay != EGL14.EGL_NO_DISPLAY) {
            if (eglContext != EGL14.EGL_NO_CONTEXT) EGL14.eglDestroyContext(eglDisplay, eglContext)
            EGL14.eglTerminate(eglDisplay)
        }
        eglDisplay = EGL14.EGL_NO_DISPLAY
        eglContext = EGL14.EGL_NO_CONTEXT
        eglConfig = null
        program = 0
        oesTexture = 0
        lutTexture = 0
    }

    private fun fail(message: String, error: Throwable) {
        if (released) return
        onRuntimeFailure("$message: ${error.message ?: error.javaClass.simpleName}")
    }
}
