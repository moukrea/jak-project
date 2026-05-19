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
//      Phase 18 keeps gk_sdl_main minimal (SDL_Init → window → context →
//      clear/swap loop). Phase 19 replaces it with the real GOAL boot.
//
// The TouchControlsView overlay is preserved by adding it to mLayout
// after super.onCreate completes.

package org.opengoal.gk;

import android.os.Bundle;
import android.util.Log;
import android.view.ViewGroup;
import android.widget.FrameLayout;

import org.libsdl.app.SDLActivity;

import java.io.File;

public class MainActivity extends SDLActivity {
    private static final String TAG = "opengoal-gk";
    private static final String ISO_DATA_SUBDIR = "iso_data";

    private TouchControlsView controls;

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

    @Override
    protected String[] getArguments() {
        // Pass the per-flavor game name and the absolute iso_data dir as
        // argv to gk_sdl_main. Phase 19 will consume these; phase 18 just
        // logs them.
        final String gameName = getString(R.string.game_name);
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
        final String gameName = getString(R.string.game_name);
        final File isoDir = new File(getFilesDir(), ISO_DATA_SUBDIR + "/" + gameName);
        NativeGk.setSelectedGame(gameName);
        NativeGk.setDataRoot(isoDir.getAbsolutePath());

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

        // Overlay the touch controls on top of SDLActivity's mLayout (a
        // RelativeLayout that already holds the SDLSurface). Phase 23
        // wires the overlay through NativeGk.onPadButton — the SDLSurface
        // would otherwise consume every touch via its own onTouch listener.
        // bringToFront + elevation force the overlay above the SDLSurface
        // even though both children of mLayout are MATCH_PARENT; without
        // this, RelativeLayout's child ordering and the SurfaceView's
        // hardware-layer compositing can still steal touches.
        controls = new TouchControlsView(this);
        if (mLayout != null) {
            ViewGroup.LayoutParams lp = new FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT);
            mLayout.addView(controls, lp);
            controls.bringToFront();
            controls.setElevation(100f);
        }

        Log.i(TAG, "MainActivity onCreate done; controls=" + (controls != null)
                + " mLayout=" + (mLayout != null)
                + " mLayout.children=" + (mLayout != null ? mLayout.getChildCount() : -1));
    }
}
