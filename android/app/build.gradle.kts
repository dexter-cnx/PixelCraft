import org.gradle.api.DefaultTask
import org.gradle.api.file.DirectoryProperty
import org.gradle.api.tasks.OutputDirectory
import org.gradle.api.tasks.TaskAction

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

abstract class GenerateGpuLutAssetsTask : DefaultTask() {
    @get:OutputDirectory
    abstract val outputDirectory: DirectoryProperty

    @TaskAction
    fun generate() {
        val repoRoot = project.rootProject.projectDir.parentFile
        val outputRoot = outputDirectory.get().asFile
        val gpuLutDir = outputRoot.resolve("gpu_luts")

        project.exec {
            workingDir = repoRoot
            commandLine(
                "make",
                "gpu-luts",
                "GPU_LUT_DIR=${gpuLutDir.absolutePath}",
            )
        }
    }
}

val generateGpuLutAssets = tasks.register<GenerateGpuLutAssetsTask>("generateGpuLutAssets") {
    group = "build"
    description = "Generate canonical Film Profile GPU LUT atlases for Android assets"

    outputDirectory.convention(layout.buildDirectory.dir("generated/gpu_lut_assets"))

    val repoRoot = rootProject.projectDir.parentFile
    inputs.file(repoRoot.resolve("rust/build.rs"))
    inputs.dir(repoRoot.resolve("rust/film_profiles"))
    inputs.file(repoRoot.resolve("tool/generate_gpu_lut_atlas.py"))
    inputs.file(repoRoot.resolve("tool/generate_gpu_native_parity_fixture.py"))
    inputs.file(repoRoot.resolve("tool/gpu_lut_parity_fixtures.json"))
}

android {
    namespace = "dev.pixelcraft.pixelcraft"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://flutter.dev/to/review-gradle-config).
        applicationId = "dev.pixelcraft.pixelcraft"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

androidComponents {
    onVariants(selector().all()) { variant ->
        variant.sources.assets?.addGeneratedSourceDirectory(
            generateGpuLutAssets,
            GenerateGpuLutAssetsTask::outputDirectory,
        )
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
