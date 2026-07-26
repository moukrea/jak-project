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

// Phase Glauncher-collection (autoport 2026-07-02): ASSET-DRIVEN game detection.
//
// The set of games an APK contains == which per-game slim CGO packs
// (`<game>_cgo.zip`) are present under that flavor's assets-slim bundle dir at
// BUILD time. Exactly ONE game => single-game APK: boots STRAIGHT into that game
// with its own launcher name + icon (no menu). MORE THAN ONE => COLLECTION APK:
// label "Jak and Daxter: Recharged Collection" + a boot selection menu. The
// same detection runs at runtime in LoaderActivity (it enumerates the bundle
// dir), so dropping a 2nd game's pack into a flavor flips it to collection
// with no other code change.
//
// These are `val` lambdas (not top-level `fun`s) so they capture the Project
// receiver and can call file(); they must be declared before the android {}
// block that consumes appLabelFor().
// Grecharged-naming (owner 2026-07-22): per-game titles are the Recharged
// line-up ("Jak and Daxter: Recharged" is a nod to "Crash Bandicoot 3:
// Warped"). USER-FACING strings only — applicationId suffixes and save
// identifiers are untouched.
val gameTitles = mapOf(
    "jak1" to "Jak and Daxter: Recharged",
    "jak2" to "Jak II: Recharged",
    "jak3" to "Jak 3: Recharged",
    "jakx" to "Jak X",
)
val collectionTitle = "Jak and Daxter: Recharged Collection"
val titleFor: (String) -> String = { id -> gameTitles[id] ?: id }
// Grecharged-buildsys-packaging (autoport 2026-07-17): the APK is ALWAYS slim —
// it ships ONLY the port artifacts (arm64 CGO pack + port-custom pack); vanilla
// source-derived data lives OUTSIDE the APK, in <game>_assets.zip (produced by
// scripts/packaging/build_assets_archive.sh and delivered to the external asset
// root). A game is "present" in a flavor if its slim CGO pack (<game>_cgo.zip,
// assets-slim) is staged.
val detectBundledGames: (String) -> List<String> = { flavor ->
    val games = sortedSetOf<String>()
    listOf(
        Pair("src/$flavor/assets-slim/bundle", "_cgo.zip")
    ).forEach { (path, suffix) ->
        val dir = file(path)
        if (dir.isDirectory) {
            (dir.listFiles() ?: emptyArray())
                .filter { it.isFile && it.name.endsWith(suffix) }
                .forEach { games.add(it.name.removeSuffix(suffix)) }
        }
    }
    games.toList()
}
// Resolve the launcher label from the detected bundle set. A flavor with no
// bundle staged yet falls back to its own game id (a single-game flavor is a
// single game by definition); the `collection` flavor is the collection
// container by definition, so it stays the collection title even while empty.
val appLabelFor: (String, String) -> String = { flavor, fallbackGame ->
    val games = detectBundledGames(flavor)
    when {
        games.size > 1 -> collectionTitle
        games.size == 1 -> titleFor(games[0])
        flavor == "collection" -> collectionTitle
        else -> titleFor(fallbackGame)
    }
}
// resValue string values are inserted as XML text: escape the ampersand in
// "Jak & Daxter" (and any apostrophe) so aapt gets valid XML.
val resEscape: (String) -> String = { s -> s.replace("&", "&amp;").replace("'", "\\'") }

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
        // Phase Glauncher-collection (autoport 2026-07-02): the launcher label
        // (app_name) is now ASSET-DRIVEN and set per flavor via resValue() from
        // appLabelFor() — a single-game flavor gets that game's title, the
        // collection flavor gets "Jak and Daxter: Recharged Collection".
        // app_name was REMOVED from res/values/strings.xml so the per-flavor
        // resValue is the single source (they collide if both are present —
        // that is why Gpkg-branding had kept it only in strings.xml). game_name
        // stays per-flavor: the Java loader/MainActivity read R.string.game_name
        // as the single-game fallback. applicationId suffixes are UNCHANGED so
        // org.opengoal.gk.jak1 (installs/saves) stays intact.
        create("jak1") {
            dimension = "game"
            applicationIdSuffix = ".jak1"
            versionNameSuffix = "-jak1"
            resValue("string", "game_name", "jak1")
            resValue("string", "app_name", resEscape(appLabelFor("jak1", "jak1")))
        }
        create("jak2") {
            dimension = "game"
            applicationIdSuffix = ".jak2"
            versionNameSuffix = "-jak2"
            resValue("string", "game_name", "jak2")
            resValue("string", "app_name", resEscape(appLabelFor("jak2", "jak2")))
        }
        create("jak3") {
            dimension = "game"
            applicationIdSuffix = ".jak3"
            versionNameSuffix = "-jak3"
            resValue("string", "game_name", "jak3")
            resValue("string", "app_name", resEscape(appLabelFor("jak3", "jak3")))
        }
        // The multi-game COLLECTION container. Distinct package
        // (org.opengoal.gk.collection) so it coexists with the single-game
        // installs. It has no single game_name (the loader picks from the
        // bundled set) — game_name is kept as "" so R.string.game_name still
        // resolves for the shared MainActivity/LoaderActivity code. Populate
        // src/collection/assets-bundled/bundle/ with 2+ <game>_assets.zip
        // (+ <game>.manifest.properties) to build a real collection (STEP-1).
        create("collection") {
            dimension = "game"
            applicationIdSuffix = ".collection"
            versionNameSuffix = "-collection"
            resValue("string", "game_name", "")
            resValue("string", "app_name", resEscape(appLabelFor("collection", "")))
        }
    }

    sourceSets {
        getByName("main") {
            jniLibs.srcDirs("src/main/jniLibs")
        }
        // Grecharged-buildsys-packaging (autoport 2026-07-17): the APK is ALWAYS
        // slim. The owner rule is absolute — the APK must NEVER embed vanilla
        // source-derived data (verbatim disc files, stock fr3). It ships ONLY the
        // port artifacts:
        //   src/<game>/assets-slim/bundle/<game>_cgo.zip     arm64 CGO/DGO code
        //     (build_cgo_pack.sh)
        //   src/<game>/assets-slim/bundle/<game>_custom.zip  port-custom data
        //     (.grassbake, enhanced HD fr3, recharged PNGs — build_custom_pack.sh)
        // The bulky vanilla iso data + stock fr3 ship SEPARATELY as
        // <game>_assets.zip (scripts/packaging/build_assets_archive.sh) delivered
        // to the user's external asset root; LoaderActivity/gk read them from
        // there. The old self-contained "bundledIso" APK mode is REMOVED.
        getByName("jak1") {
            assets.setSrcDirs(listOf("src/jak1/assets-slim"))
        }
        // Gjak2-boot: jak2 mirrors jak1 (slim-only).
        getByName("jak2") {
            assets.setSrcDirs(listOf("src/jak2/assets-slim"))
        }
        // Phase Glauncher-collection: the collection flavor ships MULTIPLE
        // per-game packs from its own assets-bundled dir. Empty today (only
        // jak1 assets exist); STEP-1 stages jak2/jak3 packs here.
        getByName("collection") {
            assets.setSrcDirs(listOf("src/collection/assets-bundled"))
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
            // Grecharged-grass-poc: EXTRACT native libs to /data/app/.../lib/arm64/ on
            // install (extractNativeLibs=true). The libgk anti-stub deploy check greps
            // the on-disk device libgk for the grass renderer strings; with libs kept
            // inside the APK (=false) that path does not exist. Extracting proves, on the
            // device filesystem, that the installed libgk is the real grass build.
            useLegacyPackaging = true
        }
    }

    androidResources {
        // Grecharged-buildsys-packaging: the slim APK ships already-DEFLATE'd
        // packs (assets/bundle/<game>_cgo.zip + <game>_custom.zip). Storing them
        // (noCompress) avoids a pointless AGP re-DEFLATE of already-compressed
        // content. The tiny manifests stay compressible.
        noCompress += listOf("zip")
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
        // CHECKER-DEBUG companion build (owner has no adb — the PBR checkerboard
        // must be on out of the box). Uncomment, or add the flag by hand to a
        // SEPARATE -B dir, to produce it:
        //     , "-DOG_PBR_CHECKER_DEBUG=ON"
        // NOTE: the onlyIf below skips reconfiguration when a CMakeCache.txt
        // already exists, so flipping this on an existing build-android tree
        // does nothing. Either wipe build-android or configure a second build
        // dir directly:
        //     cmake -S . -B build-android-checker -G Ninja \
        //       -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake \
        //       -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-29 \
        //       -DGOALC_BACKEND=arm64 -DCMAKE_BUILD_TYPE=RelWithDebInfo \
        //       -DOG_PBR_CHECKER_DEBUG=ON
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

// Grecharged-buildsys-packaging (autoport 2026-07-17): the APK is ALWAYS slim and
// ships ONLY port artifacts. Two packs are assembled into the flavor's assets-slim
// bundle dir just before AGP merges that flavor's assets:
//
//   <game>_cgo.zip     the arm64-compiled CGO/DGO code (android/build_cgo_pack.sh),
//                      unpacked to <filesDir>/cgo/<game>/ as the first-scanned
//                      fake_iso overlay so the HEAD arm64 code always wins.
//   <game>_custom.zip  the port-CUSTOM data — .grassbake, enhanced HD fr3, and
//                      recharged HUD PNGs — gated by the build's feature flags
//                      (android/build_custom_pack.sh).
//
// The vanilla source-derived runtime data (verbatim iso files + stock fr3) is NOT
// in the APK. It ships separately as <game>_assets.zip, produced by
// scripts/packaging/build_assets_archive.sh and delivered to the user's external
// asset root, from which LoaderActivity/gk read it. The old self-contained
// "bundledIso" APK mode and android/build_asset_bundle.sh are REMOVED.
//
// Both scripts are idempotent (return in ~1s when their zip is already current),
// so they run every assemble without a repack cost, and HARD-FAIL if a required
// input is missing or a mixed flag-set is detected.
val bundleJak1CgoPack by tasks.registering(Exec::class) {
    workingDir = rootProject.file("..")
    commandLine("bash", "android/build_cgo_pack.sh", "jak1")
}

val bundleJak1CustomPack by tasks.registering(Exec::class) {
    workingDir = rootProject.file("..")
    commandLine("bash", "android/build_custom_pack.sh", "jak1")
}

tasks.matching {
    it.name.startsWith("merge") && it.name.contains("Jak1") && it.name.endsWith("Assets")
}.configureEach {
    dependsOn(bundleJak1CgoPack)
    dependsOn(bundleJak1CustomPack)
}

// Gjak2-boot: jak2 mirrors jak1 — slim CGO pack + port-custom pack.
val bundleJak2CgoPack by tasks.registering(Exec::class) {
    workingDir = rootProject.file("..")
    commandLine("bash", "android/build_cgo_pack.sh", "jak2")
}

val bundleJak2CustomPack by tasks.registering(Exec::class) {
    workingDir = rootProject.file("..")
    commandLine("bash", "android/build_custom_pack.sh", "jak2")
}

tasks.matching {
    it.name.startsWith("merge") && it.name.contains("Jak2") && it.name.endsWith("Assets")
}.configureEach {
    dependsOn(bundleJak2CgoPack)
    dependsOn(bundleJak2CustomPack)
}

// Phase Glauncher-collection (autoport 2026-07-02): ASSET-DRIVEN detection
// demonstrator. Prints, per flavor, the bundled games + the resulting mode
// (SINGLE vs COLLECTION) + the launcher label appLabelFor() computes — the exact
// values the built APK carries. This is the build-time half of the 1-vs-collection
// detection (the runtime half is LoaderActivity enumerating the same bundle dir).
//
//   ./gradlew printGameDetection                      # scan every flavor's bundle dir
//   ./gradlew printGameDetection -PdetectDir=/tmp/x   # DRY-RUN an arbitrary dir
//
// The -PdetectDir dry-run lets a test stage a synthetic 2-game bundle dir
// (touch jak1_assets.zip jak2_assets.zip) and prove detection flips to COLLECTION
// + "Recharged Collection" WITHOUT shipping a real 2nd game.
tasks.register("printGameDetection") {
    description = "Asset-driven game detection: per flavor (or -PdetectDir), print bundled games + mode + app label."
    group = "verification"
    doLast {
        val dryDir = project.findProperty("detectDir") as String?
        if (dryDir != null) {
            val d = file(dryDir)
            val games = if (d.isDirectory)
                (d.listFiles() ?: emptyArray())
                    .filter { it.isFile && it.name.endsWith("_assets.zip") }
                    .map { it.name.removeSuffix("_assets.zip") }.sorted()
            else emptyList()
            val mode = if (games.size > 1) "COLLECTION" else "SINGLE"
            val label = if (games.size > 1) collectionTitle else titleFor(games.firstOrNull() ?: "jak1")
            println("DETECT dir=$dryDir games=$games count=${games.size} mode=$mode label=\"$label\"")
            return@doLast
        }
        listOf("jak1", "jak2", "jak3", "collection").forEach { fl ->
            val games = detectBundledGames(fl)
            val mode = when {
                games.size > 1 -> "COLLECTION"
                games.isEmpty() && fl == "collection" -> "COLLECTION(empty)"
                else -> "SINGLE"
            }
            val label = appLabelFor(fl, if (fl == "collection") "" else fl)
            println("DETECT flavor=$fl bundledGames=$games count=${games.size} mode=$mode label=\"$label\"")
        }
    }
}
