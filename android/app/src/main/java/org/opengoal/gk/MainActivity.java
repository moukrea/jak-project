// Phase 18 (autoport): MainActivity now extends SDLActivity so SDL3 owns
// the EGL/GLES context on the Activity's SurfaceView.
//
// Lifecycle:
//   1. LoaderActivity has guaranteed iso_data is extracted to filesDir.
//   2. SDLActivity.onCreate loads libgk.so, sets up SDL JNI, creates the
//      SDLSurface inside an mLayout RelativeLayout, then schedules the
//      SDL thread which dlsym's the C entrypoint named by
//      getMainFunction() and calls it.
//   3. We override that to "gk_sdl_main", defined in gk_android_main.cpp.

package org.opengoal.gk;

import android.content.SharedPreferences;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.view.View;
import android.widget.RelativeLayout;

import org.libsdl.app.SDLActivity;

import java.io.File;

public class MainActivity extends SDLActivity {
    private static final String TAG = "opengoal-gk";
    private static final String ISO_DATA_SUBDIR = "iso_data";

    // Phase Glauncher-collection (autoport 2026-07-02): LoaderActivity passes the
    // game the user is booting (the single bundled game, or the one picked from
    // the collection menu) as this intent extra. Falls back to R.string.game_name
    // (the single-game flavor default) when launched directly without the extra.
    public static final String EXTRA_SELECTED_GAME = "org.opengoal.gk.SELECTED_GAME";

    // Phase E2 (autoport): SharedPreferences key for the touch-overlay
    // settings flag. The desktop build's keyboard fallback is "on
    // whenever no gamepad is present"; we mirror that by setting the
    // default at first launch to the result of the gamepad probe (false
    // if a pad is already attached, true otherwise). Once written the
    // user's choice persists across launches independent of pad state.
    private static final String PREFS_NAME = "opengoal-gk";
    private static final String PREF_TOUCH_OVERLAY_ENABLED =
            "touch_overlay_enabled";
    private static final String PREF_TOUCH_OVERLAY_INITIALISED =
            "touch_overlay_initialised";
    private static final int GAMEPAD_POLL_MS = 1000;

    private TouchOverlayView mTouchOverlay;
    private Handler mGamepadPollHandler;
    private int mLastGamepadCount = -1;
    // Ginput-replay-realinput (autoport): true when the input record/replay
    // harness is armed (debug.opengoal.pad_replay = record|replay). While armed,
    // the touch overlay is GUARANTEED to stay a live, touch-capable input path —
    // it is force-added even when the gamepad default would disable it, and the
    // gamepad auto-hide keeps it touch-capable (never View.GONE) instead of
    // removing it from hit-testing. Rationale below in setupTouchOverlay().
    private boolean mInputRecordArmed = false;

    @Override
    protected String[] getLibraries() {
        // Default SDLActivity loads libSDL3.so + libmain.so. We statically
        // link SDL3 into libgk.so (phase 18), so there's exactly one .so
        // to load.
        return new String[] { "gk" };
    }

    @Override
    protected String getMainSharedObject() {
        // Absolute path to the .so SDL should dlopen for nativeRunMain.
        // The default implementation derives this from getLibraries(); we
        // hard-code it so a refactor of getLibraries() doesn't silently
        // break the dlsym lookup.
        return getApplicationInfo().nativeLibraryDir + "/libgk.so";
    }

    @Override
    protected String getMainFunction() {
        // C symbol SDL will dlsym from libgk.so and invoke. Phase 18's
        // gk_sdl_main is a placeholder that does SDL_Init + GL bring-up.
        // Phase 19 swaps the body for the real GOAL runtime boot.
        return "gk_sdl_main";
    }

    // Phase Glauncher-collection: the game to boot is the one LoaderActivity
    // selected (single bundled game or a collection-menu pick), passed via
    // EXTRA_SELECTED_GAME; fall back to the single-game flavor default.
    private String selectedGame() {
        String g = getIntent() != null
                ? getIntent().getStringExtra(EXTRA_SELECTED_GAME) : null;
        if (g == null || g.isEmpty()) {
            g = getString(R.string.game_name);
        }
        return g;
    }

    @Override
    protected String[] getArguments() {
        // Pass the selected game name and the absolute iso_data dir as
        // argv to gk_sdl_main. Phase 19 will consume these; phase 18 just
        // logs them.
        final String gameName = selectedGame();
        final File isoDir = new File(getFilesDir(), ISO_DATA_SUBDIR + "/" + gameName);
        return new String[] { gameName, isoDir.getAbsolutePath() };
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        // Phase 20: push the game name + data root into native BEFORE
        // super.onCreate triggers SDLActivity's loadLibraries → SDL thread
        // dispatch. The first NativeGk static reference here will run the
        // class's static initializer, which System.loadLibrary("gk")'s
        // libgk.so itself; once that's done, setSelectedGame /
        // setDataRoot populate the process-lifetime globals that
        // gk_sdl_main will read when the SDL thread dlsym's it.
        final String gameName = selectedGame();
        final File isoDir = new File(getFilesDir(), ISO_DATA_SUBDIR + "/" + gameName);
        NativeGk.setSelectedGame(gameName);
        NativeGk.setDataRoot(isoDir.getAbsolutePath());

        // Owner swamp-crash capture build (INSTRUMENTATION ONLY): push the app's
        // EXTERNAL files dir so a JAK_SWAMP_CAPTURE libgk can write the crash
        // forensic to a file the owner retrieves from the Files app without adb.
        // In a normal libgk this native call is an inert no-op.
        final File extFilesDir = getExternalFilesDir(null);
        if (extFilesDir != null) {
            NativeGk.setExternalFilesDir(extFilesDir.getAbsolutePath());
        }

        // Phase Glang-mixed (autoport): bridge the device locale into the
        // process environment BEFORE the runtime boots. The engine's
        // sceScfGetLanguage() (game/sce/libscf.cpp, __linux__ path) reads
        // $LANG to pick the default text/subtitle/audio language — desktop
        // Linux/Windows follow the OS language, but Android app processes
        // have no $LANG, so every defaults-boot (fresh install, wiped
        // files/) silently fell back to English regardless of the phone's
        // locale. One env var makes the existing desktop code path work
        // 1-to-1 on device; no engine change.
        try {
            final String locale = java.util.Locale.getDefault().toLanguageTag();
            android.system.Os.setenv("LANG", locale, true);
            Log.i(TAG, "locale-bridge: LANG=" + locale
                    + " (device locale -> scf-get-language)");
        } catch (android.system.ErrnoException e) {
            Log.e(TAG, "locale-bridge: setenv LANG failed", e);
        }

        // SDLActivity.onCreate is what loads libgk.so. Anything that
        // touches NativeGk MUST run AFTER super.onCreate. (The two calls
        // above do touch NativeGk, but only the static initializer fires,
        // which is harmless and just calls System.loadLibrary("gk")
        // ahead of SDLActivity's own load.)
        super.onCreate(savedInstanceState);

        // LoaderActivity should have completed extraction before transitioning
        // here. If iso_data is missing now it's a Loader regression; surface
        // it loudly in logcat. The phase 18 validator greps for this marker
        // to confirm the Loader→Main handoff actually happened.
        String[] isoEntries = isoDir.list();
        if (!isoDir.isDirectory() || isoEntries == null || isoEntries.length == 0) {
            Log.e(TAG, "FATAL: " + gameName + " iso_data missing at "
                       + isoDir.getAbsolutePath()
                       + " — LoaderActivity did not extract.");
        } else {
            Log.i(TAG, gameName + " iso_data present at " + isoDir.getAbsolutePath());
        }

        // Phase E2 (autoport): bring back the on-screen PS2-button overlay
        // behind a SharedPreferences flag. Default mirrors the desktop
        // build's keyboard-fallback rule — on when no gamepad is
        // connected at first launch, off when one is.
        setupTouchOverlay();

        Log.i(TAG, "MainActivity onCreate done; mLayout="
                + (mLayout != null)
                + " mLayout.children=" + (mLayout != null ? mLayout.getChildCount() : -1));
    }

    private void setupTouchOverlay() {
        if (mLayout == null) {
            Log.w(TAG, "touch overlay setup: mLayout is null, skipping");
            return;
        }
        SharedPreferences prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE);
        int gamepadsAtStart = safeGetOpenGamepadCount();
        boolean defaultEnabled = (gamepadsAtStart == 0);
        boolean initialised = prefs.getBoolean(PREF_TOUCH_OVERLAY_INITIALISED, false);
        if (!initialised) {
            prefs.edit()
                    .putBoolean(PREF_TOUCH_OVERLAY_INITIALISED, true)
                    .putBoolean(PREF_TOUCH_OVERLAY_ENABLED, defaultEnabled)
                    .apply();
        }
        boolean enabled = prefs.getBoolean(PREF_TOUCH_OVERLAY_ENABLED, defaultEnabled);

        // Ginput-replay-realinput (autoport): when the input record/replay harness
        // is armed, GUARANTEE a capturable input path. The record tap (CPadGetData
        // -> pad_replay) only ever sees input that reached the cpad mirror via
        // on_pad_button/on_pad_axis; the touch overlay is the one input source we
        // can always provide. If the overlay is disabled here (a gamepad was
        // present at first launch, so PREF_TOUCH_OVERLAY_ENABLED defaulted false
        // and persisted) AND the selected Bluetooth gamepad isn't actually
        // delivering Android input events (bonded-but-not-connected / HID quirk —
        // common for the owner's Switch Pro / DualShock pads), there is NO input
        // path at all and the record is SILENTLY all-neutral. That is exactly the
        // owner's 20-min / 90-min wasted captures (0/71354, 0/335077 non-neutral).
        // So while a record/replay is armed, force the overlay on and keep it
        // touch-capable (see pollGamepadCount) — a record can then never be
        // silently input-less; the owner always has a working, recordable touch
        // fallback even if their gamepad stays silent.
        mInputRecordArmed = isInputRecordArmed();
        if (mInputRecordArmed && !enabled) {
            Log.i(TAG, "touch overlay: pad_replay record/replay armed — FORCING the "
                    + "overlay ON despite the disabled setting, so a record always "
                    + "has a capturable touch input path (no silent all-neutral)");
            enabled = true;
        }

        Log.i(TAG, "touch overlay setting: enabled=" + enabled
                + " default=" + defaultEnabled
                + " gamepads_at_start=" + gamepadsAtStart
                + " record_armed=" + mInputRecordArmed);

        if (!enabled) {
            Log.i(TAG, "touch overlay disabled by settings (gamepad present or user-off)");
            return;
        }

        mTouchOverlay = new TouchOverlayView(this);
        RelativeLayout.LayoutParams lp = new RelativeLayout.LayoutParams(
                RelativeLayout.LayoutParams.MATCH_PARENT,
                RelativeLayout.LayoutParams.MATCH_PARENT);
        mLayout.addView(mTouchOverlay, lp);
        mTouchOverlay.bringToFront();
        // Marker line the validator greps (`touch overlay enabled` matches
        // the BOOT_LOG check). Gtouch-controls: the overlay now starts HIDDEN
        // (alpha 0, still touchable) and fades in on the first touch, then
        // fades out after 10 s idle — so it is enabled-but-hidden at startup,
        // not always-visible. The overlay still auto-hides outright if a real
        // gamepad connects (pollGamepadCount below).
        Log.i(TAG, "touch overlay enabled — hidden until first touch "
                + "(show-on-touch + 10s idle fade; no gamepad at startup)");

        // Ginput-replay-realinput (autoport): while a record/replay is armed, keep
        // the controls visible (no idle fade) so the owner can see and use them to
        // capture a demo — guaranteeing a discoverable, recordable touch input even
        // if the selected Bluetooth gamepad is silent.
        if (mInputRecordArmed) {
            mTouchOverlay.setPersistentVisible(true);
        }

        // Poll the SDL-managed open gamepad count on the UI thread. SDL
        // emits SDL_EVENT_GAMEPAD_ADDED off the SDL main thread; rather
        // than plumb a JNI callback we read the count directly and react
        // to transitions. 1 Hz is plenty for hide/show UX.
        mGamepadPollHandler = new Handler(Looper.getMainLooper());
        mGamepadPollHandler.post(new Runnable() {
            @Override public void run() {
                pollGamepadCount();
                if (mGamepadPollHandler != null) {
                    mGamepadPollHandler.postDelayed(this, GAMEPAD_POLL_MS);
                }
            }
        });
    }

    private void pollGamepadCount() {
        int n = safeGetOpenGamepadCount();
        if (n == mLastGamepadCount) {
            return;
        }
        int prev = mLastGamepadCount;
        mLastGamepadCount = n;
        if (prev <= 0 && n > 0 && mTouchOverlay != null
                && mTouchOverlay.getVisibility() == View.VISIBLE) {
            if (mInputRecordArmed) {
                // Ginput-replay-realinput (autoport): a record/replay is armed.
                // Do NOT View.GONE the overlay — GONE removes it from touch
                // hit-testing, killing the only guaranteed-capturable input path.
                // Keep it touch-capable; it stays visually hidden (alpha 0) until
                // touched, so a gamepad user isn't disturbed, but a touch always
                // reaches the recorder. This prevents the owner's silent
                // all-neutral when a Bluetooth pad is selected but not delivering.
                Log.i(TAG, "gamepad detected during record/replay: keeping touch "
                        + "overlay touch-capable (NOT View.GONE) so touch stays a "
                        + "recordable fallback (open_gamepad_count=" + n + ")");
            } else {
                Log.i(TAG, "gamepad detected: hiding touch overlay "
                        + "(open_gamepad_count=" + n + ")");
                mTouchOverlay.setVisibility(View.GONE);
            }
        } else if (prev > 0 && n == 0 && mTouchOverlay != null
                && mTouchOverlay.getVisibility() != View.VISIBLE) {
            // User unplugged the pad — re-show overlay so the game stays
            // controllable. Respect the persisted setting; if the user
            // explicitly turned the overlay off we leave it off.
            SharedPreferences prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE);
            if (prefs.getBoolean(PREF_TOUCH_OVERLAY_ENABLED, true)) {
                Log.i(TAG, "gamepad removed: re-showing touch overlay");
                mTouchOverlay.setVisibility(View.VISIBLE);
            }
        }
    }

    private static int safeGetOpenGamepadCount() {
        try {
            return NativeGk.getOpenGamepadCount();
        } catch (UnsatisfiedLinkError e) {
            // Native side may not be up yet during very early onCreate;
            // treat as "no gamepads" so the default is overlay-on.
            return 0;
        }
    }

    // Ginput-replay-realinput (autoport): is the input record/replay harness armed?
    // The harness is selected by the system property debug.opengoal.pad_replay
    // (set with `adb setprop` BEFORE launch; read by native in gk_android_main).
    // onCreate runs before the native SDL thread reads the property, so we read
    // the property DIRECTLY here (getprop) rather than via a JNI getter — the
    // property value is already present at launch. Used to guarantee a capturable
    // touch input path while recording (see setupTouchOverlay / pollGamepadCount).
    private static boolean isInputRecordArmed() {
        try {
            Process p = Runtime.getRuntime().exec(
                    new String[] { "getprop", "debug.opengoal.pad_replay" });
            java.io.BufferedReader r = new java.io.BufferedReader(
                    new java.io.InputStreamReader(p.getInputStream()));
            String line = r.readLine();
            r.close();
            p.waitFor();
            if (line != null) {
                line = line.trim();
                return line.equals("record") || line.equals("replay");
            }
        } catch (Exception e) {
            Log.w(TAG, "isInputRecordArmed: getprop read failed: " + e);
        }
        return false;
    }

    @Override
    protected void onDestroy() {
        if (mGamepadPollHandler != null) {
            mGamepadPollHandler.removeCallbacksAndMessages(null);
            mGamepadPollHandler = null;
        }
        super.onDestroy();
    }
}
