// Phase 17 (autoport): one-shot loader that extracts the APK-bundled
// iso_data into the app's private filesDir on first launch, then hands
// off to MainActivity.
//
// Why a dedicated activity? The extraction copies ~1.4 GB on jak1, which
// takes tens of seconds on eMMC. We need:
//   1. a background thread (UI thread would ANR after 5s),
//   2. a visible progress UI so the user knows the app is alive,
//   3. an idempotent sentinel so subsequent launches skip straight to
//      MainActivity in O(1).
//
// The sentinel is written *last*, after every file in the target dir is
// fully closed. A SIGKILL mid-copy leaves the sentinel absent; the next
// launch will see a non-empty target dir without sentinel, wipe it, and
// restart from scratch — never trust a half-finished copy.

package org.opengoal.gk;

import android.content.Intent;
import android.content.res.AssetManager;
import android.os.Bundle;
import android.util.Log;
import android.view.Gravity;
import android.view.WindowManager;
import android.widget.FrameLayout;
import android.widget.TextView;
import androidx.appcompat.app.AppCompatActivity;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;

public class LoaderActivity extends AppCompatActivity {
    private static final String TAG = "opengoal-gk";
    private static final String ISO_DATA_SUBDIR = "iso_data";
    private static final String SENTINEL_NAME = ".extracted_v1";
    private static final int COPY_BUFFER_BYTES = 256 * 1024;

    private TextView status;
    private Thread worker;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        // An asleep phone aborts the copy partway through, which then
        // costs the user another full extraction on next launch.
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);

        FrameLayout root = new FrameLayout(this);
        root.setBackgroundColor(0xFF101010);
        setContentView(root);

        status = new TextView(this);
        status.setText("Preparing game data…");
        status.setTextColor(0xFFE0E0E0);
        status.setTextSize(20);
        status.setPadding(48, 48, 48, 48);
        FrameLayout.LayoutParams lp = new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT);
        lp.gravity = Gravity.CENTER;
        root.addView(status, lp);

        final String gameName = getString(R.string.game_name);
        Log.i(TAG, "LoaderActivity: starting extraction check for " + gameName);

        worker = new Thread(() -> {
            try {
                extractIfMissing(gameName);
                extractFr3IfMissing(gameName);
                runOnUiThread(() -> {
                    startActivity(new Intent(LoaderActivity.this, MainActivity.class));
                    finish();
                });
            } catch (Throwable t) {
                Log.e(TAG, "LoaderActivity: extraction failed", t);
                final String msg = "Extraction failed: " + t.getClass().getSimpleName()
                                 + ": " + t.getMessage();
                runOnUiThread(() -> status.setText(msg));
            }
        }, "opengoal-loader");
        worker.start();
    }

    private void extractIfMissing(String gameName) throws IOException {
        File target = new File(getFilesDir(), ISO_DATA_SUBDIR + "/" + gameName);
        File sentinel = new File(target, SENTINEL_NAME);

        if (sentinel.isFile()) {
            Log.i(TAG, "iso_data already extracted");
            return;
        }

        // Sentinel absent but target dir has stuff in it → previous attempt
        // was interrupted. Wipe and start over; trusting a half-copy will
        // hand the runtime corrupted files and the failure mode (DGO load
        // crash) is far worse than re-copying 1.4 GB.
        if (target.exists()) {
            Log.w(TAG, "iso_data target exists without sentinel — wiping partial copy at "
                    + target.getAbsolutePath());
            deleteRecursive(target);
        }
        if (!target.mkdirs() && !target.isDirectory()) {
            throw new IOException("could not create " + target.getAbsolutePath());
        }

        AssetManager am = getAssets();
        String assetDir = ISO_DATA_SUBDIR + "/" + gameName;
        String[] entries = am.list(assetDir);
        if (entries == null || entries.length == 0) {
            throw new IOException("no APK assets at " + assetDir
                    + " — build did not bundle iso_data for " + gameName);
        }

        final int total = entries.length;
        final long startMs = System.currentTimeMillis();
        long bytesCopied = 0;
        byte[] buf = new byte[COPY_BUFFER_BYTES];

        for (int i = 0; i < total; i++) {
            String name = entries[i];
            File outFile = new File(target, name);
            long thisBytes;
            try (InputStream in = am.open(assetDir + "/" + name, AssetManager.ACCESS_STREAMING);
                 FileOutputStream out = new FileOutputStream(outFile)) {
                long n = 0;
                int r;
                while ((r = in.read(buf)) > 0) {
                    out.write(buf, 0, r);
                    n += r;
                }
                thisBytes = n;
            }
            bytesCopied += thisBytes;

            final int idx = i + 1;
            final long shown = bytesCopied;
            final String label = name;
            runOnUiThread(() -> status.setText(
                    "Preparing game data… " + idx + " / " + total
                            + "\n" + label
                            + "\n" + humanBytes(shown)));
        }

        long elapsedMs = System.currentTimeMillis() - startMs;
        // The sentinel must be the LAST thing we touch. If the process
        // dies before this line runs, the next launch will treat the
        // partial copy as garbage and start over.
        new FileOutputStream(sentinel).close();
        Log.i(TAG, "iso_data extract: " + total + " files, " + bytesCopied
                + " bytes in " + elapsedMs + "ms");
    }

    // Phase A35 (autoport): the renderer's texture loader reads fr3 level
    // files from <filesDir>/out/<game>/fr3/ (the synthetic project root
    // android_goal_main.cpp sets up). Independent sentinel so adding fr3s
    // to an APK never forces a re-copy of the ~1.4 GB iso_data.
    private void extractFr3IfMissing(String gameName) throws IOException {
        File target = new File(getFilesDir(), "out/" + gameName + "/fr3");
        File sentinel = new File(target, ".extracted_fr3_v1");

        AssetManager am = getAssets();
        String[] entries = am.list("fr3");
        if (entries == null || entries.length == 0) {
            Log.i(TAG, "fr3 extract: no fr3 assets bundled — renderer will use "
                    + "placeholder textures");
            return;
        }

        if (sentinel.isFile()) {
            Log.i(TAG, "fr3 already extracted");
            return;
        }
        if (target.exists()) {
            Log.w(TAG, "fr3 target exists without sentinel — wiping partial copy at "
                    + target.getAbsolutePath());
            deleteRecursive(target);
        }
        if (!target.mkdirs() && !target.isDirectory()) {
            throw new IOException("could not create " + target.getAbsolutePath());
        }

        long bytesCopied = 0;
        byte[] buf = new byte[COPY_BUFFER_BYTES];
        for (String name : entries) {
            File outFile = new File(target, name);
            try (InputStream in = am.open("fr3/" + name, AssetManager.ACCESS_STREAMING);
                 FileOutputStream out = new FileOutputStream(outFile)) {
                int r;
                while ((r = in.read(buf)) > 0) {
                    out.write(buf, 0, r);
                    bytesCopied += r;
                }
            }
        }
        new FileOutputStream(sentinel).close();
        Log.i(TAG, "fr3 extract: " + entries.length + " files, " + bytesCopied + " bytes");
    }

    private static void deleteRecursive(File f) {
        if (f.isDirectory()) {
            File[] kids = f.listFiles();
            if (kids != null) {
                for (File k : kids) deleteRecursive(k);
            }
        }
        // Best-effort; if delete() fails we'll surface it later when
        // mkdirs() or the next write does.
        if (!f.delete() && f.exists()) {
            Log.w(TAG, "failed to delete " + f.getAbsolutePath());
        }
    }

    private static String humanBytes(long b) {
        if (b < 1024) return b + " B";
        if (b < 1024L * 1024) return String.format("%.1f KB", b / 1024.0);
        if (b < 1024L * 1024 * 1024) return String.format("%.1f MB", b / (1024.0 * 1024));
        return String.format("%.2f GB", b / (1024.0 * 1024 * 1024));
    }
}
