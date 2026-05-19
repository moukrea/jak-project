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
        create("jak1") {
            dimension = "game"
            applicationIdSuffix = ".jak1"
            versionNameSuffix = "-jak1"
            resValue("string", "app_name", "OpenGOAL — Jak 1")
            resValue("string", "game_name", "jak1")
        }
        create("jak2") {
            dimension = "game"
            applicationIdSuffix = ".jak2"
            versionNameSuffix = "-jak2"
            resValue("string", "app_name", "OpenGOAL — Jak 2")
            resValue("string", "game_name", "jak2")
        }
        create("jak3") {
            dimension = "game"
            applicationIdSuffix = ".jak3"
            versionNameSuffix = "-jak3"
            resValue("string", "app_name", "OpenGOAL — Jak 3")
            resValue("string", "game_name", "jak3")
        }
    }

    sourceSets {
        getByName("main") {
            jniLibs.srcDirs("src/main/jniLibs")
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

// Copy the phase-10/12 NDK output into jniLibs/ before the APK gets packaged.
// This lets us keep the .so out of source control while still letting
// real Gradle builds succeed in a dev environment that has built the
// NDK target.
val copyNativeLibs by tasks.registering(Copy::class) {
    val ndkOut = rootProject.file("../build-android/lib/arm64-v8a/libgk.so")
    onlyIf { ndkOut.exists() }
    from(ndkOut)
    into(layout.projectDirectory.dir("src/main/jniLibs/arm64-v8a"))
}

tasks.named("preBuild") {
    dependsOn(copyNativeLibs)
}
