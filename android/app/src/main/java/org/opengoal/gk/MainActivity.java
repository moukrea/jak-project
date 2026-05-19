// Phase 13 (autoport): launcher activity for the OpenGOAL Android shell.
//
// Responsibilities:
//   1. Lay out a SurfaceView (the eventual SDL render target) with the
//      TouchControlsView overlay above it.
//   2. Resolve the per-flavor game name from R.string.game_name and
//      kick off NativeGk.startGame(name, dataRoot) on a background
//      thread so the activity stays responsive while the runtime boots.
//   3. Forward Activity lifecycle events that the SDL runtime cares
//      about (onPause/onResume) into the native side.
//
// The game name is *not* baked into native code. It comes from the
// per-flavor resValue() defined in app/build.gradle.kts so the jak1/
// jak2/jak3 APK variants each ship with the right selection.

package org.opengoal.gk;

import android.os.Bundle;
import android.util.Log;
import android.view.MotionEvent;
import android.view.SurfaceHolder;
import android.view.SurfaceView;
import android.widget.FrameLayout;
import android.widget.TextView;
import android.widget.Toast;
import androidx.appcompat.app.AppCompatActivity;

import java.io.File;

public class MainActivity extends AppCompatActivity {
    private static final String TAG = "opengoal-gk";
    private static final String ISO_DATA_SUBDIR = "iso_data";

    private SurfaceView surface;
    private TouchControlsView controls;
    private Thread runtimeThread;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        FrameLayout root = new FrameLayout(this);
        setContentView(root);

        // SDL renders onto this surface in phase 14+. Today we just keep
        // it in the tree so the layout matches the final activity shape
        // and we can attach a SurfaceHolder.Callback that proxies
        // surfaceCreated/Destroyed into the runtime later.
        surface = new SurfaceView(this);
        surface.getHolder().addCallback(new SurfaceHolder.Callback() {
            @Override public void surfaceCreated(SurfaceHolder h) {
                Log.i(TAG, "surface created: " + h.getSurfaceFrame());
            }
            @Override public void surfaceChanged(SurfaceHolder h, int f, int w, int hgt) {
                Log.i(TAG, "surface changed: " + w + "x" + hgt + " fmt=" + f);
            }
            @Override public void surfaceDestroyed(SurfaceHolder h) {
                Log.i(TAG, "surface destroyed");
            }
        });
        root.addView(surface,
                new FrameLayout.LayoutParams(
                        FrameLayout.LayoutParams.MATCH_PARENT,
                        FrameLayout.LayoutParams.MATCH_PARENT));

        TextView banner = new TextView(this);
        String version;
        try {
            version = NativeGk.version();
        } catch (UnsatisfiedLinkError | RuntimeException e) {
            version = "libgk.so: load failed (" + e.getMessage() + ")";
        }
        banner.setText(version);
        banner.setPadding(48, 48, 48, 48);
        root.addView(banner);

        controls = new TouchControlsView(this);
        root.addView(controls,
                new FrameLayout.LayoutParams(
                        FrameLayout.LayoutParams.MATCH_PARENT,
                        FrameLayout.LayoutParams.MATCH_PARENT));

        // Keep the existing logcat acceptance signal stable for the
        // phase-11/13 emulator smoke tests.
        Log.i(TAG, "target started: " + version);

        final String gameName = getString(R.string.game_name);
        final File isoDir = new File(getFilesDir(), ISO_DATA_SUBDIR + "/" + gameName);
        if (!isoDir.isDirectory() || isoDir.list() == null || isoDir.list().length == 0) {
            String msg = "Missing " + gameName + " data. Copy your PS2 ISO extract to:\n"
                       + isoDir.getAbsolutePath();
            Log.w(TAG, msg);
            Toast.makeText(this, msg, Toast.LENGTH_LONG).show();
        } else {
            Log.i(TAG, gameName + " iso_data present at " + isoDir.getAbsolutePath());
        }

        // Phase 13: the runtime boot is non-blocking. Even when phase 14+
        // makes startGame() block on a real game loop, the Activity stays
        // free to dispatch input/lifecycle events.
        runtimeThread = new Thread(() -> {
            Log.i(TAG, "runtime thread: starting " + gameName);
            int rc = NativeGk.startGame(gameName, isoDir.getAbsolutePath());
            Log.i(TAG, "runtime thread: startGame returned " + rc);
        }, "opengoal-runtime");
        runtimeThread.setDaemon(true);
        runtimeThread.start();
    }

    @Override
    public boolean dispatchTouchEvent(MotionEvent ev) {
        // Let the overlay handle gameplay-style input first; also forward
        // every event to the native side so the runtime sees raw touches.
        try {
            NativeGk.onTouchEvent((int) ev.getX(), (int) ev.getY(), ev.getActionMasked());
        } catch (UnsatisfiedLinkError ignored) {
            // Native onTouchEvent not yet linked into this build of libgk.so.
        }
        return super.dispatchTouchEvent(ev);
    }

    @Override
    protected void onPause() {
        super.onPause();
        Log.i(TAG, "activity paused");
        // SDL's lifecycle: nativePause() would go here in phase 14+.
    }

    @Override
    protected void onResume() {
        super.onResume();
        Log.i(TAG, "activity resumed");
        // SDL's lifecycle: nativeResume() would go here in phase 14+.
    }
}
