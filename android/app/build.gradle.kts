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
// The set of games an APK contains == which per-game asset bundles
// (`<game>_assets.zip`) are present under that flavor's assets bundle dir at
// BUILD time. Exactly ONE game => single-game APK: boots STRAIGHT into that game
// with its own launcher name + icon (no menu). MORE THAN ONE => COLLECTION APK:
// label "Jak and Daxter: The Recharged Jak-pot" + a boot selection menu. The
// same detection runs at runtime in LoaderActivity (it enumerates the bundle
// dir), so dropping a 2nd game's bundle into a flavor flips it to collection
// with no other code change.
//
// These are `val` lambdas (not top-level `fun`s) so they capture the Project
// receiver and can call file(); they must be declared before the android {}
// block that consumes appLabelFor().
val gameTitles = mapOf(
    "jak1" to "Jak & Daxter",
    "jak2" to "Jak II",
    "jak3" to "Jak 3",
    "jakx" to "Jak X",
)
val collectionTitle = "Jak and Daxter: The Recharged Jak-pot"
val titleFor: (String) -> String = { id -> gameTitles[id] ?: id }
// External-asset-root feature (autoport 2026-07): a game is "present" in a
// flavor if EITHER its full bundle (<game>_assets.zip, assets-bundled) OR its
// slim CGO pack (<game>_cgo.zip, assets-slim) is staged. Scan both dirs and both
// suffixes so slim builds (now the default) still detect their game(s).
val detectBundledGames: (String) -> List<String> = { flavor ->
    val games = sortedSetOf<String>()
    listOf(
        Pair("src/$flavor/assets-bundled/bundle", "_assets.zip"),
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
        // collection flavor gets "Jak and Daxter: The Recharged Jak-pot".
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
        // Phase Gpkg-distributable (autoport 2026-06-27): the normal jak1
        // APK no longer bundles the raw ~1.34 GiB iso_data/fr3 dirs. Instead
        // it ships ONE DEFLATE archive — src/jak1/assets-bundled/bundle/
        // jak1_assets.zip (+ manifest.properties) produced on PC by
        // build_asset_bundle.sh (wired via the bundleJak1Assets task below) —
        // which LoaderActivity decompresses into filesDir on first run. So
        // the default assets srcDir becomes assets-bundled, NOT the raw
        // src/jak1/assets (which stays on disk as the bundle's input only).
        //
        // A40 `-PslimIso=true` still builds an assets-light APK (fr3 only,
        // no payload) for fast libgk.so iteration: the device keeps its
        // already-unpacked files/iso_data/<game>/, so a slim install costs
        // ~100 MB instead of the full ~1 GB compressed bundle.
        // External-asset-root feature (autoport 2026-07): SLIM IS NOW THE DEFAULT.
        // The normal APK ships ONLY the tiny arm64 CGO pack
        // (src/<game>/assets-slim/bundle/<game>_cgo.zip, built by
        // build_cgo_pack.sh); the bulky iso data + fr3 come from the user's
        // external asset folder. Pass -PbundledIso=true to build the OLD
        // self-contained APK (full ~1.6 GiB payload from assets-bundled).
        // -PslimIso is kept as a NO-OP legacy alias (slim is the default now).
        getByName("jak1") {
            assets.setSrcDirs(listOf(
                if (project.findProperty("bundledIso") == "true") "src/jak1/assets-bundled"
                else "src/jak1/assets-slim"
            ))
        }
        // Gjak2-boot: jak2 mirrors jak1.
        getByName("jak2") {
            assets.setSrcDirs(listOf(
                if (project.findProperty("bundledIso") == "true") "src/jak2/assets-bundled"
                else "src/jak2/assets-slim"
            ))
        }
        // Phase Glauncher-collection: the collection flavor ships MULTIPLE
        // per-game bundles from its own assets-bundled dir. Empty today (only
        // jak1 assets exist); STEP-1 stages jak2/jak3 zips here.
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
        // Phase Gpkg-distributable: the runtime payload now ships as ONE
        // already-DEFLATE'd archive (assets/bundle/<game>_assets.zip). Storing
        // it (noCompress) is essential: AGP re-DEFLATE of a ~1 GB compressed
        // file buys ~nothing AND walks straight into the mergeAssets/package
        // GC death-spiral the raw-payload build hit. The tiny manifest stays
        // compressible. (assets-slim's fr3 files are already small.)
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

// Phase Gpkg-distributable (autoport 2026-06-27): build the COMPRESSED
// runtime-asset archive that the normal jak1 APK ships and LoaderActivity
// decompresses on first run. The script assembles the FULL, internally
// consistent set straight from the authoritative PC build outputs —
// out/jak1/iso (data) + out/jak1-arm64-full/iso (the arm64 CGO/DGO) +
// out/jak1/fr3 (all 26 texture packs) — and packs them into
// src/jak1/assets-bundled/bundle/jak1_assets.zip (+ manifest.properties)
// just before AGP merges that flavor's assets. Sourcing the build outputs
// (not the on-disk staging dirs, which drifted to a slim/stale set and
// caused a false-green) makes the bundle complete + consistent by
// construction; the script HARD-FAILS if anything is missing or stale. It
// is idempotent and returns in ~1s when the zip is already current, so it
// runs every assemble without a repack cost. Skipped for -PslimIso=true (the
// slim build ships no payload — fr3 only — for fast libgk.so iteration).
// External-asset-root feature (autoport 2026-07): the FULL bundle tasks now run
// ONLY for -PbundledIso=true (the opt-in self-contained APK). The default (slim)
// build instead runs the CGO-pack tasks below.
val bundleJak1Assets by tasks.registering(Exec::class) {
    workingDir = rootProject.file("..")
    commandLine("bash", "android/build_asset_bundle.sh", "jak1")
    onlyIf { project.findProperty("bundledIso") == "true" }
}

// External-asset-root feature: build the SLIM arm64 CGO pack
// (src/jak1/assets-slim/bundle/jak1_cgo.zip) the default APK ships. Runs unless
// -PbundledIso=true (the full-bundle build supplies code via the big zip).
val bundleJak1CgoPack by tasks.registering(Exec::class) {
    workingDir = rootProject.file("..")
    commandLine("bash", "android/build_cgo_pack.sh", "jak1")
    onlyIf { project.findProperty("bundledIso") != "true" }
}

tasks.matching {
    it.name.startsWith("merge") && it.name.contains("Jak1") && it.name.endsWith("Assets")
}.configureEach {
    dependsOn(bundleJak1Assets)
    dependsOn(bundleJak1CgoPack)
}

// Gjak2-boot: jak2 mirrors jak1 — full bundle (opt-in) + slim CGO pack (default).
val bundleJak2Assets by tasks.registering(Exec::class) {
    workingDir = rootProject.file("..")
    commandLine("bash", "android/build_asset_bundle.sh", "jak2")
    onlyIf { project.findProperty("bundledIso") == "true" }
}

val bundleJak2CgoPack by tasks.registering(Exec::class) {
    workingDir = rootProject.file("..")
    commandLine("bash", "android/build_cgo_pack.sh", "jak2")
    onlyIf { project.findProperty("bundledIso") != "true" }
}

tasks.matching {
    it.name.startsWith("merge") && it.name.contains("Jak2") && it.name.endsWith("Assets")
}.configureEach {
    dependsOn(bundleJak2Assets)
    dependsOn(bundleJak2CgoPack)
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
// + "The Recharged Jak-pot" WITHOUT shipping a real 2nd game.
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
