// Phase 11 (autoport): launcher activity for the OpenGOAL Android shell.
//
// Two responsibilities right now:
//   1. Load libgk.so and surface a smoke-test log line ("target started"
//      / version banner) so the phase-11 emulator validator can detect a
//      successful boot.
//   2. Check that the user-supplied PS2 ISO extract is present and warn
//      via a Toast if it isn't. The activity does *not* copy data —
//      players drop their files into the app-private external dir via
//      adb push or a file manager:
//        /sdcard/Android/data/org.opengoal.gk/files/iso_data/
//
// A touch-controls overlay (TouchControlsView) is inflated on top of
// the main content view to prove the input plumbing works; the joystick
// and four buttons currently just log their events. Real input wiring
// happens once SDL2 is fully integrated.

package org.opengoal.gk;

import android.os.Bundle;
import android.util.Log;
import android.widget.FrameLayout;
import android.widget.TextView;
import android.widget.Toast;
import androidx.appcompat.app.AppCompatActivity;

import java.io.File;

public class MainActivity extends AppCompatActivity {
    private static final String TAG = "opengoal-gk";
    private static final String ISO_DATA_SUBDIR = "iso_data";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        FrameLayout root = new FrameLayout(this);
        setContentView(root);

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

        // Overlay the touch controls stub on top of the banner.
        TouchControlsView controls = new TouchControlsView(this);
        root.addView(controls);

        // Phase-11 acceptance signal — keep this line stable so the
        // validator's `adb logcat | grep "target started"` matches.
        Log.i(TAG, "target started: " + version);

        File isoDir = new File(getExternalFilesDir(null), ISO_DATA_SUBDIR);
        if (!isoDir.isDirectory() || isoDir.list() == null || isoDir.list().length == 0) {
            String msg = "Missing game data. Copy your PS2 ISO extract to:\n"
                       + isoDir.getAbsolutePath();
            Log.w(TAG, msg);
            Toast.makeText(this, msg, Toast.LENGTH_LONG).show();
        } else {
            Log.i(TAG, "iso_data present at " + isoDir.getAbsolutePath());
        }
    }
}
