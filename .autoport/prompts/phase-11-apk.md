# Phase 11 — APK packaging and emulator boot

## Goal

Wrap the Android-built binaries into a signed debug APK that installs and launches on an emulator, reaching the same "target started" log line as phase 09.

## Concrete deliverables

1. `android/app/` Gradle project structure:
   - `build.gradle.kts`
   - `AndroidManifest.xml` with required permissions and the SDL2 activity (extend org.libsdl.app.SDLActivity)
   - Native libs section pointing at the build-android outputs
2. Asset packaging: the game requires data files (player-extracted from their PS2 ISO). Document the install-time flow — the user copies the extracted files to `Android/data/<package>/files/iso_data/` on first launch. The app prompts if missing.
3. Touch controls minimal scaffolding: stub virtual joystick + 4 buttons. Don't sweat the UX — this is to prove the input plumbing works, not to ship a release.
4. `gradlew assembleDebug` produces an APK.

## Constraints

- Use Java/Kotlin for the activity only. All game logic stays in the native library.
- Don't sign with a release key. Debug signing only.
- Target SDK whatever's current; min SDK 29 (Android 10).

## Success

```bash
cd android && ./gradlew assembleDebug
ls -la app/build/outputs/apk/debug/*.apk
# If adb + emulator running:
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb logcat -c
adb shell am start -n <package>/.MainActivity
sleep 30
adb logcat -d | grep -E "target started|level zero loaded"
```
