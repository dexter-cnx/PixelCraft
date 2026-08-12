package dev.pixelcraft.pixelcraft

import android.content.Context
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLSurface
import android.opengl.GLES20
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import kotlin.math.abs
import kotlin.math.roundToInt
import org.json.JSONObject

internal data class GpuHarnessResult(
    val passed: Boolean,
    val maxChannelError: Double,
    val samples: Int,
    val renderer: String,
    val version: String,
    val profileId: String,
)

internal object GpuLutShaderHarness {
    private const val LUT_SIZE = 33
    private const val TILES_PER_ROW = 6
    private const val ATLAS_SIZE = LUT_SIZE * TILES_PER_ROW
    private const val DEFAULT_TOLERANCE = 2.0 / 255.0

    private val supportedProfileIds = setOf(
        "provia_inspired",
        "velvia_inspired",
        "astia_inspired",
        "e100_inspired",
        "ektar_inspired",
        "chrome64_inspired",
    )

    private const val VERTEX_SHADER = """
        attribute vec2 aPosition;
        void main() {
          gl_Position = vec4(aPosition, 0.0, 1.0);
        }
    """

    private const val FRAGMENT_SHADER = """
        precision highp float;
        uniform sampler2D uLut;
        uniform vec3 uColor;

        const float LUT_SIZE = 33.0;
        const float TILES = 6.0;
        const float ATLAS_SIZE = 198.0;

        vec3 atlasTexel(float r, float g, float b) {
          float tileX = mod(b, TILES);
          float tileY = floor(b / TILES);
          float x = tileX * LUT_SIZE + r;
          float y = tileY * LUT_SIZE + g;
          vec2 uv = (vec2(x, y) + vec2(0.5)) / ATLAS_SIZE;
          return texture2D(uLut, uv).rgb;
        }

        vec3 sampleSlice(float b, float r, float g) {
          float r0 = floor(r);
          float g0 = floor(g);
          float r1 = min(r0 + 1.0, LUT_SIZE - 1.0);
          float g1 = min(g0 + 1.0, LUT_SIZE - 1.0);
          float rf = r - r0;
          float gf = g - g0;
          vec3 c00 = atlasTexel(r0, g0, b);
          vec3 c10 = atlasTexel(r1, g0, b);
          vec3 c01 = atlasTexel(r0, g1, b);
          vec3 c11 = atlasTexel(r1, g1, b);
          vec3 low = mix(c00, c10, rf);
          vec3 high = mix(c01, c11, rf);
          return mix(low, high, gf);
        }

        vec3 sampleLut(vec3 color) {
          vec3 scaled = clamp(color, 0.0, 1.0) * (LUT_SIZE - 1.0);
          float b0 = floor(scaled.b);
          float b1 = min(b0 + 1.0, LUT_SIZE - 1.0);
          float bf = scaled.b - b0;
          vec3 low = sampleSlice(b0, scaled.r, scaled.g);
          vec3 high = sampleSlice(b1, scaled.r, scaled.g);
          return mix(low, high, bf);
        }

        void main() {
          gl_FragColor = vec4(sampleLut(uColor), 1.0);
        }
    """

    private val fullScreenQuad: FloatBuffer = ByteBuffer
        .allocateDirect(8 * 4)
        .order(ByteOrder.nativeOrder())
        .asFloatBuffer()
        .apply {
            put(floatArrayOf(-1f, -1f, 1f, -1f, -1f, 1f, 1f, 1f))
            position(0)
        }

    fun run(): GpuHarnessResult {
        val fixtures = listOf(
            identityFixture(0f, 0f, 0f),
            identityFixture(1f, 1f, 1f),
            identityFixture(1f, 0f, 0f),
            identityFixture(0f, 1f, 0f),
            identityFixture(0f, 0f, 1f),
            identityFixture(0.5f, 0.5f, 0.5f),
            identityFixture(0.13f, 0.47f, 0.91f),
            identityFixture(0.82f, 0.24f, 0.36f),
        )
        return runWithAtlas(
            profileId = "identity",
            atlasBytes = createIdentityAtlasBytes(),
            fixtures = fixtures,
            tolerance = DEFAULT_TOLERANCE,
        )
    }

    fun runFilmProfile(context: Context, profileId: String): GpuHarnessResult {
        require(profileId in supportedProfileIds) { "Unknown Film Profile: $profileId" }
        val atlasBytes = context.assets.open("gpu_luts/$profileId.rgba8").use { it.readBytes() }
        check(atlasBytes.size == ATLAS_SIZE * ATLAS_SIZE * 4) {
            "$profileId GPU LUT atlas has ${atlasBytes.size} bytes; expected ${ATLAS_SIZE * ATLAS_SIZE * 4}"
        }

        val paritySource = context.assets.open("gpu_luts/native_parity.json")
            .bufferedReader()
            .use { it.readText() }
        val parity = JSONObject(paritySource)
        check(parity.getInt("version") == 1) { "Unsupported native GPU parity fixture version" }
        check(parity.getInt("lutSize") == LUT_SIZE) { "Native GPU fixture LUT size mismatch" }
        val tolerance = parity.optDouble("tolerance", DEFAULT_TOLERANCE)
        val inputs = parity.getJSONArray("inputs")
        val expected = parity.getJSONObject("profiles").getJSONArray(profileId)
        check(inputs.length() == expected.length()) { "$profileId parity fixture length mismatch" }

        val fixtures = buildList {
            for (index in 0 until inputs.length()) {
                val input = inputs.getJSONArray(index)
                val output = expected.getJSONArray(index)
                add(
                    ShaderFixture(
                        input = floatArrayOf(
                            input.getDouble(0).toFloat(),
                            input.getDouble(1).toFloat(),
                            input.getDouble(2).toFloat(),
                        ),
                        expected = doubleArrayOf(
                            output.getDouble(0),
                            output.getDouble(1),
                            output.getDouble(2),
                        ),
                    ),
                )
            }
        }

        return runWithAtlas(
            profileId = profileId,
            atlasBytes = atlasBytes,
            fixtures = fixtures,
            tolerance = tolerance,
        )
    }

    private fun runWithAtlas(
        profileId: String,
        atlasBytes: ByteArray,
        fixtures: List<ShaderFixture>,
        tolerance: Double,
    ): GpuHarnessResult {
        val egl = createEgl()
        try {
            val renderer = GLES20.glGetString(GLES20.GL_RENDERER).orEmpty()
            val version = GLES20.glGetString(GLES20.GL_VERSION).orEmpty()
            val program = createProgram(VERTEX_SHADER, FRAGMENT_SHADER)
            val texture = createAtlasTexture(atlasBytes)

            val position = GLES20.glGetAttribLocation(program, "aPosition")
            val color = GLES20.glGetUniformLocation(program, "uColor")
            val lut = GLES20.glGetUniformLocation(program, "uLut")
            check(position >= 0 && color >= 0 && lut >= 0) {
                "Unable to resolve LUT shader locations"
            }

            GLES20.glUseProgram(program)
            GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
            GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, texture)
            GLES20.glUniform1i(lut, 0)
            GLES20.glEnableVertexAttribArray(position)
            GLES20.glVertexAttribPointer(position, 2, GLES20.GL_FLOAT, false, 0, fullScreenQuad)
            GLES20.glViewport(0, 0, 1, 1)

            var maxError = 0.0
            val pixel = ByteBuffer.allocateDirect(4).order(ByteOrder.nativeOrder())
            fixtures.forEach { fixture ->
                GLES20.glUniform3f(
                    color,
                    fixture.input[0],
                    fixture.input[1],
                    fixture.input[2],
                )
                GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
                GLES20.glFinish()
                pixel.position(0)
                GLES20.glReadPixels(
                    0,
                    0,
                    1,
                    1,
                    GLES20.GL_RGBA,
                    GLES20.GL_UNSIGNED_BYTE,
                    pixel,
                )
                checkGl("read $profileId fixture")
                val actual = doubleArrayOf(
                    (pixel.get(0).toInt() and 0xFF) / 255.0,
                    (pixel.get(1).toInt() and 0xFF) / 255.0,
                    (pixel.get(2).toInt() and 0xFF) / 255.0,
                )
                for (channel in 0..2) {
                    maxError = maxOf(
                        maxError,
                        abs(actual[channel] - fixture.expected[channel]),
                    )
                }
            }

            GLES20.glDisableVertexAttribArray(position)
            GLES20.glDeleteTextures(1, intArrayOf(texture), 0)
            GLES20.glDeleteProgram(program)

            return GpuHarnessResult(
                passed = maxError <= tolerance,
                maxChannelError = maxError,
                samples = fixtures.size,
                renderer = renderer,
                version = version,
                profileId = profileId,
            )
        } finally {
            destroyEgl(egl)
        }
    }

    private fun createIdentityAtlasBytes(): ByteArray {
        val bytes = ByteArray(ATLAS_SIZE * ATLAS_SIZE * 4)
        for (blue in 0 until LUT_SIZE) {
            val tileX = blue % TILES_PER_ROW
            val tileY = blue / TILES_PER_ROW
            for (green in 0 until LUT_SIZE) {
                for (red in 0 until LUT_SIZE) {
                    val x = tileX * LUT_SIZE + red
                    val y = tileY * LUT_SIZE + green
                    val offset = (y * ATLAS_SIZE + x) * 4
                    bytes[offset] = toByte(red.toDouble() / (LUT_SIZE - 1))
                    bytes[offset + 1] = toByte(green.toDouble() / (LUT_SIZE - 1))
                    bytes[offset + 2] = toByte(blue.toDouble() / (LUT_SIZE - 1))
                    bytes[offset + 3] = 0xFF.toByte()
                }
            }
        }
        return bytes
    }

    private fun createAtlasTexture(atlasBytes: ByteArray): Int {
        val bytes = ByteBuffer
            .allocateDirect(atlasBytes.size)
            .order(ByteOrder.nativeOrder())
        bytes.put(atlasBytes)
        bytes.position(0)

        val ids = IntArray(1)
        GLES20.glGenTextures(1, ids, 0)
        check(ids[0] != 0) { "Unable to create LUT texture" }
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, ids[0])
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_NEAREST)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_NEAREST)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexImage2D(
            GLES20.GL_TEXTURE_2D,
            0,
            GLES20.GL_RGBA,
            ATLAS_SIZE,
            ATLAS_SIZE,
            0,
            GLES20.GL_RGBA,
            GLES20.GL_UNSIGNED_BYTE,
            bytes,
        )
        checkGl("upload LUT atlas")
        return ids[0]
    }

    private fun createProgram(vertexSource: String, fragmentSource: String): Int {
        val vertex = compileShader(GLES20.GL_VERTEX_SHADER, vertexSource)
        val fragment = compileShader(GLES20.GL_FRAGMENT_SHADER, fragmentSource)
        val program = GLES20.glCreateProgram()
        check(program != 0) { "Unable to create OpenGL program" }
        GLES20.glAttachShader(program, vertex)
        GLES20.glAttachShader(program, fragment)
        GLES20.glLinkProgram(program)
        val status = IntArray(1)
        GLES20.glGetProgramiv(program, GLES20.GL_LINK_STATUS, status, 0)
        val log = GLES20.glGetProgramInfoLog(program)
        GLES20.glDeleteShader(vertex)
        GLES20.glDeleteShader(fragment)
        check(status[0] == GLES20.GL_TRUE) { "Unable to link LUT shader: $log" }
        return program
    }

    private fun compileShader(type: Int, source: String): Int {
        val shader = GLES20.glCreateShader(type)
        check(shader != 0) { "Unable to create OpenGL shader" }
        GLES20.glShaderSource(shader, source)
        GLES20.glCompileShader(shader)
        val status = IntArray(1)
        GLES20.glGetShaderiv(shader, GLES20.GL_COMPILE_STATUS, status, 0)
        val log = GLES20.glGetShaderInfoLog(shader)
        check(status[0] == GLES20.GL_TRUE) { "Unable to compile LUT shader: $log" }
        return shader
    }

    private fun createEgl(): EglState {
        val display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
        check(display != EGL14.EGL_NO_DISPLAY) { "Unable to get EGL display" }
        val versions = IntArray(2)
        check(EGL14.eglInitialize(display, versions, 0, versions, 1)) {
            "Unable to initialize EGL"
        }

        val configAttributes = intArrayOf(
            EGL14.EGL_RENDERABLE_TYPE,
            EGL14.EGL_OPENGL_ES2_BIT,
            EGL14.EGL_SURFACE_TYPE,
            EGL14.EGL_PBUFFER_BIT,
            EGL14.EGL_RED_SIZE,
            8,
            EGL14.EGL_GREEN_SIZE,
            8,
            EGL14.EGL_BLUE_SIZE,
            8,
            EGL14.EGL_ALPHA_SIZE,
            8,
            EGL14.EGL_NONE,
        )
        val configs = arrayOfNulls<EGLConfig>(1)
        val configCount = IntArray(1)
        check(
            EGL14.eglChooseConfig(
                display,
                configAttributes,
                0,
                configs,
                0,
                1,
                configCount,
                0,
            ) && configCount[0] > 0,
        ) { "Unable to choose EGL config" }
        val config = requireNotNull(configs[0])

        val context = EGL14.eglCreateContext(
            display,
            config,
            EGL14.EGL_NO_CONTEXT,
            intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE),
            0,
        )
        check(context != EGL14.EGL_NO_CONTEXT) { "Unable to create EGL context" }

        val surface = EGL14.eglCreatePbufferSurface(
            display,
            config,
            intArrayOf(EGL14.EGL_WIDTH, 1, EGL14.EGL_HEIGHT, 1, EGL14.EGL_NONE),
            0,
        )
        check(surface != EGL14.EGL_NO_SURFACE) { "Unable to create EGL pbuffer" }
        check(EGL14.eglMakeCurrent(display, surface, surface, context)) {
            "Unable to make EGL context current"
        }
        return EglState(display, context, surface)
    }

    private fun destroyEgl(state: EglState) {
        EGL14.eglMakeCurrent(
            state.display,
            EGL14.EGL_NO_SURFACE,
            EGL14.EGL_NO_SURFACE,
            EGL14.EGL_NO_CONTEXT,
        )
        EGL14.eglDestroySurface(state.display, state.surface)
        EGL14.eglDestroyContext(state.display, state.context)
        EGL14.eglTerminate(state.display)
    }

    private fun identityFixture(red: Float, green: Float, blue: Float): ShaderFixture =
        ShaderFixture(
            input = floatArrayOf(red, green, blue),
            expected = doubleArrayOf(red.toDouble(), green.toDouble(), blue.toDouble()),
        )

    private fun toByte(value: Double): Byte =
        (value.coerceIn(0.0, 1.0) * 255.0).roundToInt().toByte()

    private fun checkGl(operation: String) {
        val error = GLES20.glGetError()
        check(error == GLES20.GL_NO_ERROR) {
            "OpenGL error 0x${error.toString(16)} during $operation"
        }
    }

    private data class ShaderFixture(
        val input: FloatArray,
        val expected: DoubleArray,
    )

    private data class EglState(
        val display: EGLDisplay,
        val context: EGLContext,
        val surface: EGLSurface,
    )
}
