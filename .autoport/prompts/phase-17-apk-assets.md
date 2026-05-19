# Phase 17 — APK-bundled assets used at runtime (no manual push)

## Goal

The APK already ships the game's iso_data under `assets/iso_data/<game>/`
(phases 14-16 staged it there). The Activity, however, currently looks for
data in `getFilesDir()/iso_data/<game>/` — which is empty on first launch
— and shows a "Missing data" toast. We need the bundled assets to actually
get used. The fix is to **extract them from the APK to filesDir on first
launch**, behind a sentinel so subsequent launches are O(1).

After this phase, a user who sideloads the debug APK and taps the icon
will see the game data load itself with no ADB / no manual file copy.

## Constraints

- Java/Kotlin work only. **Do NOT touch native code** in `android/*.cpp` —
  phases 18-21 handle the runtime bring-up. This phase keeps the native
  startup path exactly as it is today (kernel init + return); the only
  observable change is that the iso-dir-present check now succeeds.
- **Do NOT change the desktop x86 build**. This phase touches
  `android/app/src/...` only.
- Do **NOT** delete the assets from the APK after copying. The APK is the
  source of truth; the filesDir copy is a cache the user can wipe (clear
  app data) and we re-extract.
- The extraction must be **idempotent**: a sentinel file marks completion
  so a second launch is instant. If extraction was previously partial
  (sentinel absent, but target dir non-empty), wipe the partial result
  and start over — never trust a half-finished copy.
- Run extraction on a **background thread**. Doing 1.4 GB of file copies
  on the UI thread triggers Android's ANR ("Application Not Responding")
  watchdog after 5s.
- Keep the screen on during extraction (`getWindow().addFlags(FLAG_KEEP_SCREEN_ON)`).
  An asleep phone aborts the copy.

## Concrete deliverables

1. **New `LoaderActivity`** at
   `android/app/src/main/java/org/opengoal/gk/LoaderActivity.java`
   (`extends AppCompatActivity`). Responsibilities:
   - On `onCreate`, show a minimal "Preparing game data… X / Y" TextView UI.
   - Resolve `gameName` from `R.string.game_name` (same per-flavor source
     of truth the current `MainActivity` uses).
   - Spawn a worker thread that calls `extractIfMissing(gameName)`. The
     worker posts UI updates via `runOnUiThread`.
   - On extraction success, `startActivity(new Intent(this, MainActivity.class))`
     then `finish()`.
   - On extraction failure, leave the activity visible with the error in
     the TextView (do NOT crash; the user will need to inspect logcat).

2. **`extractIfMissing(String gameName)`** logic — same file:
   - target dir: `new File(getFilesDir(), "iso_data/" + gameName)`
   - sentinel: `new File(target, ".extracted_v1")`
   - if sentinel exists → log `iso_data already extracted` and return
   - else: if target exists and is non-empty, wipe it (recursive delete)
     to avoid trusting a partial copy
   - `getAssets().list("iso_data/" + gameName)` to enumerate
   - For each entry, `getAssets().open(...)` → `FileOutputStream` →
     copy with a 256 KB buffer. Track cumulative bytes and per-file
     progress for the UI.
   - Use a `RandomAccessFile`-style write with periodic `fsync` is NOT
     required; the default sequence is fine.
   - After the loop, **only then** create the sentinel file with
     `new FileOutputStream(sentinel).close()`. The sentinel must be
     last so a SIGKILL mid-copy doesn't fool the next launch.
   - Log a final summary line:
     `iso_data extract: <N> files, <BYTES> bytes in <MS>ms`

3. **`MainActivity` change** (`android/app/src/main/java/org/opengoal/gk/MainActivity.java`):
   - Remove the "Missing data" Toast/log path entirely. By the time
     `MainActivity` runs, extraction is guaranteed complete (Loader
     started us). Keep the "iso_data present at …" log line — phase 18+
     validators use it.
   - **Do not** start the runtime thread before checking the iso dir.
     The check is now a hard assertion; if the dir is empty when
     MainActivity launches it indicates a Loader bug — log a fatal
     error to the TextView and don't start the thread.

4. **AndroidManifest.xml**
   (`android/app/src/main/AndroidManifest.xml`):
   - `LoaderActivity` becomes the new `MAIN`/`LAUNCHER` activity.
   - `MainActivity` no longer has the `MAIN`/`LAUNCHER` intent filter
     (still exported as the runtime activity Loader launches into).
   - Both activities keep their existing `android:configChanges`,
     `android:screenOrientation`, etc.

5. **Log markers** (exact strings — the validator greps for these):
   - On first launch: `iso_data extract: <N> files, <BYTES> bytes in <MS>ms`
     where N>0 and BYTES>1000000000 (jak1 is ~1.4 GB).
   - On a subsequent launch (sentinel present):
     `iso_data already extracted` (no re-extraction).
   - In MainActivity (always):
     `iso_data present at /data/user/0/<package>/files/iso_data/<game>`

6. **No regressions**: `./gradlew assembleJak1Debug` must still succeed
   and the resulting APK must still be debug-signed (apksigner verify OK).

## Don't

- Do **not** use Kotlin coroutines or AndroidX `WorkManager`. Plain
  `Thread` keeps the diff small and avoids pulling in new dependencies.
- Do **not** read assets directly from the APK at runtime
  (`AAssetManager_open` + `mmap` path). That's a future optimization;
  this phase deliberately picks the simple extract-once approach.
- Do **not** show a custom splash image. The TextView UI is sufficient;
  graphics work is later.

## Pitfalls

- `getAssets().list("foo")` returns immediate children only. jak1 assets
  are flat (`assets/iso_data/jak1/0COMMON.TXT`, no subdirs), so a single
  call is enough. Verify with a smoke run: `entries.length` must be ~321
  for jak1.
- AAB asset packs are NOT involved here — these are bundled into the base
  APK by AGP because they were placed in `src/jak1/assets/`. No special
  handling needed.
- AGP compresses asset files by default. That's fine — `AssetManager.open`
  decompresses transparently. (A later phase may add `aaptOptions
  { noCompress(".cgo", ".dgo", ".str") }` to make AAsset_fd-based zero
  copy possible, but not in this phase.)
- The 1.4 GB extraction is slow on phones with eMMC (~30-90 seconds is
  normal). Keep the screen on.

## Validator

```
.autoport/validators/phase-17-apk-assets.sh
```

The validator (a) builds jak1 APK, (b) **uninstalls** any existing
`org.opengoal.gk.jak1` to force the first-launch path, (c) installs and
launches, (d) waits for the `iso_data extract: N files...` marker
within 240s, (e) force-stops and re-launches expecting the
`iso_data already extracted` fast path within 15s, (f) confirms the
final `iso_data present at …` marker, (g) confirms the desktop x86
build still passes.

## Success

Sideloading `app-jak1-debug.apk` shows a "Preparing game data… X/Y"
screen on first launch, then automatically transitions to the runtime
activity once extraction completes. Subsequent launches go straight to
the runtime activity. No manual `adb push`. No "Missing data" toast.
