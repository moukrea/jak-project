// Phase E3 (autoport): dedicated activity that drives the kmemcard
// deterministic save writer without booting the SDL/GLES runtime.
//
// The phase-E3 contract is byte-identity between an Android-produced
// save and the desktop x86_64 reference. Producing the save through
// the full SDLActivity boot would cost ~100 s of cold extraction +
// IOP + dispatcher startup, none of which exercises kmemcard. This
// activity short-circuits that: it loads libgk.so via the NativeGk
// static initializer, invokes writeTestSave(path), emits the
// `test save written: <path>` marker the e3_run.sh harness greps,
// and finishes.
//
// The activity itself has no UI — it sets a black background just so
// the launcher doesn't render the previous activity behind it during
// the millisecond before finish().

package org.opengoal.gk;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.util.Log;
import android.view.WindowManager;
import android.widget.FrameLayout;

import java.io.File;

public class SaveActivity extends Activity {
    private static final String TAG = "opengoal-gk";

    // The Intent extra the e3_run.sh harness sets to the absolute path
    // where the deterministic save should be written. Read on every
    // onCreate so a re-launch (without finishing the previous one) writes
    // again to the same path — idempotent because the bytes are fixed.
    public static final String EXTRA_SAVE_PATH = "writeTestSaveTo";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        // Visual: solid black, no widgets. The activity is on screen for
        // only a few milliseconds before finish().
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        FrameLayout root = new FrameLayout(this);
        root.setBackgroundColor(0xFF000000);
        setContentView(root);

        Intent intent = getIntent();
        String path = intent != null ? intent.getStringExtra(EXTRA_SAVE_PATH) : null;
        if (path == null || path.isEmpty()) {
            // Fallback to a default inside filesDir so a manual `am start
            // -n ... .SaveActivity` (no extra) still produces an artefact.
            File savesDir = new File(getFilesDir(), "saves");
            //noinspection ResultOfMethodCallIgnored
            savesDir.mkdirs();
            path = new File(savesDir, "E3-android-save.bin").getAbsolutePath();
            Log.w(TAG, "SaveActivity: no " + EXTRA_SAVE_PATH
                    + " extra; defaulting to " + path);
        }

        // Make sure the parent dir exists — writeTestSave does the same
        // via file_util::create_dir_if_needed_for_file but a Java-side
        // mkdirs() means we can read back the path immediately even on
        // a filesystem layout glitch.
        File f = new File(path);
        File parent = f.getParentFile();
        if (parent != null && !parent.isDirectory()) {
            //noinspection ResultOfMethodCallIgnored
            parent.mkdirs();
        }

        int rc;
        try {
            rc = NativeGk.writeTestSave(path);
        } catch (UnsatisfiedLinkError e) {
            Log.e(TAG, "SaveActivity: libgk.so missing JNI writeTestSave", e);
            rc = -1;
        }

        if (rc == 0) {
            // The native side already logs `test save written: <path>`.
            // This redundant Java-side log makes the activity-level
            // completion visible separately from the JNI marker.
            Log.i(TAG, "SaveActivity: writeTestSave returned 0, file=" + path
                    + " size=" + f.length());
        } else {
            Log.e(TAG, "SaveActivity: writeTestSave returned " + rc
                    + " for path=" + path);
        }

        finish();
    }
}
