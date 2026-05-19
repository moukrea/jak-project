# Phase 13 — Real APK with per-game product flavors

## Goal

Produce real, debug-signed Android APKs using the Android Gradle Plugin.
The phase-11 stub (a shell script that zips a libgk.so with a text-form
manifest) is explicitly rejected.

Mirror the desktop model: **one runtime, three games selected at launch**.
On desktop you run `gk --game jak1` (or jak2/jak3). On Android, we ship
**three APK variants** built from one source tree via Gradle product
flavors — one per game. Each has its own `applicationId`, app icon, and
gets its game data from its own assets overlay (phases 14-16 populate
those).

## Hard requirements

1. **Real Gradle wrapper.** Either:
   - `gradle wrapper --gradle-version 8.7` so
     `android/gradle/wrapper/gradle-wrapper.jar` exists, OR
   - Replace `android/gradlew` with `exec gradle "$@"` and rely on
     system gradle (the validator sources `.autoport/lib/android-env.sh`
     which adds it to PATH).
   - Either way, retire `scripts/fallback-assemble-debug.sh`.

2. **Product flavors `jak1`, `jak2`, `jak3`** in `android/app/build.gradle.kts`:

   ```kotlin
   android {
       flavorDimensions += "game"
       productFlavors {
           create("jak1") {
               dimension = "game"
               applicationIdSuffix = ".jak1"
               versionNameSuffix = "-jak1"
               resValue("string", "app_name", "OpenGOAL — Jak 1")
           }
           create("jak2") {
               dimension = "game"
               applicationIdSuffix = ".jak2"
               versionNameSuffix = "-jak2"
               resValue("string", "app_name", "OpenGOAL — Jak 2")
           }
           create("jak3") {
               dimension = "game"
               applicationIdSuffix = ".jak3"
               versionNameSuffix = "-jak3"
               resValue("string", "app_name", "OpenGOAL — Jak 3")
           }
       }
   }
   ```

   This produces three APKs in
   `app/build/outputs/apk/{jak1,jak2,jak3}/debug/app-{jak1,jak2,jak3}-debug.apk`.
   Per-flavor source sets live at `src/jak1/`, `src/jak2/`, `src/jak3/`
   (each can contain `assets/`, `java/`, `AndroidManifest.xml` overlay).

3. **`./gradlew assembleJak1Debug` (or any flavor) succeeds.** Phase 13
   only verifies AGP wiring works for ONE flavor — game data is not
   yet present (that's phase 14-16). The base APK must:
   - Use AGP's `aapt2` so `aapt2 dump badging` parses it.
   - Be debug-signed via AGP's auto-generated keystore.
   - Bundle `lib/arm64-v8a/libgk.so` (size ≥ 2 MB from phase 12).
   - Contain `classes.dex` from the Java/Kotlin compile.
   - applicationId be `org.opengoal.gk.jak1` (for the jak1 flavor).

4. **JNI bridge.** `NativeGk.java` must do more than declare a stub
   `static native String version()`. Add at minimum:
   - `static native int startGame(String gameName, String dataRoot)` —
     calls into the real runtime in `game/main.cpp` after staging an
     argv that includes `--game <gameName>` and `-fakeiso`. Per-flavor
     code in `src/jakN/java/.../GameSelection.java` can hardcode the
     name, OR the base activity reads it from the resource string
     `R.string.game_name` set per flavor.
   - `static native void onTouchEvent(int x, int y, int action)` —
     forwards Android MotionEvents into SDL_PushEvent so the runtime's
     existing input layer sees synthesized SDL events.

5. **Activity wiring.** `MainActivity` must:
   - On `onCreate`, lay out `TouchControlsView` over an SDL surface.
   - Call `System.loadLibrary("gk")` then `NativeGk.startGame(...)` on
     a background thread.
   - In `onPause/onResume`, forward to SDL's lifecycle methods.

6. **Asset access path.** Each flavor's APK ships its game data under
   `assets/iso_data/<game>/` (phases 14-16 populate this). On first
   launch, the JNI bridge either:
   - Copies `assets/iso_data/<game>/` to `getFilesDir()/iso_data/<game>/`
     once, then points the runtime at the filesDir path; OR
   - Uses `AAssetManager_open` + memory-map via `AAsset_openFileDescriptor`
     so the runtime reads directly from the APK zip without unpacking.

   Either is fine; pick the simpler one and document the trade-off in
   `android/README.md`.

## Constraints

- Debug signing only (AGP auto-creates the keystore).
- `min-sdk` 29, `target-sdk` 34 (matches NDK build target).
- Don't add Play Services / Firebase. Offline.
- If a per-flavor APK exceeds 150 MB at assembly time (mostly possible
  in phases 14-16 when assets land), switch the build to `bundleJakNDebug`
  producing an `.aab` (Android App Bundle) with asset packs. Don't treat
  size as a hard blocker — package differently.

## Don't

- Don't ship a release-signed APK.
- Don't add resources to `src/main/` that override flavor-specific ones.
- Don't bake the game name into native code; pass it from Java via
  `startGame(name, ...)`.

## Validator

```
.autoport/validators/phase-13-real-apk.sh
```

Builds `assembleJak1Debug` (cheapest single-flavor APK), then verifies
binary manifest via `aapt2 dump badging`, debug signature via
`apksigner verify`, and structural inventory of the zip.

## Success

A debug-signed APK at
`android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk` (or any
flavor) parseable by aapt2 and verifiable by apksigner.
