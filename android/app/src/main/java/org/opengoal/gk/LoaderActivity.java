// Phase Glauncher-collection (autoport 2026-07-02): the launcher entry point.
// It decides — from which per-game asset bundles are present — whether this APK
// is a SINGLE-game build or a COLLECTION, then either boots straight into the one
// game or shows a selection menu, and finally DECOMPRESSES the chosen game's
// bundled asset archive into the app's private filesDir before handing off to
// MainActivity.
//
// ASSET-DRIVEN mode (mirrors build.gradle.kts detectBundledGames):
//   - The set of games == the `<game>_assets.zip` archives under assets/bundle/.
//   - EXACTLY ONE game  -> NO menu; unpack it and boot straight into the game.
//   - MORE THAN ONE     -> a selection menu (text rows, usable by TOUCH and by
//                          GAMEPAD/D-pad); pick one -> unpack -> boot it.
//   - A debug override (getprop debug.opengoal.games=jak1,jak2) lets a build
//     that physically bundles one game still exercise the collection menu on a
//     real device (dry-run) without shipping a 2nd game. Games listed in the
//     override but with no bundled archive are shown but reported "not included".
//
// The DECOMPRESS half is unchanged from Gpkg-distributable except that it is now
// per-game: manifest/zip/version-stamp are all keyed by game, so multiple games'
// data can coexist in filesDir. jak1 keeps its legacy stamp name so an existing
// jak1 install is NOT forced to re-decompress on upgrade.
//
// Correctness guarantees preserved: background worker thread (no ANR), a visible
// determinate progress bar, an idempotent version stamp, a low-storage precheck,
// per-entry CRC32 + file-count/byte-total integrity, and the stamp written LAST
// so a SIGKILL mid-unpack never boots off a half-written data set.

package org.opengoal.gk;

import android.content.Intent;
import android.content.res.AssetManager;
import android.graphics.Color;
import android.os.Bundle;
import android.os.StatFs;
import android.util.Log;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.View;
import android.view.WindowManager;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.TextView;
import android.widget.Toast;
import androidx.appcompat.app.AppCompatActivity;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Properties;
import java.util.TreeSet;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

public class LoaderActivity extends AppCompatActivity {
    private static final String TAG = "opengoal-gk";

    // Compressed archives + manifests live under assets/bundle/.
    private static final String BUNDLE_DIR = "bundle";
    private static final String ZIP_SUFFIX = "_assets.zip";

    private static final int COPY_BUFFER_BYTES = 256 * 1024;
    // Free-space safety margin over the raw uncompressed size.
    private static final double STORAGE_MARGIN = 1.05;

    // Human-facing titles for the collection menu + single-game label. Keep in
    // sync with build.gradle.kts gameTitles / appLabelFor.
    private static final Map<String, String> GAME_TITLES = new LinkedHashMap<>();
    static {
        GAME_TITLES.put("jak1", "Jak & Daxter");
        GAME_TITLES.put("jak2", "Jak II");
        GAME_TITLES.put("jak3", "Jak 3");
        GAME_TITLES.put("jakx", "Jak X");
    }
    private static final String COLLECTION_TITLE =
            "Jak and Daxter: The Recharged Jak-pot";

    // Palette (matches the placeholder launcher icon).
    private static final int COL_BG        = 0xFF101820;
    private static final int COL_TEXT      = 0xFFE6ECF2;
    private static final int COL_DIM       = 0xFF9FB0C0;
    private static final int COL_GOLD      = 0xFFF4C542;
    private static final int COL_ROW_SEL   = 0xFF1E7A5A; // eco teal
    private static final int COL_ROW_IDLE  = 0x00000000;

    private TextView status;
    private ProgressBar progress;
    private Thread worker;

    // Menu state (only used in collection mode).
    private boolean inMenu = false;
    private List<String> menuGames;
    private List<TextView> menuRows;
    private int selectedIndex = 0;
    private int lastAxisDir = 0; // d-pad/stick debounce

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        // An asleep phone aborts the unpack partway through, which then costs
        // the user another full decompress on next launch.
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);

        List<String> games = resolveGameList();
        Log.i(TAG, "LoaderActivity: bundled game set = " + games
                + " (installed=" + installedGames() + ")");

        if (games.size() <= 1) {
            // SINGLE-GAME: no launcher menu — boot straight into the one game.
            String game = games.isEmpty() ? "" : games.get(0);
            if (game.isEmpty()) {
                // Ultra-safe fallback to the flavor default.
                try { game = getString(R.string.game_name); } catch (Throwable ignore) {}
            }
            Log.i(TAG, "single-game build -> booting straight into '" + game
                    + "' (no launcher menu)");
            showProgressUi();
            beginUnpackAndLaunch(game);
        } else {
            // COLLECTION: show the selection menu.
            Log.i(TAG, "collection build (" + games.size()
                    + " games) -> showing selection menu");
            showMenuUi(games);
        }
    }

    // --- game-set detection (asset-driven, mirrors build.gradle.kts) ---------

    /**
     * The ordered set of games this launcher offers: a debug override if set,
     * else the games with a bundled archive in assets/bundle/, else the
     * single-game flavor default.
     */
    private List<String> resolveGameList() {
        // 1. Debug override — lets a single-game APK exercise the collection
        //    menu on a real device (dry-run). `adb shell setprop
        //    debug.opengoal.games jak1,jak2` then relaunch.
        String override = getProp("debug.opengoal.games");
        if (override != null && !override.trim().isEmpty()) {
            List<String> out = new ArrayList<>();
            for (String s : override.split(",")) {
                String g = s.trim();
                if (!g.isEmpty() && !out.contains(g)) out.add(g);
            }
            if (!out.isEmpty()) {
                Log.i(TAG, "game set from debug.opengoal.games override: " + out);
                return out;
            }
        }
        // 2. Asset-driven: enumerate the bundled archives.
        List<String> bundled = installedGames();
        if (!bundled.isEmpty()) return bundled;

        // 3. Fallback: the single-game flavor default (e.g. jak1).
        try {
            String g = getString(R.string.game_name);
            if (g != null && !g.isEmpty()) return new ArrayList<>(Arrays.asList(g));
        } catch (Throwable ignore) {}
        return new ArrayList<>();
    }

    /** Games with a real `<game>_assets.zip` bundled in this APK, sorted. */
    private List<String> installedGames() {
        TreeSet<String> games = new TreeSet<>();
        try {
            String[] entries = getAssets().list(BUNDLE_DIR);
            if (entries != null) {
                for (String e : entries) {
                    if (e.endsWith(ZIP_SUFFIX)) {
                        games.add(e.substring(0, e.length() - ZIP_SUFFIX.length()));
                    }
                }
            }
        } catch (IOException e) {
            Log.w(TAG, "installedGames: could not list assets/" + BUNDLE_DIR, e);
        }
        return new ArrayList<>(games);
    }

    private boolean isInstalled(String game) {
        return assetExists(BUNDLE_DIR + "/" + game + ZIP_SUFFIX);
    }

    private String titleFor(String game) {
        String t = GAME_TITLES.get(game);
        return t != null ? t : game;
    }

    // --- collection selection menu (touch + gamepad) -------------------------

    private void showMenuUi(List<String> games) {
        inMenu = true;
        menuGames = games;
        menuRows = new ArrayList<>();
        selectedIndex = 0;

        FrameLayout root = new FrameLayout(this);
        root.setBackgroundColor(COL_BG);

        LinearLayout col = new LinearLayout(this);
        col.setOrientation(LinearLayout.VERTICAL);
        col.setPadding(dp(48), dp(32), dp(48), dp(32));
        FrameLayout.LayoutParams colLp = new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT);
        colLp.gravity = Gravity.CENTER;
        root.addView(col, colLp);

        TextView header = new TextView(this);
        header.setText(COLLECTION_TITLE);
        header.setTextColor(COL_GOLD);
        header.setTextSize(TypedValue.COMPLEX_UNIT_SP, 24);
        header.setGravity(Gravity.CENTER);
        col.addView(header, wrap());

        TextView subtitle = new TextView(this);
        subtitle.setText("Select a game — tap, or use your controller (D-pad + Ⓐ)");
        subtitle.setTextColor(COL_DIM);
        subtitle.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14);
        subtitle.setGravity(Gravity.CENTER);
        subtitle.setPadding(0, dp(8), 0, dp(24));
        col.addView(subtitle, wrap());

        for (int i = 0; i < games.size(); i++) {
            final String game = games.get(i);
            final int idx = i;
            TextView row = new TextView(this);
            String label = titleFor(game);
            if (!isInstalled(game)) label += "   (not included)";
            row.setText(label);
            row.setTextColor(COL_TEXT);
            row.setTextSize(TypedValue.COMPLEX_UNIT_SP, 20);
            row.setPadding(dp(24), dp(18), dp(24), dp(18));
            // Touch: clickable so a tap selects+confirms that row. NOT focusable:
            // if a row held Android view-focus, the framework would consume
            // DPAD_CENTER/ENTER as a click on the FOCUSED row (always row 0) before
            // Activity.onKeyDown runs — decoupling gamepad-confirm from the teal
            // `selectedIndex` highlight. Non-focusable rows let all D-pad keys
            // (incl. CENTER) reach onKeyDown, which confirms `selectedIndex`.
            row.setClickable(true);
            row.setFocusable(false);
            row.setOnClickListener(v -> { selectedIndex = idx; highlight(); confirm(idx); });
            LinearLayout.LayoutParams rlp = new LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT);
            rlp.topMargin = dp(6);
            col.addView(row, rlp);
            menuRows.add(row);
        }

        setContentView(root);
        highlight();
        Log.i(TAG, "collection menu shown with " + games.size() + " entries: " + games);
    }

    private void highlight() {
        if (menuRows == null) return;
        for (int i = 0; i < menuRows.size(); i++) {
            TextView r = menuRows.get(i);
            boolean sel = (i == selectedIndex);
            r.setBackgroundColor(sel ? COL_ROW_SEL : COL_ROW_IDLE);
            r.setTextColor(sel ? Color.WHITE : COL_TEXT);
        }
    }

    private void moveSelection(int delta) {
        if (menuGames == null || menuGames.isEmpty()) return;
        int n = menuGames.size();
        selectedIndex = ((selectedIndex + delta) % n + n) % n;
        highlight();
    }

    private void confirm(int idx) {
        if (menuGames == null || idx < 0 || idx >= menuGames.size()) return;
        String game = menuGames.get(idx);
        if (!isInstalled(game)) {
            String msg = titleFor(game) + " is not included in this build.";
            Log.w(TAG, "menu select '" + game + "' — " + msg);
            Toast.makeText(this, msg, Toast.LENGTH_SHORT).show();
            return;
        }
        Log.i(TAG, "menu select '" + game + "' (" + titleFor(game) + ") — unpacking + launching");
        inMenu = false;
        showProgressUi();
        beginUnpackAndLaunch(game);
    }

    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        if (inMenu) {
            switch (keyCode) {
                case KeyEvent.KEYCODE_DPAD_UP:
                    moveSelection(-1); return true;
                case KeyEvent.KEYCODE_DPAD_DOWN:
                    moveSelection(1); return true;
                case KeyEvent.KEYCODE_DPAD_CENTER:
                case KeyEvent.KEYCODE_ENTER:
                case KeyEvent.KEYCODE_NUMPAD_ENTER:
                case KeyEvent.KEYCODE_BUTTON_A:
                case KeyEvent.KEYCODE_BUTTON_START:
                    confirm(selectedIndex); return true;
                default:
                    break;
            }
        }
        return super.onKeyDown(keyCode, event);
    }

    @Override
    public boolean onGenericMotionEvent(MotionEvent event) {
        if (inMenu && (event.getSource() & android.view.InputDevice.SOURCE_JOYSTICK)
                == android.view.InputDevice.SOURCE_JOYSTICK
                && event.getAction() == MotionEvent.ACTION_MOVE) {
            float hat = event.getAxisValue(MotionEvent.AXIS_HAT_Y);
            float ly = event.getAxisValue(MotionEvent.AXIS_Y);
            float v = Math.abs(hat) > 0.5f ? hat : ly;
            int dir = v > 0.5f ? 1 : (v < -0.5f ? -1 : 0);
            if (dir != 0 && dir != lastAxisDir) {
                moveSelection(dir);
            }
            lastAxisDir = dir;
            return true;
        }
        return super.onGenericMotionEvent(event);
    }

    // --- progress UI (shared by single-game + post-selection) ----------------

    private void showProgressUi() {
        FrameLayout root = new FrameLayout(this);
        root.setBackgroundColor(COL_BG);
        setContentView(root);

        LinearLayout col = new LinearLayout(this);
        col.setOrientation(LinearLayout.VERTICAL);
        col.setPadding(dp(48), dp(36), dp(48), dp(36));
        FrameLayout.LayoutParams colLp = new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT);
        colLp.gravity = Gravity.CENTER;
        root.addView(col, colLp);

        status = new TextView(this);
        status.setText("Setting up game data…");
        status.setTextColor(COL_TEXT);
        status.setTextSize(TypedValue.COMPLEX_UNIT_SP, 20);
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
        pLp.topMargin = dp(24);
        col.addView(progress, pLp);
    }

    private void beginUnpackAndLaunch(final String gameName) {
        Log.i(TAG, "LoaderActivity: first-run decompress check for " + gameName);
        worker = new Thread(() -> {
            try {
                unpackBundleIfNeeded(gameName);
                runOnUiThread(() -> {
                    Intent i = new Intent(LoaderActivity.this, MainActivity.class);
                    i.putExtra(MainActivity.EXTRA_SELECTED_GAME, gameName);
                    startActivity(i);
                    finish();
                });
            } catch (Throwable t) {
                Log.e(TAG, "LoaderActivity: asset setup failed", t);
                final String msg = "Setup failed:\n" + t.getMessage();
                runOnUiThread(() -> {
                    if (status != null) status.setText(msg);
                    if (progress != null) {
                        progress.setIndeterminate(false);
                        progress.setProgress(0);
                    }
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
        // Per-game manifest first (collection layout: bundle/<game>.manifest.properties),
        // else the legacy single-manifest (bundle/manifest.properties).
        String perGame = BUNDLE_DIR + "/" + gameName + ".manifest.properties";
        String manifestAsset = assetExists(perGame)
                ? perGame : (BUNDLE_DIR + "/manifest.properties");
        Manifest m = new Manifest();
        Properties p = new Properties();
        try (InputStream in = getAssets().open(manifestAsset)) {
            p.load(in);
        }
        m.version = p.getProperty("version", "0");
        m.fileCount = Integer.parseInt(p.getProperty("file_count", "-1").trim());
        m.rawBytes = Long.parseLong(p.getProperty("raw_bytes", "-1").trim());
        m.zipName = BUNDLE_DIR + "/" + gameName + ZIP_SUFFIX;
        Log.i(TAG, "manifest for " + gameName + " <- " + manifestAsset
                + " (version=" + m.version + " files=" + m.fileCount + ")");
        return m;
    }

    // jak1 keeps its historical stamp name so an existing jak1 install is not
    // forced into a full re-decompress on upgrade; other games are per-game.
    private static String stampName(String game) {
        return "jak1".equals(game)
                ? ".asset_bundle_stamp"
                : ".asset_bundle_stamp_" + game;
    }

    // --- the one-time, idempotent, version-stamped decompress ----------------

    private void unpackBundleIfNeeded(String gameName) throws IOException {
        Manifest mf = readManifest(gameName);
        File filesDir = getFilesDir();
        File stamp = new File(filesDir, stampName(gameName));

        // Idempotent fast path: stamp present AND version matches → already
        // unpacked from this APK; boot straight through.
        if (stamp.isFile()) {
            String have = readStamp(stamp);
            if (mf.version.equals(have)) {
                Log.i(TAG, gameName + " asset bundle already unpacked (version="
                        + have + ") — skipping decompress, data ready");
                return;
            }
            Log.w(TAG, gameName + " asset bundle version changed (" + have + " -> "
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
        Log.i(TAG, gameName + " asset bundle decompressed: " + filesWritten
                + " files, " + bytesWritten + " bytes in " + elapsedMs
                + "ms (version=" + mf.version + ")");
        runOnUiThread(() -> {
            progress.setProgress(1000);
            status.setText("Setup complete — starting game…");
        });
    }

    // --- helpers -------------------------------------------------------------

    private boolean assetExists(String path) {
        try (InputStream in = getAssets().open(path)) {
            return true;
        } catch (IOException e) {
            return false;
        }
    }

    /** Read a system property via getprop (LoaderActivity has no JNI up yet). */
    private static String getProp(String key) {
        try {
            Process p = Runtime.getRuntime().exec(new String[] { "getprop", key });
            BufferedReader r = new BufferedReader(new InputStreamReader(p.getInputStream()));
            String line = r.readLine();
            r.close();
            p.waitFor();
            return line;
        } catch (Exception e) {
            return null;
        }
    }

    private int dp(int v) {
        return Math.round(v * getResources().getDisplayMetrics().density);
    }

    private LinearLayout.LayoutParams wrap() {
        return new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT);
    }

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
