// Phase 11 (autoport): :app module Gradle config.
//
// This is the Android Gradle Plugin build file for the OpenGOAL Android
// shell. The actual game logic and runtime live in libgk.so, produced
// by the NDK build under build-android/ (see phase 10). Here we just
// repackage that .so plus a thin Java Activity into a debug APK.

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
        versionName = "0.1-autoport-phase11"

        ndk {
            // Only ship arm64-v8a for now. Phase 10 only built libgk.so
            // for this ABI; adding others would require multi-arch NDK
            // builds, which is out of scope for phase 11.
            abiFilters += listOf("arm64-v8a")
        }
    }

    // The native library is built externally (top-level CMake invoked
    // through scripts/build-android-ndk.sh in phase 10), so we don't
    // declare an externalNativeBuild here. Instead we copy the produced
    // .so into src/main/jniLibs/<abi>/ before packaging — see the
    // copyNativeLibs task below.
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
        // Keep debug symbols in the .so for now; stripping is a release concern.
        jniLibs {
            useLegacyPackaging = false
        }
    }
}

dependencies {
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("androidx.core:core:1.13.1")
}

// Copy the phase-10 NDK output into jniLibs/ before the APK gets packaged.
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
