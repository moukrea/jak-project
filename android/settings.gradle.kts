// Phase 11 (autoport): Gradle settings for the OpenGOAL Android APK.
//
// Single-module project. The native library (libgk.so) is built by the
// top-level CMakeLists.txt with the NDK toolchain (phase 10); this
// Gradle project only wraps the .so + a thin Java activity into an APK.

pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "opengoal"
include(":app")
