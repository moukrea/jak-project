// Phase 13 (autoport): :app module Gradle config with per-game product flavors.
//
// The desktop runtime is a single binary that selects a game at launch
// (`gk --game jak1`). Android mirrors that as three APK variants —
// `jak1`, `jak2`, `jak3` — built from one source tree via product
// flavors. Each variant has its own applicationId suffix and label so
// they can coexist on a device. Game-specific data overlays land in
// `src/jakN/assets/iso_data/` in phases 14-16.

plugins {
    id("com.android.application")
}

android {
    namespace = "org.opengoal.gk"
    compileSdk = 34

    defaultConfig {
        applicationId = "org.opengoal.gk"
        // min API 29 (Android 10) — matches NDK toolchain target in phase 10.
        minSdk = 29
        targetSdk = 34
        versionCode = 1
        versionName = "0.1-autoport-phase13"

        ndk {
            // Only ship arm64-v8a for now. Phase 10 only built libgk.so
            // for this ABI; adding others would require multi-arch NDK
            // builds, which is out of scope for phase 13.
            abiFilters += listOf("arm64-v8a")
        }
    }

    flavorDimensions += "game"
    productFlavors {
        // Phase Gpkg-branding (autoport 2026-06-27): app_name moved to
        // res/values/strings.xml ("Jak & Daxter") so the launcher label
        // lives in the manifest resource graph and isn't duplicated across
        // flavors (a per-flavor resValue + a strings.xml entry of the same
        // name collide as a duplicate resource). game_name stays per-flavor:
        // the Java loader reads R.string.game_name to select which game's
        // data to extract/boot. applicationId/suffix are UNCHANGED so the
        // package id stays org.opengoal.gk.jak1 (installs/saves intact).
        create("jak1") {
            dimension = "game"
            applicationIdSuffix = ".jak1"
            versionNameSuffix = "-jak1"
            resValue("string", "game_name", "jak1")
        }
        create("jak2") {
            dimension = "game"
            applicationIdSuffix = ".jak2"
            versionNameSuffix = "-jak2"
            resValue("string", "game_name", "jak2")
        }
        create("jak3") {
            dimension = "game"
            applicationIdSuffix = ".jak3"
            versionNameSuffix = "-jak3"
            resValue("string", "game_name", "jak3")
        }
    }

    sourceSets {
        getByName("main") {
            jniLibs.srcDirs("src/main/jniLibs")
        }
        // A40: `-PslimIso=true` builds the APK without the ~1.4 GB iso_data
        // payload (fr3 textures stay bundled via assets-slim/). The device
        // keeps its extracted files/iso_data/<game>/ + .extracted_v1
        // sentinel (LoaderActivity checks the sentinel before it ever asks
        // the AssetManager), so iterating on libgk.so costs a ~100 MB
        // install instead of a ~2.7 GB transient on a storage-starved
        // device. Seed the data once with adb push + run-as cp.
        if (project.findProperty("slimIso") == "true") {
            getByName("jak1") { assets.setSrcDirs(listOf("src/jak1/assets-slim")) }
        }
    }

    buildTypes {
        getByName("debug") {
            isMinifyEnabled = false
            // Default debug signing config is provided automatically by AGP.
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    packaging {
        jniLibs {
            useLegacyPackaging = false
        }
    }

    androidResources {
        // Phase 14: ISO data files (CGO, STR, VAG, DGO, etc.) are already
        // in their final binary on-disc form. Skipping compression keeps
        // mergeAssets/package out of the GC death-spiral on the ~1.4 GB
        // Jak 1 payload.
        noCompress += listOf(
            "cgo", "CGO",
            "str", "STR",
            "vag", "VAG",
            "txt", "TXT",
            "dgo", "DGO",
            "bsp", "BSP",
            "go",  "GO"
        )
    }
}

dependencies {
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("androidx.core:core:1.13.1")

    // androidx.appcompat 1.7.0 pulls in kotlin-stdlib-jdk7/jdk8:1.6.21,
    // but AGP 8.5.x ships kotlin-stdlib:1.8.22 which already contains the
    // jdk7/jdk8 extensions. Force the unified stdlib so AGP doesn't
    // report duplicate Kotlin classes.
    constraints {
        implementation("org.jetbrains.kotlin:kotlin-stdlib:1.8.22")
        implementation("org.jetbrains.kotlin:kotlin-stdlib-jdk7:1.8.22")
        implementation("org.jetbrains.kotlin:kotlin-stdlib-jdk8:1.8.22")
    }
}

// Phase 18 (autoport): native code now changes every phase (SDL3 wired
// in, GOAL boot in 19, GLES shaders in 21…). Make Gradle drive the NDK
// build itself so `./gradlew assembleJak1Debug` (what the per-phase
// validators run) always reflects the current C++/CMake state.
//
// We can't use AGP's externalNativeBuild here because the upstream
// CMakeLists at the repo root (which android/CMakeLists.txt is reached
// through) has Linux/x86 logic that only runs on the desktop path —
// AGP would try to configure that tree as if it were an Android module.
// Instead we invoke cmake/ninja directly via Exec tasks. The build is
// fully incremental: cmake reconfigures only when CMakeLists changes,
// ninja only rebuilds the object files that depend on edited sources.

val ndkBuildDir = rootProject.file("../build-android")
val ndkOutLib = rootProject.file("../build-android/lib/arm64-v8a/libgk.so")

val configureNativeLibs by tasks.registering(Exec::class) {
    val toolchain = System.getenv("ANDROID_NDK_HOME")?.let {
        "$it/build/cmake/android.toolchain.cmake"
    } ?: ""
    val repoRoot = rootProject.file("..").absolutePath
    workingDir = rootProject.file("..")
    commandLine(
        "cmake", "-S", repoRoot, "-B", ndkBuildDir.absolutePath, "-G", "Ninja",
        "-DCMAKE_TOOLCHAIN_FILE=$toolchain",
        "-DANDROID_ABI=arm64-v8a",
        "-DANDROID_PLATFORM=android-29",
        "-DGOALC_BACKEND=arm64",
        "-DCMAKE_BUILD_TYPE=RelWithDebInfo"
    )
    onlyIf {
        // Reconfigure only if the cmake cache is absent. Subsequent
        // edits to CMakeLists.txt are picked up automatically by the
        // build step's reconfiguration; rerunning cmake every time
        // forces a slow clean reconfigure we don't need.
        !File(ndkBuildDir, "CMakeCache.txt").exists()
    }
}

val buildNativeLibs by tasks.registering(Exec::class) {
    dependsOn(configureNativeLibs)
    workingDir = rootProject.file("..")
    commandLine("cmake", "--build", ndkBuildDir.absolutePath, "--target", "gk")
    // The output is the .so the next task picks up; declaring it as an
    // output lets Gradle skip the task on an up-to-date incremental run.
    outputs.file(ndkOutLib)
}

val copyNativeLibs by tasks.registering(Copy::class) {
    dependsOn(buildNativeLibs)
    onlyIf { ndkOutLib.exists() }
    from(ndkOutLib)
    into(layout.projectDirectory.dir("src/main/jniLibs/arm64-v8a"))
}

tasks.named("preBuild") {
    dependsOn(copyNativeLibs)
}
