// supervisor-diag DIAG2 (autoport 2026-07-08): bulletproof export of the jak2
// remote-diagnostic breadcrumb/crash files out of the app's private external
// files dir into the PUBLIC Downloads collection, so the owner (HONOR phone, no
// adb, logcat suppressed) can read them from a stock file manager.
//
// Why a static helper instead of the old LoaderActivity-only inline copy:
//   The previous build exported only from LoaderActivity.onCreate. When Android
//   resumes the app from recents it re-enters MainActivity directly and
//   LoaderActivity never re-runs, so the single-shot copy never fired and the
//   owner saw NO file in Downloads. This helper is called from BOTH activities
//   (LoaderActivity.onCreate, MainActivity.onCreate + onPause) AND on a 60s
//   periodic timer while the game runs, so data lands in Downloads no matter how
//   the process is entered or left.
//
// Contract: every public method is best-effort and NEVER throws. On ANY
// exception the full stack is Log.e'd AND appended to files/jak2_diag_export_err.txt
// (external files dir) so a failure is itself visible in the next export. jak1 is
// untouched: callers gate on the selected game, and the source files only exist
// for a jak2 diag libgk anyway.

package org.opengoal.gk;

import android.content.ContentResolver;
import android.content.ContentValues;
import android.content.Context;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.provider.MediaStore;
import android.util.Log;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.FileWriter;
import java.io.InputStream;
import java.io.OutputStream;
import java.io.PrintWriter;
import java.text.SimpleDateFormat;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Date;
import java.util.Deque;
import java.util.List;
import java.util.Locale;

public final class DiagExporter {
    private static final String TAG = "opengoal-gk";

    // Source files the jak2 diag libgk / LoaderActivity write into the app's
    // EXTERNAL files dir (getExternalFilesDir(null)).
    private static final String[] SRC_NAMES = { "jak2_diag.txt", "jak2_crash.txt" };
    private static final String ERR_NAME = "jak2_diag_export_err.txt";
    private static final long ERR_CAP_BYTES = 256L * 1024L;

    // Periodic exporter: at most one snapshot per this interval, and only the N
    // most recent periodic files this session are kept (older session-created
    // ones are deleted so Downloads doesn't fill with hundreds of snapshots).
    public static final long PERIODIC_INTERVAL_MS = 60_000L;
    private static final int PERIODIC_KEEP = 3;

    // Session state (process-lifetime). Guarded by the class monitor.
    private static long sLastPeriodicMs = 0L;
    private static boolean sToastShown = false;
    // MediaStore Uris of periodic snapshots this session created, oldest first,
    // so we can delete the oldest when we exceed PERIODIC_KEEP.
    private static final Deque<Uri> sPeriodicUris = new ArrayDeque<>();

    private DiagExporter() {}

    private static File externalDiagDir(Context ctx) {
        try {
            return ctx.getExternalFilesDir(null);
        } catch (Throwable t) {
            return null;
        }
    }

    private static String timestamp() {
        return new SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US).format(new Date());
    }

    // Append a full exception breadcrumb to files/jak2_diag_export_err.txt so a
    // silent export failure is visible on the NEXT export. Never throws.
    private static void recordError(Context ctx, String where, Throwable t) {
        try {
            Log.e(TAG, "DiagExporter " + where + " failed", t);
        } catch (Throwable ignore) {}
        try {
            File dir = externalDiagDir(ctx);
            if (dir == null) return;
            File f = new File(dir, ERR_NAME);
            // Rotate if it grew huge.
            boolean append = !(f.isFile() && f.length() > ERR_CAP_BYTES);
            StringBuilder sb = new StringBuilder();
            sb.append("[").append(timestamp()).append("] ").append(where).append(": ");
            sb.append(t == null ? "null" : t.toString()).append("\n");
            if (t != null) {
                ByteArrayOutputStream bos = new ByteArrayOutputStream();
                PrintWriter pw = new PrintWriter(bos);
                t.printStackTrace(pw);
                pw.flush();
                sb.append(bos.toString()).append("\n");
            }
            try (FileWriter w = new FileWriter(f, append)) {
                w.write(sb.toString());
            }
        } catch (Throwable ignore) {
            // best-effort; swallow
        }
    }

    /**
     * ONE-SHOT export used at launch (LoaderActivity.onCreate, MainActivity.onCreate)
     * and on backgrounding (MainActivity.onPause). Copies any present jak2 diag/crash
     * file into Downloads as jak2-diag-<ts>.txt / jak2-crash-<ts>.txt.
     *
     * The source is NOT consumed here (unlike the old .sent rename) so the periodic
     * exporter and later launches keep seeing the growing breadcrumb. To avoid an
     * unbounded pile of near-identical Downloads files across many onCreate/onPause
     * cycles, the export is throttled to at most one snapshot per PERIODIC_INTERVAL_MS
     * (shared with the periodic timer). A crash file forces an export regardless of
     * throttle, since it is high-value and written at most once.
     *
     * A success toast is shown at most once per session. Never throws.
     */
    public static void exportNow(Context ctx, String reason) {
        exportInternal(ctx, reason, /*periodicRotate=*/false, /*forceIfCrash=*/true);
    }

    /**
     * PERIODIC export used by MainActivity's 60s Handler. Same copy-out, but keeps
     * only the PERIODIC_KEEP most recent snapshots this session created (deletes the
     * oldest MediaStore entries) so Downloads doesn't accumulate a snapshot per
     * minute over a long play session. Never throws.
     */
    public static void exportPeriodic(Context ctx) {
        exportInternal(ctx, "periodic", /*periodicRotate=*/true, /*forceIfCrash=*/false);
    }

    private static synchronized void exportInternal(Context ctx, String reason,
                                                    boolean periodicRotate,
                                                    boolean forceIfCrash) {
        try {
            if (ctx == null) return;
            File dir = externalDiagDir(ctx);
            if (dir == null) return;

            // Is there anything worth exporting at all?
            File crash = new File(dir, "jak2_crash.txt");
            boolean haveCrash = crash.isFile() && crash.length() > 0;

            long now = System.currentTimeMillis();
            boolean throttled = (now - sLastPeriodicMs) < PERIODIC_INTERVAL_MS;
            // A crash file always exports on a one-shot call even inside the throttle
            // window; periodic + throttled non-crash calls are skipped.
            if (throttled && !(forceIfCrash && haveCrash)) {
                return;
            }

            String ts = timestamp();
            boolean anyExported = false;
            for (String name : SRC_NAMES) {
                File src = new File(dir, name);
                if (!src.isFile() || src.length() == 0) continue;
                String base = name.equals("jak2_crash.txt") ? "jak2-crash-" : "jak2-diag-";
                String outName = base + ts + ".txt";
                Uri exported = exportOneToDownloads(ctx, src, outName);
                if (exported != null) {
                    anyExported = true;
                    if (periodicRotate) {
                        sPeriodicUris.addLast(exported);
                        rotatePeriodic(ctx);
                    }
                }
            }

            if (anyExported) {
                sLastPeriodicMs = now;
                maybeToast(ctx);
            }
        } catch (Throwable t) {
            recordError(ctx, "exportInternal(" + reason + ")", t);
        }
    }

    // Keep only the PERIODIC_KEEP most recent periodic snapshots this session
    // created; delete the older MediaStore rows. Caller holds the monitor.
    private static void rotatePeriodic(Context ctx) {
        try {
            while (sPeriodicUris.size() > PERIODIC_KEEP) {
                Uri old = sPeriodicUris.pollFirst();
                if (old == null) break;
                try {
                    ctx.getContentResolver().delete(old, null, null);
                    Log.i(TAG, "DiagExporter: rotated out old periodic snapshot " + old);
                } catch (Throwable t) {
                    // If the delete fails (user moved the file, etc.), drop the ref
                    // and move on — we already removed it from the deque.
                    recordError(ctx, "rotatePeriodic.delete", t);
                }
            }
        } catch (Throwable t) {
            recordError(ctx, "rotatePeriodic", t);
        }
    }

    private static void maybeToast(Context ctx) {
        if (sToastShown) return;
        sToastShown = true;
        try {
            // Toast must run on the main looper; post it there. Best-effort.
            final Context appCtx = ctx.getApplicationContext();
            new android.os.Handler(android.os.Looper.getMainLooper()).post(() -> {
                try {
                    android.widget.Toast.makeText(appCtx,
                            "diag exporté dans Downloads",
                            android.widget.Toast.LENGTH_LONG).show();
                } catch (Throwable ignore) {}
            });
        } catch (Throwable t) {
            recordError(ctx, "maybeToast", t);
        }
    }

    // Insert one file into MediaStore.Downloads (API 29+) and stream the bytes in.
    // Returns the created content Uri on success (so the periodic path can rotate
    // it out later), else null. Pre-Q falls back to a direct copy into the public
    // Downloads dir and returns a file:// Uri that delete() below no-ops on. Never
    // throws (records the error and returns null).
    private static Uri exportOneToDownloads(Context ctx, File src, String outName) {
        try {
            ContentResolver cr = ctx.getContentResolver();
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ContentValues cv = new ContentValues();
                cv.put(MediaStore.Downloads.DISPLAY_NAME, outName);
                cv.put(MediaStore.Downloads.MIME_TYPE, "text/plain");
                cv.put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS);
                cv.put(MediaStore.Downloads.IS_PENDING, 1);
                Uri collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI;
                Uri item = cr.insert(collection, cv);
                if (item == null) return null;
                try (InputStream in = new FileInputStream(src);
                     OutputStream out = cr.openOutputStream(item)) {
                    if (out == null) {
                        cr.delete(item, null, null);
                        return null;
                    }
                    byte[] buf = new byte[64 * 1024];
                    int r;
                    while ((r = in.read(buf)) > 0) out.write(buf, 0, r);
                }
                cv.clear();
                cv.put(MediaStore.Downloads.IS_PENDING, 0);
                cr.update(item, cv, null, null);
                Log.i(TAG, "DiagExporter: exported " + src.getName()
                        + " -> Downloads/" + outName);
                return item;
            } else {
                File dl = Environment.getExternalStoragePublicDirectory(
                        Environment.DIRECTORY_DOWNLOADS);
                if (dl != null && (dl.isDirectory() || dl.mkdirs())) {
                    File out = new File(dl, outName);
                    try (InputStream in = new FileInputStream(src);
                         OutputStream os = new FileOutputStream(out)) {
                        byte[] buf = new byte[64 * 1024];
                        int r;
                        while ((r = in.read(buf)) > 0) os.write(buf, 0, r);
                    }
                    Log.i(TAG, "DiagExporter: exported " + src.getName()
                            + " -> " + out.getAbsolutePath());
                    return Uri.fromFile(out);
                }
                return null;
            }
        } catch (Throwable t) {
            recordError(ctx, "exportOneToDownloads(" + outName + ")", t);
            return null;
        }
    }
}
