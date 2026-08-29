package org.opengoal.gk;

import android.content.Context;
import android.content.SharedPreferences;
import android.net.ConnectivityManager;
import android.net.NetworkCapabilities;
import android.util.Log;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/**
 * Grecharged-managed-assets: downloads the remastered texture packs published
 * at github.com/moukrea/recharged-assets into the app's private storage, so
 * they no longer have to be embedded in the APK.
 *
 * Why here and not in native code: the Android build ships no TLS stack on
 * purpose (libcurl is excluded in android/CMakeLists.txt), and the first-launch
 * flow with its progress UI already lives in LoaderActivity. This class only
 * does transport + verification; the resulting directory is exactly the layout
 * the shared C++ installer and loader expect (state.json + *.rpack), which is
 * also what tools/install_pack.py produces on desktop.
 *
 * Landing zone: {@code <filesDir>/managed_assets/<game>/}. Deliberately NOT
 * {@code <filesDir>/custom/<game>/} — that one is wiped on every APK version
 * change, which would throw away a multi-hundred-MB download on each update.
 *
 * Safety: shards download to {@code staging/} as {@code .part} files with HTTP
 * Range resume, are checked against the manifest's size + SHA-256, and only
 * then moved next to a {@code state.json} that is written last, by rename. An
 * interrupted run always leaves the previous installation usable.
 */
public final class AssetPackDownloader {
    private static final String TAG = "opengoal-gk";
    /**
     * Gpbr-material-props: extras this build knows how to install. Anything else is skipped rather
     * than treated as an error, so a newer release stays installable by an older APK.
     */
    private static final java.util.Set<String> KNOWN_EXTRA_KINDS =
            Collections.singleton("surfaces");
    private static final int CONNECT_TIMEOUT_MS = 20_000;
    private static final int READ_TIMEOUT_MS = 60_000;
    private static final int BUF = 1 << 16;

    /** Progress sink; called from the worker thread. */
    public interface Listener {
        void onProgress(String what, int shardIndex, int shardCount, long bytesDone,
                        long bytesTotal);
    }

    public static final class Result {
        public boolean ok;
        public boolean skipped;      // nothing to do, or intentionally not attempted
        public String message = "";
        public int downloaded;
        public int kept;
        public int removed;
    }

    private final Context ctx;
    private final String game;
    private final Listener listener;

    public AssetPackDownloader(Context ctx, String game, Listener listener) {
        this.ctx = ctx;
        this.game = game;
        this.listener = listener;
    }

    public File targetDir() {
        return new File(ctx.getFilesDir(), "managed_assets/" + game);
    }

    /** True when a verified pack is already installed. */
    public boolean isInstalled() {
        return new File(targetDir(), "state.json").isFile();
    }

    private boolean isUnmetered() {
        ConnectivityManager cm =
                (ConnectivityManager) ctx.getSystemService(Context.CONNECTIVITY_SERVICE);
        if (cm == null) {
            return false;
        }
        NetworkCapabilities caps = cm.getNetworkCapabilities(cm.getActiveNetwork());
        return caps != null
                && caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
                && caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET);
    }

    /**
     * Read assets.lock.json from the APK, fetch + hash-check its manifest, then
     * install the shards for {@code profile}/{@code preset}.
     *
     * @param wifiOnly    refuse to start on a metered network
     * @param withPbr     also install the material-map shards
     * @param cancelled   polled between shards
     */
    public Result run(String profile, String preset, boolean wifiOnly, boolean withPbr,
                      java.util.concurrent.atomic.AtomicBoolean cancelled) {
        Result r = new Result();
        try {
            JSONObject lock = readLockFromApk();
            if (lock == null) {
                r.skipped = true;
                r.message = "no assets.lock.json in this build";
                return r;
            }
            if (wifiOnly && !isUnmetered()) {
                r.skipped = true;
                r.message = "waiting for an unmetered network";
                return r;
            }

            String manifestUrl = lock.getString("manifest_url");
            String manifestSha = lock.getString("manifest_sha256");
            byte[] manifestBytes = fetch(manifestUrl);
            String gotSha = sha256Hex(manifestBytes);
            if (!gotSha.equals(manifestSha)) {
                r.message = "manifest hash mismatch (expected " + manifestSha + ", got " + gotSha
                        + ")";
                return r;
            }
            JSONObject manifest = new JSONObject(new String(manifestBytes, "UTF-8"));
            if (manifest.getInt("schema_version") != 1) {
                r.message = "unsupported manifest schema_version";
                return r;
            }

            // ---- resolve the wanted shard set --------------------------------
            JSONArray all = manifest.getJSONArray("shards");
            List<JSONObject> wanted = new ArrayList<>();
            long totalBytes = 0;
            for (int i = 0; i < all.length(); i++) {
                JSONObject s = all.getJSONObject(i);
                if (!s.getString("game").equals(game)
                        || !s.getString("profile").equals(profile)
                        || !s.getString("preset").equals(preset)) {
                    continue;
                }
                JSONArray needs = s.optJSONArray("requires_features");
                if (needs != null && needs.length() > 0 && !withPbr) {
                    continue;  // material shards on a build without the PBR path
                }
                String name = s.getString("name");
                if (name.contains("/") || name.contains("\\") || name.contains("..")) {
                    r.message = "unsafe shard name in manifest: " + name;
                    return r;
                }
                wanted.add(s);
                totalBytes += s.getLong("size");
            }
            // NOTE (Gpbr-material-props): the "no shards" early return used to sit HERE, before
            // the extras were even looked at. It is moved below the extras resolution on purpose:
            // an extra is per-game, never per profile/preset, so a selection that matches no shard
            // can still owe the surface table. Returning early would have made the properties
            // silently absent on exactly the configurations that need them most (a device whose
            // profile/preset combination has no pack). Same fix as AssetCli's plan.up_to_date().

            // ---- resolve the wanted extras -----------------------------------
            // Small non-shard files installed beside the packs (the per-material surface table).
            // `extras` is optional: every manifest published so far predates it, so its absence
            // must change nothing at all. An extra is per-game and per-feature, never per profile
            // or preset — material properties do not depend on texture size or GPU format.
            JSONArray allExtras = manifest.optJSONArray("extras");
            List<JSONObject> wantedExtras = new ArrayList<>();
            for (int i = 0; allExtras != null && i < allExtras.length(); i++) {
                JSONObject e = allExtras.optJSONObject(i);
                if (e == null || !game.equals(e.optString("game"))) {
                    continue;
                }
                JSONArray extraNeeds = e.optJSONArray("requires_features");
                if (extraNeeds != null && extraNeeds.length() > 0 && !withPbr) {
                    continue;
                }
                if (!KNOWN_EXTRA_KINDS.contains(e.optString("kind"))) {
                    Log.i(TAG, "managed assets: ignoring extra of unknown kind "
                            + e.optString("kind"));
                    continue;
                }
                String extraName = e.optString("name");
                if (extraName.isEmpty() || e.optString("url").isEmpty()
                        || e.optString("sha256").length() != 64 || e.optLong("size") <= 0) {
                    Log.w(TAG, "managed assets: skipping extra with missing/bad fields: "
                            + extraName);
                    continue;
                }
                // Same guard as the shards: this name becomes a path inside the install directory.
                if (extraName.contains("/") || extraName.contains("\\")
                        || extraName.contains("..")) {
                    Log.w(TAG, "managed assets: skipping extra with unsafe name: " + extraName);
                    continue;
                }
                wantedExtras.add(e);
            }

            if (wanted.isEmpty() && wantedExtras.isEmpty()) {
                r.skipped = true;
                r.message = "no shards or extras for " + profile + "/" + preset;
                return r;
            }

            File dir = targetDir();
            File staging = new File(dir, "staging");
            if (!dir.isDirectory() && !dir.mkdirs()) {
                r.message = "cannot create " + dir;
                return r;
            }
            staging.mkdirs();

            // ---- download what is missing ------------------------------------
            List<String> installed = new ArrayList<>();
            long done = 0;
            long toDownload = 0;
            for (JSONObject s : wanted) {
                File f = new File(dir, s.getString("name"));
                if (!(f.isFile() && f.length() == s.getLong("size"))) {
                    toDownload += s.getLong("size");
                }
            }
            for (JSONObject e : wantedExtras) {
                File f = new File(dir, e.getString("name"));
                if (!(f.isFile() && f.length() == e.getLong("size"))) {
                    toDownload += e.getLong("size");
                }
            }
            if (toDownload > 0) {
                long free = dir.getUsableSpace();
                if (free < toDownload + toDownload / 10) {
                    r.message = "not enough free space: " + (free >> 20) + " MiB available, "
                            + (toDownload >> 20) + " MiB needed";
                    return r;
                }
            }
            for (int i = 0; i < wanted.size(); i++) {
                JSONObject s = wanted.get(i);
                String name = s.getString("name");
                long size = s.getLong("size");
                File finalFile = new File(dir, name);
                // Shard names carry their content hash, so a file of the right
                // size is already the right content.
                if (finalFile.isFile() && finalFile.length() == size) {
                    installed.add(name);
                    r.kept++;
                    continue;
                }
                if (cancelled != null && cancelled.get()) {
                    r.message = "cancelled";
                    return r;  // previous install untouched, staging kept for resume
                }
                if (listener != null) {
                    listener.onProgress(name, i, wanted.size(), done, toDownload);
                }
                File part = new File(staging, name);
                downloadResumable(s.getString("url"), part, size);
                if (part.length() != size) {
                    part.delete();
                    r.message = "size mismatch for " + name;
                    return r;
                }
                if (!sha256Hex(part).equals(s.getString("sha256"))) {
                    part.delete();
                    r.message = "sha256 mismatch for " + name;
                    return r;
                }
                if (!part.renameTo(finalFile)) {
                    r.message = "cannot install " + name;
                    return r;
                }
                done += size;
                installed.add(name);
                r.downloaded++;
            }

            // ---- the extras, under the exact same contract as a shard ---------
            List<String> installedExtras = new ArrayList<>();
            for (int i = 0; i < wantedExtras.size(); i++) {
                JSONObject e = wantedExtras.get(i);
                String name = e.getString("name");
                long size = e.getLong("size");
                File finalFile = new File(dir, name);
                // Presence by CONTENT, not by size — an extra keeps ONE name across releases
                // (surfaces.json), unlike a shard whose name carries its content hash. A retuned
                // table that happens to serialise to the same byte count would otherwise be
                // judged already-installed and never fetched. 60 KB of SHA-256 is free; a
                // silently-not-updated material table is not.
                if (finalFile.isFile() && finalFile.length() == size
                        && sha256Hex(finalFile).equals(e.getString("sha256"))) {
                    installedExtras.add(name);
                    r.kept++;
                    continue;
                }
                if (cancelled != null && cancelled.get()) {
                    r.message = "cancelled";
                    return r;  // previous install untouched, staging kept for resume
                }
                if (listener != null) {
                    listener.onProgress(name, i, wantedExtras.size(), done, toDownload);
                }
                File part = new File(staging, name);
                downloadResumable(e.getString("url"), part, size);
                if (part.length() != size) {
                    part.delete();
                    r.message = "size mismatch for " + name;
                    return r;
                }
                if (!sha256Hex(part).equals(e.getString("sha256"))) {
                    part.delete();
                    r.message = "sha256 mismatch for " + name;
                    return r;
                }
                if (!part.renameTo(finalFile)) {
                    r.message = "cannot install " + name;
                    return r;
                }
                done += size;
                installedExtras.add(name);
                r.downloaded++;
            }

            // ---- atomic switch, then GC --------------------------------------
            List<String> previous = readInstalledShards(dir);
            List<String> previousExtras = readStateNames(dir, "extras");
            Collections.sort(installed);
            JSONObject state = new JSONObject();
            state.put("schema_version", 1);
            state.put("asset_version", manifest.getString("asset_version"));
            state.put("profile", profile);
            state.put("preset", preset);
            state.put("verified", true);
            state.put("shards", new JSONArray(installed));
            // Its own key: the loader opens every name under "shards" as an RPACK, and a JSON file
            // in there would warn on every scan.
            Collections.sort(installedExtras);
            state.put("extras", new JSONArray(installedExtras));
            File tmpState = new File(dir, "state.json.new");
            try (FileOutputStream out = new FileOutputStream(tmpState)) {
                out.write(state.toString(1).getBytes("UTF-8"));
                out.getFD().sync();
            }
            if (!tmpState.renameTo(new File(dir, "state.json"))) {
                tmpState.delete();
                r.message = "cannot switch state.json";
                return r;  // the old install is still the current one
            }
            for (String old : previous) {
                // An extra is not content-addressed: it keeps the same installed name across asset
                // versions, so a stale entry must never delete the file just installed.
                if (installedExtras.contains(old) || previousExtras.contains(old)) {
                    continue;
                }
                if (!installed.contains(old) && new File(dir, old).delete()) {
                    r.removed++;
                }
            }
            deleteRecursive(staging);

            r.ok = true;
            r.message = manifest.getString("asset_version") + " (" + r.downloaded + " downloaded, "
                    + r.kept + " kept, " + r.removed + " removed)";
            Log.i(TAG, "managed assets: installed " + r.message);
            return r;
        } catch (Throwable t) {
            Log.e(TAG, "managed assets: install failed", t);
            r.message = String.valueOf(t.getMessage());
            return r;
        }
    }

    // ---------------------------------------------------------------- io

    private JSONObject readLockFromApk() throws IOException, org.json.JSONException {
        try (InputStream in = ctx.getAssets().open("assets.lock.json")) {
            java.io.ByteArrayOutputStream bos = new java.io.ByteArrayOutputStream();
            byte[] buf = new byte[BUF];
            int n;
            while ((n = in.read(buf)) > 0) {
                bos.write(buf, 0, n);
            }
            return new JSONObject(new String(bos.toByteArray(), "UTF-8"));
        } catch (IOException e) {
            return null;  // no lock shipped: the feature is dormant
        }
    }

    private static HttpURLConnection open(String url) throws IOException {
        HttpURLConnection c = (HttpURLConnection) new URL(url).openConnection();
        c.setConnectTimeout(CONNECT_TIMEOUT_MS);
        c.setReadTimeout(READ_TIMEOUT_MS);
        c.setInstanceFollowRedirects(true);  // release assets redirect to a CDN
        return c;
    }

    private static byte[] fetch(String url) throws IOException {
        HttpURLConnection c = open(url);
        try (InputStream in = c.getInputStream()) {
            if (c.getResponseCode() / 100 != 2) {
                throw new IOException("HTTP " + c.getResponseCode() + " for " + url);
            }
            java.io.ByteArrayOutputStream bos = new java.io.ByteArrayOutputStream();
            byte[] buf = new byte[BUF];
            int n;
            while ((n = in.read(buf)) > 0) {
                bos.write(buf, 0, n);
            }
            return bos.toByteArray();
        } finally {
            c.disconnect();
        }
    }

    /** Append-resume onto {@code dest} using a Range request. */
    private static void downloadResumable(String url, File dest, long expectedSize)
            throws IOException {
        long have = dest.isFile() ? dest.length() : 0;
        if (have > expectedSize) {
            dest.delete();
            have = 0;
        }
        if (have == expectedSize) {
            return;
        }
        HttpURLConnection c = open(url);
        if (have > 0) {
            c.setRequestProperty("Range", "bytes=" + have + "-");
        }
        try {
            int code = c.getResponseCode();
            if (code / 100 != 2) {
                throw new IOException("HTTP " + code + " for " + url);
            }
            // A server that ignored the Range restarts the body from zero.
            boolean append = have > 0 && code == HttpURLConnection.HTTP_PARTIAL;
            if (have > 0 && !append) {
                Log.w(TAG, "managed assets: server ignored Range, restarting " + dest.getName());
            }
            try (InputStream in = c.getInputStream();
                 FileOutputStream out = new FileOutputStream(dest, append)) {
                byte[] buf = new byte[BUF];
                int n;
                while ((n = in.read(buf)) > 0) {
                    out.write(buf, 0, n);
                }
                out.getFD().sync();
            }
        } finally {
            c.disconnect();
        }
    }

    private static List<String> readInstalledShards(File dir) {
        return readStateNames(dir, "shards");  // shards only: extras live under their own key
    }

    private static List<String> readStateNames(File dir, String key) {
        List<String> out = new ArrayList<>();
        File f = new File(dir, "state.json");
        if (!f.isFile()) {
            return out;
        }
        try (InputStream in = new java.io.FileInputStream(f)) {
            java.io.ByteArrayOutputStream bos = new java.io.ByteArrayOutputStream();
            byte[] buf = new byte[BUF];
            int n;
            while ((n = in.read(buf)) > 0) {
                bos.write(buf, 0, n);
            }
            JSONArray a = new JSONObject(new String(bos.toByteArray(), "UTF-8"))
                    .optJSONArray(key);
            for (int i = 0; a != null && i < a.length(); i++) {
                out.add(a.getString(i));
            }
        } catch (Throwable ignored) {
            // an unreadable state is treated as "nothing installed"
        }
        return out;
    }

    private static void deleteRecursive(File f) {
        if (f == null || !f.exists()) {
            return;
        }
        File[] kids = f.listFiles();
        if (kids != null) {
            for (File k : kids) {
                deleteRecursive(k);
            }
        }
        f.delete();
    }

    // ---------------------------------------------------------------- hash

    private static String hex(byte[] d) {
        StringBuilder sb = new StringBuilder(d.length * 2);
        for (byte b : d) {
            sb.append(Character.forDigit((b >> 4) & 0xF, 16));
            sb.append(Character.forDigit(b & 0xF, 16));
        }
        return sb.toString();
    }

    private static String sha256Hex(byte[] data) throws Exception {
        return hex(MessageDigest.getInstance("SHA-256").digest(data));
    }

    private static String sha256Hex(File f) throws Exception {
        MessageDigest md = MessageDigest.getInstance("SHA-256");
        try (InputStream in = new java.io.FileInputStream(f)) {
            byte[] buf = new byte[BUF];
            int n;
            while ((n = in.read(buf)) > 0) {
                md.update(buf, 0, n);
            }
        }
        return hex(md.digest());
    }
}
