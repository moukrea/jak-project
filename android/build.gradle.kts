// Phase 11 (autoport): top-level Gradle build file.
//
// Plugin versions are pinned here so the :app module just references them
// without re-declaring versions. AGP 8.5.x lines up with Gradle 8.7 (set
// in gradle/wrapper/gradle-wrapper.properties).

plugins {
    id("com.android.application") version "8.5.2" apply false
}

tasks.register("clean", Delete::class) {
    delete(rootProject.layout.buildDirectory)
}
