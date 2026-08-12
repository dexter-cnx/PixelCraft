import java.util.Properties
import org.gradle.api.DefaultTask
import org.gradle.api.file.DirectoryProperty
import org.gradle.api.tasks.OutputDirectory
import org.gradle.api.tasks.TaskAction
import org.gradle.process.ExecOperations
import javax.inject.Inject

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

abstract class GenerateGpuLutAssetsTask : DefaultTask() {
    @get:OutputDirectory
    abstract val outputDirectory: DirectoryProperty

    @get:Inject
    abstract val execOperations: ExecOperations

    @TaskAction
    fun generate() {
        val repoRoot = project.rootProject.projectDir.parentFile
        val outputRoot = outputDirectory.get().asFile
        val gpuLutDir = outputRoot.resolve("gpu_luts")

        execOperations.exec {
            workingDir(repoRoot)
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
    inputs.file(repoRoot.resolve("rust/src/bin/generate_creative_luts.rs"))
    inputs.file(repoRoot.resolve("rust/src/photon_filters.rs"))
    inputs.dir(repoRoot.resolve("rust/creative_luts"))
    inputs.file(repoRoot.resolve("tool/generate_gpu_lut_atlas.py"))
    inputs.file(repoRoot.resolve("tool/generate_gpu_creative_lut_atlas.py"))
    inputs.file(repoRoot.resolve("tool/generate_gpu_native_parity_fixture.py"))
    inputs.file(repoRoot.resolve("tool/gpu_lut_parity_fixtures.json"))
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use(keystoreProperties::load)
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
        applicationId = "dev.cnxdev.pixelcraft"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    if (keystorePropertiesFile.exists()) {
        signingConfigs {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Never sign a production artifact with the debug key.
            // Local/CI release builds remain unsigned unless android/key.properties
            // supplies an explicit release keystore. Store signing secrets stay out of git.
            if (keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
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
