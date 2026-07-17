// Phase Glauncher-collection (autoport 2026-07-02): the launcher entry point.
// It decides — from which per-game asset bundles are present — whether this APK
// is a SINGLE-game build or a COLLECTION, then either boots straight into the one
// game or shows a selection menu, and finally DECOMPRESSES the chosen game's
// bundled asset archive into the app's private filesDir before handing off to
// MainActivity.
//
// ASSET-DRIVEN mode (mirrors build.gradle.kts detectBundledGames):
//   - The set of games == the `<game>_assets.zip` archives under assets/bundle/
//     PLUS (external-asset-root feature) the `<game>_cgo.zip` slim code packs.
//   - EXACTLY ONE game  -> NO menu; unpack it and boot straight into the game.
//   - MORE THAN ONE     -> a selection menu (text rows, usable by TOUCH and by
//                          GAMEPAD/D-pad); pick one -> unpack -> boot it.
//   - A debug override (getprop debug.opengoal.games=jak1,jak2) lets a build
//     that physically bundles one game still exercise the collection menu on a
//     real device (dry-run) without shipping a 2nd game. Games listed in the
//     override but with no bundled archive are shown but reported "not included".
//
// Phase Grecharged-external-assets (autoport 2026-07): the slim APK no longer
// embeds the iso assets. Per game the flow is now:
//   1. Always unpack the small per-arch CGO pack (assets/bundle/<game>_cgo.zip,
//      compiled *.CGO/*.DGO + android text banks) to <filesDir>/cgo/<game>/ —
//      fake_iso scans it FIRST so fresh code always wins.
//   2. Decide the DATA source: "internal" (legacy filesDir extraction, kept
//      byte-compatible for old self-contained builds and dev installs) or
//      "external" (a user-chosen storage folder with the layout
//      <chosen>/jak_N/{assets/{iso,fr3,recharged_assets},saves,custom_assets}).
//      First boot with neither configured shows a chooser screen (folder picker /
//      manual path / keep-internal), including one-time migration copies of the
//      already-extracted internal assets and the user's saves. The choice is
//      persisted in SharedPreferences("recharged_assets") — the contract
//      MainActivity reads — and mirrored to <filesDir>/asset_root.txt for adb
//      tooling. If a configured external root later goes invalid (moved,
//      unmounted, access revoked) MainActivity bounces back here to re-prompt.
//
// Correctness guarantees preserved: background worker thread (no ANR), a visible
// determinate progress bar, an idempotent version stamp, a low-storage precheck,
// per-entry CRC32 + file-count/byte-total integrity, and the stamp written LAST
// so a SIGKILL mid-unpack never boots off a half-written data set.

package org.opengoal.gk;

import android.app.AlertDialog;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.content.res.AssetManager;
import android.graphics.Color;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.os.StatFs;
import android.provider.DocumentsContract;
import android.provider.Settings;
import android.util.Log;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.View;
import android.view.WindowManager;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.TextView;
import android.widget.Toast;
import androidx.appcompat.app.AppCompatActivity;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.FileWriter;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
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
    // External-asset-root feature: the slim per-arch code pack.
    private static final String CGO_SUFFIX = "_cgo.zip";
    // Grecharged-buildsys-packaging: the package-shipped port-custom asset pack.
    private static final String CUSTOM_SUFFIX = "_custom.zip";

    private static final int COPY_BUFFER_BYTES = 256 * 1024;
    // Free-space safety margin over the raw uncompressed size.
    private static final double STORAGE_MARGIN = 1.05;

    // External-asset-root feature: persisted choice. SharedPreferences file +
    // keys are the contract MainActivity reads — keep in sync.
    private static final String ASSET_PREFS = "recharged_assets";
    private static final String PREF_ASSET_ROOT = "asset_root";
    private static final String PREF_ASSET_MODE = "asset_mode";
    private static final String MODE_EXTERNAL = "external";
    private static final String MODE_INTERNAL = "internal";
    // MainActivity bounces back here with this extra when the configured
    // external root stopped being readable.
    private static final String EXTRA_ASSET_ROOT_INVALID =
            "org.opengoal.gk.ASSET_ROOT_INVALID";

    private static final int REQ_ALL_FILES_ACCESS = 71;
    private static final int REQ_LEGACY_PERMS = 72;
    private static final int REQ_PICK_TREE = 73;
    private static final int REQ_PICK_ZIP = 74;

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

    // Menu state. Used both by the collection game-selection menu (menuGames
    // non-null) and — external-asset-root feature — by generic option screens
    // (menuActions non-null): the same rows/highlight/D-pad machinery drives
    // both; confirm() dispatches on which list is set.
    private boolean inMenu = false;
    private List<String> menuGames;
    private List<Runnable> menuActions;
    private List<TextView> menuRows;
    private int selectedIndex = 0;
    private int lastAxisDir = 0; // d-pad/stick debounce

    // External-asset-root feature: chooser-flow state.
    private String chooserGame;          // game the chooser flow is configuring
    private String chooserBanner;        // one-shot warning line shown on the chooser
    private Runnable afterAccessGranted; // continuation once storage access is held

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        // An asleep phone aborts the unpack partway through, which then costs
        // the user another full decompress on next launch.
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);

        if (getIntent() != null
                && getIntent().getBooleanExtra(EXTRA_ASSET_ROOT_INVALID, false)) {
            chooserBanner = "ASSETS FOLDER NOT FOUND — pick it again.";
        }

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

    /**
     * Games shipped in this APK, sorted: a full `<game>_assets.zip` bundle
     * (self-contained build) OR — external-asset-root feature — a slim
     * `<game>_cgo.zip` code pack (the now-default slim build).
     */
    private List<String> installedGames() {
        TreeSet<String> games = new TreeSet<>();
        try {
            String[] entries = getAssets().list(BUNDLE_DIR);
            if (entries != null) {
                for (String e : entries) {
                    if (e.endsWith(ZIP_SUFFIX)) {
                        games.add(e.substring(0, e.length() - ZIP_SUFFIX.length()));
                    } else if (e.endsWith(CGO_SUFFIX)) {
                        games.add(e.substring(0, e.length() - CGO_SUFFIX.length()));
                    }
                }
            }
        } catch (IOException e) {
            Log.w(TAG, "installedGames: could not list assets/" + BUNDLE_DIR, e);
        }
        return new ArrayList<>(games);
    }

    private boolean isInstalled(String game) {
        return assetExists(BUNDLE_DIR + "/" + game + ZIP_SUFFIX)
                || assetExists(BUNDLE_DIR + "/" + game + CGO_SUFFIX);
    }

    private String titleFor(String game) {
        String t = GAME_TITLES.get(game);
        return t != null ? t : game;
    }

    /** Map a game id ("jak1") to its external-layout folder ("jak_1"). Keep in
     *  sync with MainActivity.gameFolder(). */
    private static String gameFolder(String game) {
        if (game != null && game.length() > 3 && game.startsWith("jak")) {
            return "jak_" + game.substring(3);
        }
        return game;
    }

    // --- collection selection menu (touch + gamepad) -------------------------

    private void showMenuUi(List<String> games) {
        menuGames = games;
        menuActions = null;
        List<String> labels = new ArrayList<>();
        for (String game : games) {
            String label = titleFor(game);
            if (!isInstalled(game)) label += "   (not included)";
            labels.add(label);
        }
        buildRowScreen(COLLECTION_TITLE,
                "Select a game — tap, or use your controller (D-pad + Ⓐ)",
                null, labels);
        Log.i(TAG, "collection menu shown with " + games.size() + " entries: " + games);
    }

    /**
     * Shared row-screen builder: title + optional banner + subtitle + rows.
     * Rows are driven by the existing touch/D-pad machinery; confirm() runs
     * either the game selection (menuGames) or a Runnable (menuActions).
     */
    private void buildRowScreen(String title, String subtitle, String banner,
                                List<String> labels) {
        inMenu = true;
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
        header.setText(title);
        header.setTextColor(COL_GOLD);
        header.setTextSize(TypedValue.COMPLEX_UNIT_SP, 24);
        header.setGravity(Gravity.CENTER);
        col.addView(header, wrap());

        if (banner != null && !banner.isEmpty()) {
            TextView warn = new TextView(this);
            warn.setText(banner);
            warn.setTextColor(0xFFE07A3F); // warm warning orange
            warn.setTextSize(TypedValue.COMPLEX_UNIT_SP, 15);
            warn.setGravity(Gravity.CENTER);
            warn.setPadding(0, dp(10), 0, 0);
            col.addView(warn, wrap());
        }

        TextView sub = new TextView(this);
        sub.setText(subtitle);
        sub.setTextColor(COL_DIM);
        sub.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14);
        sub.setGravity(Gravity.CENTER);
        sub.setPadding(0, dp(8), 0, dp(24));
        col.addView(sub, wrap());

        for (int i = 0; i < labels.size(); i++) {
            final int idx = i;
            TextView row = new TextView(this);
            row.setText(labels.get(i));
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
        if (menuRows == null || menuRows.isEmpty()) return;
        int n = menuRows.size();
        selectedIndex = ((selectedIndex + delta) % n + n) % n;
        highlight();
    }

    private void confirm(int idx) {
        if (menuRows == null || idx < 0 || idx >= menuRows.size()) return;
        // Generic option screen (external-asset-root chooser flows).
        if (menuActions != null) {
            if (idx < menuActions.size()) {
                inMenu = false;
                menuActions.get(idx).run();
            }
            return;
        }
        // Collection game-selection menu.
        if (menuGames == null || idx >= menuGames.size()) return;
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

    private void setStatus(String text) {
        runOnUiThread(() -> { if (status != null) status.setText(text); });
    }

    private void setProgressPermille(int pm) {
        runOnUiThread(() -> { if (progress != null) progress.setProgress(pm); });
    }

    // --- boot orchestration ---------------------------------------------------

    /**
     * External-asset-root feature: per-game boot pipeline.
     *   1. unpack the CGO code pack (always, cheap, version-stamped);
     *   2. route on the persisted asset mode (external / internal / unset).
     */
    private void beginUnpackAndLaunch(final String gameName) {
        Log.i(TAG, "LoaderActivity: boot pipeline for " + gameName);
        worker = new Thread(() -> {
            try {
                unpackCgoPackIfNeeded(gameName);
                unpackCustomPackIfNeeded(gameName);
                runOnUiThread(() -> decideBootMode(gameName));
            } catch (Throwable t) {
                Log.e(TAG, "LoaderActivity: CGO pack setup failed", t);
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

    /** Route on the persisted mode. Runs on the UI thread. */
    private void decideBootMode(String gameName) {
        SharedPreferences prefs = getSharedPreferences(ASSET_PREFS, MODE_PRIVATE);
        String mode = prefs.getString(PREF_ASSET_MODE, null);
        String root = prefs.getString(PREF_ASSET_ROOT, null);

        if (MODE_EXTERNAL.equals(mode) && root != null && !root.isEmpty()) {
            File gameRoot = new File(root, gameFolder(gameName));
            File iso = new File(gameRoot, "assets/iso");
            String[] entries = iso.list();
            boolean valid = hasStorageAccess()
                    && iso.isDirectory() && entries != null && entries.length > 0;
            if (valid) {
                launchGame(gameName);
                return;
            }
            Log.w(TAG, "external root invalid at boot (" + iso.getAbsolutePath()
                    + ", access=" + hasStorageAccess() + ") — re-prompting");
            if (chooserBanner == null) {
                chooserBanner = hasStorageAccess()
                        ? "ASSETS FOLDER NOT FOUND — pick it again."
                        : "STORAGE ACCESS REQUIRED — grant it, then retry.";
            }
            showChooserUi(gameName);
            return;
        }

        if (MODE_INTERNAL.equals(mode)) {
            startInternalUnpackAndLaunch(gameName);
            return;
        }

        // Mode unset. Old self-contained builds (full bundle in the APK) keep
        // behaving exactly as before — no new UI, persist internal silently.
        if (assetExists(BUNDLE_DIR + "/" + gameName + ZIP_SUFFIX)) {
            Log.i(TAG, "full bundle present + no mode set -> internal (legacy behavior)");
            persistChoice(gameName, MODE_INTERNAL, null);
            startInternalUnpackAndLaunch(gameName);
            return;
        }

        // Fresh slim install (or an update over an internal-data install).
        showChooserUi(gameName);
    }

    private void startInternalUnpackAndLaunch(final String gameName) {
        showProgressUi();
        worker = new Thread(() -> {
            try {
                unpackBundleIfNeeded(gameName);
                launchGame(gameName);
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

    /** Hand off to MainActivity. Safe to call from any thread. */
    private void launchGame(final String gameName) {
        runOnUiThread(() -> {
            Intent i = new Intent(LoaderActivity.this, MainActivity.class);
            i.putExtra(MainActivity.EXTRA_SELECTED_GAME, gameName);
            startActivity(i);
            finish();
        });
    }

    // --- external-asset-root: chooser screen ----------------------------------

    private boolean hasInternalAssets(String gameName) {
        File iso = new File(getFilesDir(), "iso_data/" + gameName);
        String[] entries = iso.list();
        return iso.isDirectory() && entries != null && entries.length > 0;
    }

    private void showChooserUi(String gameName) {
        chooserGame = gameName;
        String banner = chooserBanner;
        chooserBanner = null; // one-shot

        List<String> labels = new ArrayList<>();
        List<Runnable> actions = new ArrayList<>();

        SharedPreferences prefs = getSharedPreferences(ASSET_PREFS, MODE_PRIVATE);
        final String savedRoot = prefs.getString(PREF_ASSET_ROOT, null);
        if (savedRoot != null && !savedRoot.isEmpty()
                && MODE_EXTERNAL.equals(prefs.getString(PREF_ASSET_MODE, null))) {
            // A root is already configured but was invalid at boot (most often a
            // revoked grant): retry it first without forcing a re-pick.
            labels.add("RETRY " + savedRoot);
            actions.add(() -> ensureStorageAccess(() -> {
                showProgressUi();
                decideBootMode(gameName);
            }));
        }

        labels.add("CHOOSE ASSETS FOLDER");
        actions.add(() -> ensureStorageAccess(this::openFolderPicker));

        labels.add("TYPE PATH MANUALLY");
        actions.add(() -> ensureStorageAccess(() -> showManualPathDialog(null)));

        if (hasInternalAssets(gameName)) {
            labels.add("USE INTERNAL ASSETS");
            actions.add(() -> {
                persistChoice(gameName, MODE_INTERNAL, null);
                startInternalUnpackAndLaunch(gameName);
            });
        }

        menuGames = null;
        menuActions = actions;
        buildRowScreen(titleFor(gameName) + " — game assets",
                "Game assets now live in a folder you choose (one folder serves all\n"
                        + "games: jak_1 / jak_2 / jak_3 subfolders). Pick where they are —\n"
                        + "or should go.",
                banner, labels);
        Log.i(TAG, "asset chooser shown for " + gameName
                + (banner != null ? " (banner: " + banner + ")" : ""));
    }

    // --- external-asset-root: storage access ----------------------------------

    private boolean hasStorageAccess() {
        if (Build.VERSION.SDK_INT >= 30) {
            return Environment.isExternalStorageManager();
        }
        return checkSelfPermission(android.Manifest.permission.READ_EXTERNAL_STORAGE)
                == PackageManager.PERMISSION_GRANTED;
    }

    /** Run `next` once storage access is held, asking the user if needed. */
    private void ensureStorageAccess(Runnable next) {
        if (hasStorageAccess()) {
            next.run();
            return;
        }
        afterAccessGranted = next;
        if (Build.VERSION.SDK_INT >= 30) {
            try {
                Intent i = new Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                        Uri.parse("package:" + getPackageName()));
                startActivityForResult(i, REQ_ALL_FILES_ACCESS);
            } catch (ActivityNotFoundException e) {
                try {
                    startActivityForResult(
                            new Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION),
                            REQ_ALL_FILES_ACCESS);
                } catch (ActivityNotFoundException e2) {
                    Log.e(TAG, "no all-files-access settings screen available", e2);
                    afterAccessGranted = null;
                    chooserBanner = "STORAGE ACCESS REQUIRED — could not open Settings.";
                    showChooserUi(chooserGame);
                }
            }
        } else {
            requestPermissions(new String[] {
                    android.Manifest.permission.READ_EXTERNAL_STORAGE,
                    android.Manifest.permission.WRITE_EXTERNAL_STORAGE,
            }, REQ_LEGACY_PERMS);
        }
    }

    private void resumeAfterAccessCheck() {
        Runnable next = afterAccessGranted;
        afterAccessGranted = null;
        if (next == null) return;
        if (hasStorageAccess()) {
            next.run();
        } else {
            // Declined: back to the chooser with a visible retry hint. Never
            // auto-reopen Settings — only another explicit tap does.
            Log.w(TAG, "storage access declined");
            chooserBanner = "STORAGE ACCESS REQUIRED — RETRY.";
            showChooserUi(chooserGame);
        }
    }

    @Override
    public void onRequestPermissionsResult(int code, String[] perms, int[] grants) {
        super.onRequestPermissionsResult(code, perms, grants);
        if (code == REQ_LEGACY_PERMS) {
            resumeAfterAccessCheck();
        }
    }

    // --- external-asset-root: folder / archive pickers -------------------------

    private void openFolderPicker() {
        try {
            Intent i = new Intent(Intent.ACTION_OPEN_DOCUMENT_TREE);
            startActivityForResult(i, REQ_PICK_TREE);
        } catch (ActivityNotFoundException e) {
            Log.w(TAG, "no documents UI for ACTION_OPEN_DOCUMENT_TREE", e);
            showManualPathDialog(null);
        }
    }

    private void openArchivePicker() {
        try {
            Intent i = new Intent(Intent.ACTION_OPEN_DOCUMENT);
            i.addCategory(Intent.CATEGORY_OPENABLE);
            i.setType("application/zip");
            i.putExtra(Intent.EXTRA_MIME_TYPES, new String[] {
                    "application/zip", "application/octet-stream" });
            startActivityForResult(i, REQ_PICK_ZIP);
        } catch (ActivityNotFoundException e) {
            Log.w(TAG, "no documents UI for ACTION_OPEN_DOCUMENT", e);
            chooserBanner = "NO FILE PICKER AVAILABLE ON THIS DEVICE.";
            showChooserUi(chooserGame);
        }
    }

    @Override
    protected void onActivityResult(int req, int result, Intent data) {
        super.onActivityResult(req, result, data);
        switch (req) {
            case REQ_ALL_FILES_ACCESS:
                // The Settings screen has no OK/Cancel result — re-check the state.
                resumeAfterAccessCheck();
                return;
            case REQ_PICK_TREE: {
                Uri uri = (data != null) ? data.getData() : null;
                if (uri == null) { showChooserUi(chooserGame); return; }
                String path = treeUriToPath(uri);
                if (path == null) {
                    Log.w(TAG, "tree uri not convertible to a path: " + uri);
                    showManualPathDialog(guessPathFromTreeUri(uri));
                    return;
                }
                applyChosenRoot(path);
                return;
            }
            case REQ_PICK_ZIP: {
                Uri uri = (data != null) ? data.getData() : null;
                if (uri == null) { showPopulateUi(chooserGame); return; }
                startArchiveExtraction(uri);
                return;
            }
            default:
                break;
        }
    }

    /**
     * Convert an ACTION_OPEN_DOCUMENT_TREE result to a plain filesystem path.
     * `primary:REST` -> /storage/emulated/0/REST; `XXXX-XXXX:REST` ->
     * /storage/XXXX-XXXX/REST. Returns null for shapes we can't map (cloud
     * providers etc.) — the caller falls back to the manual dialog.
     */
    private static String treeUriToPath(Uri uri) {
        try {
            if (!"com.android.externalstorage.documents".equals(uri.getAuthority())) {
                return null;
            }
            String docId = DocumentsContract.getTreeDocumentId(uri);
            int colon = docId.indexOf(':');
            String volume = colon >= 0 ? docId.substring(0, colon) : docId;
            String rest = colon >= 0 ? docId.substring(colon + 1) : "";
            String base = "primary".equalsIgnoreCase(volume)
                    ? "/storage/emulated/0" : ("/storage/" + volume);
            return rest.isEmpty() ? base : (base + "/" + rest);
        } catch (Throwable t) {
            return null;
        }
    }

    private static String guessPathFromTreeUri(Uri uri) {
        try {
            String docId = DocumentsContract.getTreeDocumentId(uri);
            int colon = docId.indexOf(':');
            return colon >= 0 ? "/storage/emulated/0/" + docId.substring(colon + 1) : null;
        } catch (Throwable t) {
            return null;
        }
    }

    private void showManualPathDialog(String prefill) {
        EditText input = new EditText(this);
        input.setText(prefill != null ? prefill : "/storage/emulated/0/OpenGOAL");
        input.setSingleLine(true);
        AlertDialog dlg = new AlertDialog.Builder(this)
                .setTitle("Assets folder")
                .setMessage("Absolute path of the folder that holds (or should hold) "
                        + gameFolder(chooserGame) + "/assets")
                .setView(input)
                .setPositiveButton("OK", (d, w) -> {
                    String path = input.getText().toString().trim();
                    if (path.isEmpty()) { showChooserUi(chooserGame); return; }
                    File dir = new File(path);
                    if (!dir.isDirectory() && !dir.mkdirs()) {
                        chooserBanner = "COULD NOT CREATE " + path;
                        showChooserUi(chooserGame);
                        return;
                    }
                    if (!dir.canRead()) {
                        chooserBanner = "CANNOT READ " + path + " — check storage access.";
                        showChooserUi(chooserGame);
                        return;
                    }
                    applyChosenRoot(path);
                })
                .setNegativeButton("CANCEL", (d, w) -> showChooserUi(chooserGame))
                .create();
        dlg.show();
    }

    // --- external-asset-root: root acceptance + population ---------------------

    /** A chosen base folder is in hand: persist, scaffold, then populate/launch. */
    private void applyChosenRoot(String chosenBase) {
        final String gameName = chooserGame;
        File dir = new File(chosenBase);
        if (!dir.isDirectory() || !dir.canRead()) {
            chooserBanner = "FOLDER NOT READABLE: " + chosenBase;
            showChooserUi(gameName);
            return;
        }
        File gameRoot = new File(dir, gameFolder(gameName));
        // Scaffold the per-game layout. assets/iso may stay absent until populated.
        for (String sub : new String[] { "assets", "saves", "custom_assets" }) {
            File d = new File(gameRoot, sub);
            if (!d.isDirectory() && !d.mkdirs()) {
                chooserBanner = "COULD NOT CREATE " + d.getAbsolutePath();
                showChooserUi(gameName);
                return;
            }
        }
        persistChoice(gameName, MODE_EXTERNAL, chosenBase);
        Log.i(TAG, "external asset root chosen: " + chosenBase
                + " (gameRoot=" + gameRoot.getAbsolutePath() + ")");

        File iso = new File(gameRoot, "assets/iso");
        String[] entries = iso.list();
        if (iso.isDirectory() && entries != null && entries.length > 0) {
            migrateSavesIfNeeded(gameName, gameRoot);
            launchGame(gameName);
        } else {
            showPopulateUi(gameName);
        }
    }

    /** assets/iso is empty at the chosen root: offer ways to fill it. */
    private void showPopulateUi(String gameName) {
        chooserGame = gameName;
        List<String> labels = new ArrayList<>();
        List<Runnable> actions = new ArrayList<>();

        if (hasInternalAssets(gameName)) {
            labels.add("COPY INSTALLED ASSETS TO FOLDER");
            actions.add(() -> startInternalCopy(gameName));
        }

        labels.add("EXTRACT ASSET ARCHIVE (ZIP)");
        actions.add(this::openArchivePicker);

        labels.add("CONTINUE ANYWAY");
        actions.add(() -> {
            File gameRoot = externalGameRoot(gameName);
            File iso = new File(gameRoot, "assets/iso");
            String[] entries = iso.list();
            if (iso.isDirectory() && entries != null && entries.length > 0) {
                migrateSavesIfNeeded(gameName, gameRoot);
                launchGame(gameName);
            } else {
                chooserBanner = "ASSETS NOT FOUND AT " + iso.getAbsolutePath();
                showPopulateUi(gameName);
            }
        });

        menuGames = null;
        menuActions = actions;
        buildRowScreen(titleFor(gameName) + " — add assets",
                "The chosen folder has no game assets yet\n("
                        + new File(externalGameRoot(gameName), "assets/iso").getAbsolutePath()
                        + " is empty).",
                chooserBanner, labels);
        chooserBanner = null;
    }

    private File externalGameRoot(String gameName) {
        SharedPreferences prefs = getSharedPreferences(ASSET_PREFS, MODE_PRIVATE);
        String root = prefs.getString(PREF_ASSET_ROOT, "");
        return new File(root, gameFolder(gameName));
    }

    /**
     * Persist the user's choice — SharedPreferences for MainActivity, plus the
     * <filesDir>/asset_root.txt mirror adb tooling reads (per-game root path for
     * external, the literal line "internal" otherwise).
     */
    private void persistChoice(String gameName, String mode, String chosenBase) {
        SharedPreferences.Editor ed =
                getSharedPreferences(ASSET_PREFS, MODE_PRIVATE).edit();
        ed.putString(PREF_ASSET_MODE, mode);
        if (chosenBase != null) ed.putString(PREF_ASSET_ROOT, chosenBase);
        ed.apply();
        try (FileWriter w = new FileWriter(new File(getFilesDir(), "asset_root.txt"))) {
            w.write(MODE_EXTERNAL.equals(mode)
                    ? new File(chosenBase, gameFolder(gameName)).getAbsolutePath() + "\n"
                    : "internal\n");
        } catch (IOException e) {
            Log.w(TAG, "could not write asset_root.txt", e);
        }
    }

    // --- external-asset-root: migration copies ---------------------------------

    /** Copy the already-extracted internal assets out to the chosen folder. */
    private void startInternalCopy(final String gameName) {
        showProgressUi();
        setStatus("Copying installed assets…");
        worker = new Thread(() -> {
            try {
                File gameRoot = externalGameRoot(gameName);
                File filesDir = getFilesDir();

                // Build the copy list first so progress has a denominator.
                List<File> src = new ArrayList<>();
                List<File> dst = new ArrayList<>();
                File isoSrc = new File(filesDir, "iso_data/" + gameName);
                File[] isoFiles = isoSrc.listFiles();
                if (isoFiles != null) {
                    for (File f : isoFiles) {
                        if (!f.isFile()) continue;
                        String n = f.getName();
                        // Compiled code stays with the binary (the CGO pack) —
                        // the external folder carries only the data files.
                        if (n.endsWith(".CGO") || n.endsWith(".DGO")) continue;
                        src.add(f);
                        dst.add(new File(gameRoot, "assets/iso/" + n));
                    }
                }
                File fr3Src = new File(filesDir, "out/" + gameName + "/fr3");
                File[] fr3Files = fr3Src.listFiles();
                if (fr3Files != null) {
                    for (File f : fr3Files) {
                        if (!f.isFile()) continue;
                        src.add(f);
                        dst.add(new File(gameRoot, "assets/fr3/" + f.getName()));
                    }
                }
                File rhSrc = new File(filesDir, "recharged_assets");
                File[] rhFiles = rhSrc.listFiles();
                if (rhFiles != null) {
                    for (File f : rhFiles) {
                        if (!f.isFile()) continue;
                        src.add(f);
                        dst.add(new File(gameRoot, "assets/recharged_assets/" + f.getName()));
                    }
                }

                for (int i = 0; i < src.size(); i++) {
                    copyFile(src.get(i), dst.get(i));
                    final int done = i + 1, total = src.size();
                    setStatus("Copying installed assets…\n" + done + " / " + total);
                    setProgressPermille(total > 0 ? (done * 1000) / total : 0);
                }
                Log.i(TAG, "internal asset copy done: " + src.size()
                        + " files -> " + gameRoot.getAbsolutePath()
                        + " (originals kept)");

                migrateSavesIfNeeded(gameName, gameRoot);
                launchGame(gameName);
            } catch (Throwable t) {
                Log.e(TAG, "internal asset copy failed", t);
                final String msg = t.getMessage();
                runOnUiThread(() -> {
                    chooserBanner = "COPY FAILED: " + msg;
                    showPopulateUi(gameName);
                });
            }
        }, "opengoal-asset-copy");
        worker.start();
    }

    /**
     * One-time saves migration: copy internal saves/settings out to
     * <gameRoot>/saves once the game switches to the external layout, so the
     * user's progress follows. COPY only — internal originals are kept.
     * Skipped when the external saves dir already has content.
     */
    private void migrateSavesIfNeeded(String gameName, File gameRoot) {
        try {
            File savesDst = new File(gameRoot, "saves");
            String[] existing = savesDst.list();
            if (existing != null && existing.length > 0) {
                return; // external saves already in place — never clobber them
            }
            File cfg = new File(getFilesDir(), ".config/OpenGOAL/" + gameName);
            int n = 0;
            n += copyTree(new File(cfg, "saves"), savesDst);
            n += copyTree(new File(cfg, "settings"), new File(savesDst, "settings"));
            if (n > 0) {
                Log.i(TAG, "migrated " + n + " save/settings file(s) to "
                        + savesDst.getAbsolutePath() + " (internal originals kept)");
            }
        } catch (Throwable t) {
            // Migration must never block the boot; the game will simply start
            // with fresh saves at the new location.
            Log.w(TAG, "saves migration failed (continuing)", t);
        }
    }

    /** Recursive copy; returns the number of files copied. Missing src = 0. */
    private int copyTree(File srcDir, File dstDir) throws IOException {
        if (!srcDir.isDirectory()) return 0;
        File[] kids = srcDir.listFiles();
        if (kids == null) return 0;
        int n = 0;
        for (File k : kids) {
            File d = new File(dstDir, k.getName());
            if (k.isDirectory()) {
                n += copyTree(k, d);
            } else if (k.isFile()) {
                copyFile(k, d);
                n++;
            }
        }
        return n;
    }

    private void copyFile(File src, File dst) throws IOException {
        File parent = dst.getParentFile();
        if (parent != null && !parent.isDirectory() && !parent.mkdirs()) {
            throw new IOException("could not create " + parent.getAbsolutePath());
        }
        byte[] buf = new byte[COPY_BUFFER_BYTES];
        try (InputStream in = new FileInputStream(src);
             OutputStream out = new FileOutputStream(dst)) {
            int r;
            while ((r = in.read(buf)) > 0) out.write(buf, 0, r);
        }
    }

    // --- external-asset-root: user-archive extraction ---------------------------

    /**
     * Stream a user-picked <game>_assets.zip (entries iso/, fr3/,
     * recharged_assets/) into <gameRoot>/assets/. No manifest is available for
     * a user-supplied file, so progress shows running count + MB; per-entry
     * CRC32 is still validated by ZipInputStream.closeEntry().
     */
    private void startArchiveExtraction(final Uri uri) {
        final String gameName = chooserGame;
        showProgressUi();
        setStatus("Extracting asset archive…");
        runOnUiThread(() -> { if (progress != null) progress.setIndeterminate(true); });
        worker = new Thread(() -> {
            long bytes = 0;
            int files = 0;
            try {
                File assetsDir = new File(externalGameRoot(gameName), "assets");
                String canonRoot = assetsDir.getCanonicalPath() + File.separator;
                byte[] buf = new byte[COPY_BUFFER_BYTES];
                try (InputStream raw = getContentResolver().openInputStream(uri);
                     ZipInputStream zin = new ZipInputStream(raw)) {
                    if (raw == null) throw new IOException("could not open the picked file");
                    ZipEntry e;
                    while ((e = zin.getNextEntry()) != null) {
                        String name = e.getName();
                        if (e.isDirectory()) { zin.closeEntry(); continue; }
                        File outFile = new File(assetsDir, name);
                        if (!outFile.getCanonicalPath().startsWith(canonRoot)) {
                            throw new IOException("refusing unsafe archive entry: " + name);
                        }
                        File parent = outFile.getParentFile();
                        if (parent != null && !parent.isDirectory() && !parent.mkdirs()) {
                            throw new IOException("could not create "
                                    + parent.getAbsolutePath());
                        }
                        try (FileOutputStream out = new FileOutputStream(outFile)) {
                            int r;
                            while ((r = zin.read(buf)) > 0) {
                                out.write(buf, 0, r);
                                bytes += r;
                            }
                        }
                        zin.closeEntry(); // CRC32 validation
                        files++;
                        if ((files % 5) == 0) {
                            setStatus("Extracting asset archive…\n" + files + " files   "
                                    + humanBytes(bytes));
                        }
                    }
                }
                if (files == 0) {
                    throw new IOException("archive contained no files");
                }
                Log.i(TAG, "external archive extracted: " + files + " files, "
                        + bytes + " bytes -> " + externalGameRoot(gameName)
                        + "/assets");
                migrateSavesIfNeeded(gameName, externalGameRoot(gameName));
                launchGame(gameName);
            } catch (Throwable t) {
                Log.e(TAG, "archive extraction failed after " + files + " files", t);
                final String msg = t.getMessage();
                runOnUiThread(() -> {
                    chooserBanner = "EXTRACTION FAILED: " + msg;
                    showPopulateUi(gameName);
                });
            }
        }, "opengoal-archive-extract");
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

    // --- the CGO code-pack decompress (external-asset-root feature) -----------

    /**
     * Unpack assets/bundle/<game>_cgo.zip (FLAT entries: *.CGO / *.DGO /
     * *COMMON.TXT) into <filesDir>/cgo/<game>/. Version-stamped
     * (.cgo_pack_stamp_<game>, written LAST), per-entry CRC32 via closeEntry,
     * file-count integrity from the pack manifest. Silently returns when this
     * APK ships no CGO pack (old self-contained builds).
     */
    private void unpackCgoPackIfNeeded(String gameName) throws IOException {
        String zipAsset = BUNDLE_DIR + "/" + gameName + CGO_SUFFIX;
        if (!assetExists(zipAsset)) {
            Log.i(TAG, "no CGO pack in this APK for " + gameName + " — skipping");
            return;
        }
        String manifestAsset = BUNDLE_DIR + "/" + gameName + "_cgo.manifest.properties";
        Properties p = new Properties();
        try (InputStream in = getAssets().open(manifestAsset)) {
            p.load(in);
        }
        String version = p.getProperty("version", "0");
        int wantFiles = Integer.parseInt(p.getProperty("file_count", "-1").trim());

        File filesDir = getFilesDir();
        File stamp = new File(filesDir, ".cgo_pack_stamp_" + gameName);
        File target = new File(filesDir, "cgo/" + gameName);

        if (stamp.isFile() && version.equals(readStamp(stamp))) {
            Log.i(TAG, gameName + " CGO pack current (version=" + version + ")");
            return;
        }
        Log.i(TAG, gameName + " CGO pack unpack (version=" + version
                + ", files=" + wantFiles + ")");
        setStatus("Updating game code…");

        // Wipe target + stale stamp first so an interrupted unpack never boots
        // off a mixed code set (the mixed-build SIGILL class).
        if (stamp.exists()) stamp.delete();
        deleteRecursive(target);
        if (!target.mkdirs()) {
            throw new IOException("could not create " + target.getAbsolutePath());
        }

        int filesWritten = 0;
        byte[] buf = new byte[COPY_BUFFER_BYTES];
        String canonRoot = target.getCanonicalPath() + File.separator;
        try (InputStream rawIn = getAssets().open(zipAsset, AssetManager.ACCESS_STREAMING);
             ZipInputStream zin = new ZipInputStream(rawIn)) {
            ZipEntry e;
            while ((e = zin.getNextEntry()) != null) {
                if (e.isDirectory()) { zin.closeEntry(); continue; }
                File outFile = new File(target, new File(e.getName()).getName());
                if (!outFile.getCanonicalPath().startsWith(canonRoot)) {
                    throw new IOException("refusing unsafe CGO pack entry: " + e.getName());
                }
                try (FileOutputStream out = new FileOutputStream(outFile)) {
                    int r;
                    while ((r = zin.read(buf)) > 0) out.write(buf, 0, r);
                }
                zin.closeEntry(); // CRC32 validation
                filesWritten++;
            }
        }
        if (wantFiles >= 0 && filesWritten != wantFiles) {
            throw new IOException("CGO pack integrity: unpacked " + filesWritten
                    + " files, manifest expects " + wantFiles);
        }
        writeStamp(stamp, version);
        Log.i(TAG, gameName + " CGO pack unpacked: " + filesWritten
                + " files (version=" + version + ")");
    }

    // Grecharged-buildsys-packaging: unpack the package-shipped port-custom asset
    // pack (recharged_assets/*.png, fr3/*.grassbake, fr3/enhanced/*.fr3) into
    // <filesDir>/custom/<game>/. Mirrors unpackCgoPackIfNeeded (version-stamped,
    // wipe-then-unpack-then-stamp-LAST) with two differences: (a) zip entry
    // subpaths are PRESERVED (parent dirs created); (b) if the pack is ABSENT
    // from the APK but a stamp exists, the previously-unpacked custom dir is
    // wiped and the stamp deleted (pack removed from build) — not an error.
    private void unpackCustomPackIfNeeded(String gameName) throws IOException {
        File filesDir = getFilesDir();
        File stamp = new File(filesDir, ".custom_pack_stamp_" + gameName);
        File target = new File(filesDir, "custom/" + gameName);

        String zipAsset = BUNDLE_DIR + "/" + gameName + CUSTOM_SUFFIX;
        String manifestAsset = BUNDLE_DIR + "/" + gameName + "_custom.manifest.properties";
        if (!assetExists(manifestAsset)) {
            // Pack removed from this build: drop any previously-unpacked dir so we
            // don't boot custom assets the build no longer ships.
            if (stamp.isFile()) {
                Log.i(TAG, "custom pack removed from APK for " + gameName
                        + " — wiping " + target.getAbsolutePath());
                deleteRecursive(target);
                stamp.delete();
            } else {
                Log.i(TAG, "no custom pack in this APK for " + gameName + " — skipping");
            }
            return;
        }

        Properties p = new Properties();
        try (InputStream in = getAssets().open(manifestAsset)) {
            p.load(in);
        }
        String version = p.getProperty("version", "0");
        int wantFiles = Integer.parseInt(p.getProperty("file_count", "-1").trim());

        if (stamp.isFile() && version.equals(readStamp(stamp))) {
            Log.i(TAG, gameName + " custom pack current (version=" + version + ")");
            return;
        }
        Log.i(TAG, gameName + " custom pack unpack (version=" + version
                + ", files=" + wantFiles + ")");
        setStatus("Updating game assets…");

        // Wipe target + stale stamp first so an interrupted unpack never leaves a
        // mixed asset set behind.
        if (stamp.exists()) stamp.delete();
        deleteRecursive(target);
        if (!target.mkdirs()) {
            throw new IOException("could not create " + target.getAbsolutePath());
        }

        int filesWritten = 0;
        byte[] buf = new byte[COPY_BUFFER_BYTES];
        String canonRoot = target.getCanonicalPath() + File.separator;
        try (InputStream rawIn = getAssets().open(zipAsset, AssetManager.ACCESS_STREAMING);
             ZipInputStream zin = new ZipInputStream(rawIn)) {
            ZipEntry e;
            while ((e = zin.getNextEntry()) != null) {
                if (e.isDirectory()) { zin.closeEntry(); continue; }
                // PRESERVE the entry subpath (recharged_assets/x.png, fr3/y.grassbake,
                // fr3/enhanced/z.fr3) — create parent dirs.
                File outFile = new File(target, e.getName());
                if (!outFile.getCanonicalPath().startsWith(canonRoot)) {
                    throw new IOException("refusing unsafe custom pack entry: " + e.getName());
                }
                File parent = outFile.getParentFile();
                if (parent != null && !parent.isDirectory() && !parent.mkdirs()) {
                    throw new IOException("could not create " + parent.getAbsolutePath());
                }
                try (FileOutputStream out = new FileOutputStream(outFile)) {
                    int r;
                    while ((r = zin.read(buf)) > 0) out.write(buf, 0, r);
                }
                zin.closeEntry(); // CRC32 validation
                filesWritten++;
            }
        }
        if (wantFiles >= 0 && filesWritten != wantFiles) {
            throw new IOException("custom pack integrity: unpacked " + filesWritten
                    + " files, manifest expects " + wantFiles);
        }
        writeStamp(stamp, version);
        Log.i(TAG, gameName + " custom pack unpacked: " + filesWritten
                + " files (version=" + version + ")");
    }

    // --- the one-time, idempotent, version-stamped decompress ----------------

    // ---- supervisor-diag: jak2 remote-diagnostic file plumbing (Java side) ------
    //
    // The native side (gk_android_main.cpp, jak2-gated at runtime) writes progress
    // breadcrumbs to files/jak2_diag.txt and a crash forensic to files/jak2_crash.txt
    // via getExternalFilesDir(null). getExternalFilesDir(null) is the app's EXTERNAL
    // files dir, NOT getFilesDir(); mirror that here so we copy the same files out.

    private File externalDiagDir() {
        // Match the native path (getExternalFilesDir(null)); may be null if external
        // storage is unavailable — caller handles null.
        return getExternalFilesDir(null);
    }

    // Append one line to files/jak2_diag.txt (external files dir) via plain Java.
    // Best-effort — never throws to the caller (unpack must not fail on a diag write).
    private void appendJak2Diag(String line) {
        try {
            File dir = externalDiagDir();
            if (dir == null) return;
            File f = new File(dir, "jak2_diag.txt");
            // Truncate-rotate if it somehow grew huge (mirrors the native 256 KB cap).
            boolean append = !(f.isFile() && f.length() > 256L * 1024L);
            try (FileWriter w = new FileWriter(f, append)) {
                w.write("[loader] " + line + "\n");
            }
        } catch (Throwable ignore) {
            // diagnostics are best-effort; swallow everything
        }
    }

    // appendJak2Diag (above) writes best-effort loader breadcrumbs into the app's
    // private files dir only. The DIAG2 public-Downloads exporter + boot toast were
    // a temporary HONOR-debug aid and have been removed (owner 2026-07-09: leftover
    // toast at boot). Nothing surfaces these files to the user anymore.

    private void unpackBundleIfNeeded(String gameName) throws IOException {
        // External-asset-root feature: a slim APK ships NO full bundle. Internal
        // mode then simply keeps whatever iso_data is already on the device
        // (dev installs maintain it via adb) — the old wipe-then-unpack path
        // must never run without a zip to refill it from.
        if (!assetExists(BUNDLE_DIR + "/" + gameName + ZIP_SUFFIX)) {
            Log.i(TAG, "no full asset bundle in this APK for " + gameName
                    + " — keeping existing internal data as-is");
            return;
        }

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

        // supervisor-diag: record unpack progress for jak2 so a failed/partial unpack
        // on the owner's HONOR (no adb) is visible in the exported diag file. jak2-only
        // so jak1 file-side behavior is unchanged.
        final boolean diagUnpack = "jak2".equals(gameName);
        if (diagUnpack) {
            appendJak2Diag("unpack START game=" + gameName + " zip=" + mf.zipName
                    + " expect_files=" + mf.fileCount + " expect_bytes=" + mf.rawBytes);
        }

        final long startMs = System.currentTimeMillis();
        long bytesWritten = 0;
        int filesWritten = 0;
        long lastUiUpdate = -1;
        byte[] buf = new byte[COPY_BUFFER_BYTES];

        AssetManager am = getAssets();
        // STREAMING access → the ~1 GiB archive is never materialised in RAM;
        // ZipInputStream inflates it entry-by-entry as we read.
        try {
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

                if (diagUnpack && (filesWritten % 100) == 0) {
                    appendJak2Diag("unpack progress files=" + filesWritten
                            + " bytes=" + bytesWritten);
                }

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
        } catch (IOException ioe) {
            // supervisor-diag: record the failed/partial unpack for the owner before
            // propagating (the caller surfaces the failure to the UI).
            if (diagUnpack) {
                appendJak2Diag("unpack FAILED files=" + filesWritten
                        + " bytes=" + bytesWritten + " err=" + ioe.getMessage());
            }
            throw ioe;
        }

        // Stamp LAST: only a fully-verified unpack is trusted on next launch.
        writeStamp(stamp, mf.version);

        long elapsedMs = System.currentTimeMillis() - startMs;
        Log.i(TAG, gameName + " asset bundle decompressed: " + filesWritten
                + " files, " + bytesWritten + " bytes in " + elapsedMs
                + "ms (version=" + mf.version + ")");
        if (diagUnpack) {
            appendJak2Diag("unpack DONE files=" + filesWritten + " bytes=" + bytesWritten
                    + " ms=" + elapsedMs);
        }
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
