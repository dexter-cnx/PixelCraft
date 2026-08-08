plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val gpuLutAssetRoot = layout.buildDirectory.dir("generated/gpu_lut_assets")
val gpuLutAssetDir = gpuLutAssetRoot.map { it.dir("gpu_luts") }

val generateGpuLutAssets by tasks.registering(Exec::class) {
    group = "build"
    description = "Generate canonical Film Profile GPU LUT atlases for Android assets"

    val repoRoot = rootProject.projectDir.parentFile
    workingDir = repoRoot
    commandLine(
        "make",
        "gpu-luts",
        "GPU_LUT_DIR=${gpuLutAssetDir.get().asFile.absolutePath}",
    )

    inputs.file(repoRoot.resolve("rust/build.rs"))
    inputs.dir(repoRoot.resolve("rust/film_profiles"))
    inputs.file(repoRoot.resolve("tool/generate_gpu_lut_atlas.py"))
    inputs.file(repoRoot.resolve("tool/generate_gpu_native_parity_fixture.py"))
    inputs.file(repoRoot.resolve("tool/gpu_lut_parity_fixtures.json"))
    outputs.dir(gpuLutAssetRoot)
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
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "dev.pixelcraft.pixelcraft"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    sourceSets {
        getByName("main").assets.srcDir(gpuLutAssetRoot)
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

tasks.named("preBuild").configure {
    dependsOn(generateGpuLutAssets)
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
