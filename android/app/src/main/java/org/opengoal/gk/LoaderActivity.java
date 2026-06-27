// Phase Gpkg-distributable (autoport 2026-06-27): one-shot loader that
// DECOMPRESSES the APK-bundled, COMPRESSED runtime-asset archive into the
// app's private filesDir on first launch, then hands off to MainActivity.
//
// What changed vs the old phase-17 loader: the APK used to bundle the
// ~1.34 GiB runtime data as RAW, uncompressed files (assets/iso_data/<game>
// + assets/fr3) and this activity just COPIED them out. The owner's revised
// distributable design ships those assets as ONE DEFLATE zip
// (assets/bundle/<game>_assets.zip, built on PC by build_asset_bundle.sh)
// so the APK is smaller and the raw files aren't laid down until first run.
// This activity now streams that zip through java.util.zip.ZipInputStream
// and writes each entry to its on-device home.
//
// Requirements this satisfies (the loop never blocks the UI thread, never
// trusts a half-finished unpack):
//   1. a background worker thread (the UI thread would ANR after 5s),
//   2. a visible determinate progress BAR + status text,
//   3. a one-time, idempotent VERSION STAMP so later launches skip straight
//      to MainActivity in O(1); a new APK (bumped bundle version) forces a
//      clean re-decompress,
//   4. a low-storage pre-check (clear error instead of a half-unpack), and
//   5. integrity verification: ZipInputStream validates each entry's CRC32
//      as it streams, and we cross-check the final file count + byte total
//      against the manifest before writing the stamp.
//
// The stamp is written LAST, after every output file is fully closed. A
// SIGKILL / low-battery kill mid-unpack leaves the stamp absent; the next
// launch wipes the partial data and restarts — never boot off a half-unpack
// (a truncated DGO would crash the runtime far more confusingly).

package org.opengoal.gk;

import android.content.Intent;
import android.content.res.AssetManager;
import android.os.Bundle;
import android.os.StatFs;
import android.util.Log;
import android.view.Gravity;
import android.view.WindowManager;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.TextView;
import androidx.appcompat.app.AppCompatActivity;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.Properties;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

public class LoaderActivity extends AppCompatActivity {
    private static final String TAG = "opengoal-gk";

    // Single compressed archive + its manifest, both bundled under assets/bundle/.
    private static final String BUNDLE_DIR = "bundle";
    private static final String MANIFEST_ASSET = BUNDLE_DIR + "/manifest.properties";

    // The on-device version stamp. Its content is the bundle version; a
    // mismatch (new APK shipped a new payload) forces a clean re-decompress.
    private static final String STAMP_NAME = ".asset_bundle_stamp";

    private static final int COPY_BUFFER_BYTES = 256 * 1024;
    // Free-space safety margin over the raw uncompressed size.
    private static final double STORAGE_MARGIN = 1.05;

    private TextView status;
    private ProgressBar progress;
    private Thread worker;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        // An asleep phone aborts the unpack partway through, which then costs
        // the user another full decompress on next launch.
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);

        FrameLayout root = new FrameLayout(this);
        root.setBackgroundColor(0xFF101010);
        setContentView(root);

        LinearLayout col = new LinearLayout(this);
        col.setOrientation(LinearLayout.VERTICAL);
        col.setPadding(64, 48, 64, 48);
        FrameLayout.LayoutParams colLp = new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT);
        colLp.gravity = Gravity.CENTER;
        root.addView(col, colLp);

        status = new TextView(this);
        status.setText("Setting up game data…");
        status.setTextColor(0xFFE0E0E0);
        status.setTextSize(20);
        col.addView(status, new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT));

        progress = new ProgressBar(this, null,
                android.R.attr.progressBarStyleHorizontal);
        progress.setMax(1000);            // permille; smoother than 0..100
        progress.setProgress(0);
        progress.setIndeterminate(false);
        LinearLayout.LayoutParams pLp = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT);
        pLp.topMargin = 32;
        col.addView(progress, pLp);

        final String gameName = getString(R.string.game_name);
        Log.i(TAG, "LoaderActivity: first-run decompress check for " + gameName);

        worker = new Thread(() -> {
            try {
                unpackBundleIfNeeded(gameName);
                runOnUiThread(() -> {
                    startActivity(new Intent(LoaderActivity.this, MainActivity.class));
                    finish();
                });
            } catch (Throwable t) {
                Log.e(TAG, "LoaderActivity: asset setup failed", t);
                final String msg = "Setup failed:\n" + t.getMessage();
                runOnUiThread(() -> {
                    status.setText(msg);
                    progress.setIndeterminate(false);
                    progress.setProgress(0);
                });
            }
        }, "opengoal-loader");
        worker.start();
    }

    // --- bundle manifest -----------------------------------------------------

    private static final class Manifest {
        String version = "0";
        int fileCount = -1;
        long rawBytes = -1;
        String zipName = "";
    }

    private Manifest readManifest(String gameName) throws IOException {
        Manifest m = new Manifest();
        Properties p = new Properties();
        try (InputStream in = getAssets().open(MANIFEST_ASSET)) {
            p.load(in);
        }
        m.version = p.getProperty("version", "0");
        m.fileCount = Integer.parseInt(p.getProperty("file_count", "-1").trim());
        m.rawBytes = Long.parseLong(p.getProperty("raw_bytes", "-1").trim());
        m.zipName = BUNDLE_DIR + "/" + gameName + "_assets.zip";
        return m;
    }

    // --- the one-time, idempotent, version-stamped decompress ----------------

    private void unpackBundleIfNeeded(String gameName) throws IOException {
        Manifest mf = readManifest(gameName);
        File filesDir = getFilesDir();
        File stamp = new File(filesDir, STAMP_NAME);

        // Idempotent fast path: stamp present AND version matches → already
        // unpacked from this APK; boot straight through.
        if (stamp.isFile()) {
            String have = readStamp(stamp);
            if (mf.version.equals(have)) {
                Log.i(TAG, "asset bundle already unpacked (version=" + have
                        + ") — skipping decompress, data ready");
                return;
            }
            Log.w(TAG, "asset bundle version changed (" + have + " -> "
                    + mf.version + ") — re-decompressing");
        }

        // Targets this bundle owns. Wipe both (and the stale stamp) so a
        // version bump or an interrupted previous run never boots off mixed
        // or half-written data.
        File isoTarget = new File(filesDir, "iso_data/" + gameName);
        File fr3Target = new File(filesDir, "out/" + gameName + "/fr3");
        if (stamp.exists()) stamp.delete();
        deleteRecursive(isoTarget);
        deleteRecursive(fr3Target);

        // Low-storage pre-check: refuse with a clear message rather than
        // unpacking until the disk fills mid-write.
        if (mf.rawBytes > 0) {
            long need = (long) (mf.rawBytes * STORAGE_MARGIN);
            long avail = availableBytes(filesDir);
            if (avail < need) {
                throw new IOException("Not enough free storage. Need "
                        + humanBytes(need) + ", only " + humanBytes(avail)
                        + " free. Free up space and relaunch.");
            }
            Log.i(TAG, "storage ok: need " + humanBytes(need) + ", have "
                    + humanBytes(avail));
        }

        runOnUiThread(() -> status.setText("Decompressing game data…\n0%"));

        final long startMs = System.currentTimeMillis();
        long bytesWritten = 0;
        int filesWritten = 0;
        long lastUiUpdate = -1;
        byte[] buf = new byte[COPY_BUFFER_BYTES];

        AssetManager am = getAssets();
        // STREAMING access → the ~1 GiB archive is never materialised in RAM;
        // ZipInputStream inflates it entry-by-entry as we read.
        try (InputStream rawIn = am.open(mf.zipName, AssetManager.ACCESS_STREAMING);
             ZipInputStream zin = new ZipInputStream(rawIn)) {
            ZipEntry e;
            while ((e = zin.getNextEntry()) != null) {
                String name = e.getName();
                if (e.isDirectory()) {
                    zin.closeEntry();
                    continue;
                }
                // Map zip-relative entry → on-device home:
                //   fr3/<f>            -> out/<game>/fr3/<f>
                //   iso_data/<game>/<f> -> iso_data/<game>/<f>  (as-is)
                String rel = name.startsWith("fr3/")
                        ? ("out/" + gameName + "/" + name)
                        : name;
                File outFile = new File(filesDir, rel);
                // Defend against zip path traversal (../ entries).
                String canonRoot = filesDir.getCanonicalPath() + File.separator;
                if (!outFile.getCanonicalPath().startsWith(canonRoot)) {
                    throw new IOException("refusing unsafe bundle entry: " + name);
                }
                File parent = outFile.getParentFile();
                if (parent != null && !parent.isDirectory() && !parent.mkdirs()) {
                    throw new IOException("could not create " + parent.getAbsolutePath());
                }

                try (FileOutputStream out = new FileOutputStream(outFile)) {
                    int r;
                    while ((r = zin.read(buf)) > 0) {
                        out.write(buf, 0, r);
                        bytesWritten += r;
                    }
                }
                // closeEntry() validates the entry's CRC32 against the zip's
                // stored value — a corrupt/truncated archive throws here.
                zin.closeEntry();
                filesWritten++;

                // Throttle UI updates to ~each permille so we don't flood the
                // main-thread looper on 300+ small files.
                long permille = mf.rawBytes > 0
                        ? Math.min(1000, (bytesWritten * 1000) / mf.rawBytes)
                        : 0;
                if (permille != lastUiUpdate) {
                    lastUiUpdate = permille;
                    final int pm = (int) permille;
                    final long shown = bytesWritten;
                    runOnUiThread(() -> {
                        progress.setProgress(pm);
                        status.setText("Decompressing game data…\n"
                                + (pm / 10) + "%   " + humanBytes(shown));
                    });
                }
            }
        }

        // Integrity: cross-check what we actually wrote against the manifest.
        // CRC was already verified per entry; this catches a short/extra
        // archive or a truncated stream the CRC pass alone wouldn't.
        if (mf.fileCount >= 0 && filesWritten != mf.fileCount) {
            throw new IOException("integrity check failed: unpacked "
                    + filesWritten + " files, manifest expects " + mf.fileCount);
        }
        if (mf.rawBytes >= 0 && bytesWritten != mf.rawBytes) {
            throw new IOException("integrity check failed: unpacked "
                    + bytesWritten + " bytes, manifest expects " + mf.rawBytes);
        }

        // Stamp LAST: only a fully-verified unpack is trusted on next launch.
        writeStamp(stamp, mf.version);

        long elapsedMs = System.currentTimeMillis() - startMs;
        Log.i(TAG, "asset bundle decompressed: " + filesWritten + " files, "
                + bytesWritten + " bytes in " + elapsedMs + "ms (version="
                + mf.version + ")");
        runOnUiThread(() -> {
            progress.setProgress(1000);
            status.setText("Setup complete — starting game…");
        });
    }

    // --- helpers -------------------------------------------------------------

    private static String readStamp(File stamp) {
        try (InputStream in = new java.io.FileInputStream(stamp)) {
            byte[] b = new byte[64];
            int n = in.read(b);
            return n > 0 ? new String(b, 0, n).trim() : "";
        } catch (IOException e) {
            return "";
        }
    }

    private static void writeStamp(File stamp, String version) throws IOException {
        try (FileOutputStream out = new FileOutputStream(stamp)) {
            out.write(version.getBytes());
        }
    }

    private static long availableBytes(File dir) {
        try {
            StatFs s = new StatFs(dir.getAbsolutePath());
            return s.getAvailableBytes();
        } catch (Throwable t) {
            // If we can't stat, don't block the unpack on a false negative.
            return Long.MAX_VALUE;
        }
    }

    private static void deleteRecursive(File f) {
        if (f == null || !f.exists()) return;
        if (f.isDirectory()) {
            File[] kids = f.listFiles();
            if (kids != null) {
                for (File k : kids) deleteRecursive(k);
            }
        }
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
