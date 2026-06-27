#!/usr/bin/env bash
# Phase Gpkg-distributable device test (autoport 2026-06-27).
# Builds the FULL (non-slim) jak1 APK that ships the COMPRESSED asset bundle,
# proves the bundle is stored compressed in the APK, installs it, and exercises:
#   FIRST RUN  : no on-device stamp -> decompress UI + unpack 1.34 GiB -> boot
#   SECOND RUN : stamp present, version matches -> skip decompress, boot directly
# Then runs deploy_verify. All artifacts land in this directory.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

R=.autoport/reports/Gpkg-distributable
mkdir -p "$R"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
SERIAL=eae4df44
PKG=org.opengoal.gk.jak1
export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-/home/emeric/Android/android-ndk-r27c}"
A() { "$ADB" -s "$SERIAL" "$@"; }
say() { echo "=== $* ==="; }

# ----------------------------------------------------------------------------
say "1. BUILD full (non-slim) APK with the compressed bundle"
( cd android && ./gradlew --no-daemon assembleJak1Debug ) > "$R/10-gradle.log" 2>&1
GRC=$?
echo "gradle_rc=$GRC" | tee "$R/10-gradle-rc.txt"
tail -3 "$R/10-gradle.log"
[ $GRC -eq 0 ] || { echo "BUILD FAILED"; exit 1; }

APK=$(find android -name 'app-jak1-debug.apk' -printf '%T@ %p\n' | sort -rn | head -1 | cut -d' ' -f2-)
echo "APK=$APK"
APK_BYTES=$(stat -c %s "$APK")
echo "apk_bytes=$APK_BYTES  ($(awk "BEGIN{printf \"%.0f\", $APK_BYTES/1048576}") MiB)" | tee "$R/11-apk-size.txt"

# ----------------------------------------------------------------------------
say "2. PROVE the bundle is in the APK, STORED (compressed payload, not raw dirs)"
# zipinfo: column shows method 'stor' for the already-DEFLATE'd bundle.
"$ADB" version >/dev/null 2>&1
unzip -l "$APK" | grep -E 'assets/bundle/' | tee "$R/12-apk-bundle-entries.txt"
echo "--- compression method of the bundle (expect 'stor') ---" | tee -a "$R/12-apk-bundle-entries.txt"
zipinfo "$APK" 'assets/bundle/jak1_assets.zip' 2>/dev/null | tee -a "$R/12-apk-bundle-entries.txt"
echo "--- raw iso_data dirs must be ABSENT from the APK (only the zip ships) ---" | tee -a "$R/12-apk-bundle-entries.txt"
RAW_IN_APK=$(unzip -l "$APK" | grep -cE 'assets/iso_data/' || true)
echo "raw_iso_data_entries_in_apk=$RAW_IN_APK (expect 0)" | tee -a "$R/12-apk-bundle-entries.txt"

# ----------------------------------------------------------------------------
say "3. INSTALL the APK (MIUI-unblocked attribution)"
A shell cmd appops set com.android.shell REQUEST_INSTALL_PACKAGES allow >/dev/null 2>&1 || true
A install -r -d -t -i com.android.vending "$APK" > "$R/13-install.txt" 2>&1
tail -2 "$R/13-install.txt"

# ----------------------------------------------------------------------------
say "4. FIRST RUN — wipe on-device unpacked data + stamp to force decompress"
A shell am force-stop "$PKG" >/dev/null 2>&1
# NB: the whole `run-as ... sh -c '...'` must reach the device as ONE adb-shell
# argument, else adb's arg-join splits the `-c` payload ("sh: -c: requires an
# argument"). Wrap it in an outer double-quoted string.
A shell "run-as $PKG sh -c 'rm -f files/.asset_bundle_stamp; rm -rf files/iso_data files/out/jak1/fr3'" 2>&1 | tee "$R/14-prewipe.txt"
echo "--- confirm no stamp + no iso_data before launch ---" | tee -a "$R/14-prewipe.txt"
A shell "run-as $PKG sh -c 'ls -la files/.asset_bundle_stamp 2>&1; ls files/iso_data 2>&1'" | tee -a "$R/14-prewipe.txt"

A logcat -c >/dev/null 2>&1
A shell am start -n "$PKG/.LoaderActivity" > "$R/15-firstrun-amstart.txt" 2>&1
# capture progress UI mid-decompress
sleep 6
A shell dumpsys window 2>/dev/null | grep -E 'mCurrentFocus' | tee "$R/16-firstrun-focus.txt"
A shell screencap -p /sdcard/gpkg_firstrun_progress.png 2>/dev/null
A pull /sdcard/gpkg_firstrun_progress.png "$R/16-firstrun-progress.png" >/dev/null 2>&1
# capture the whole decompress + boot window
A logcat -d > "$R/17-firstrun-logcat-early.log" 2>&1
echo "[waiting up to 240s for decompress + boot marker]"
for i in $(seq 1 40); do
  sleep 6
  A logcat -d > "$R/17-firstrun-logcat.log" 2>&1
  if grep -aqE 'asset bundle decompressed' "$R/17-firstrun-logcat.log" && \
     grep -aqE 'link finish: *logo|\[display\]|GOAL frame|engine.*frame' "$R/17-firstrun-logcat.log"; then
    echo "  first-run decompress+boot markers seen at ~$((i*6))s"
    break
  fi
done
echo "--- decompress evidence (opengoal-gk loader lines) ---" | tee "$R/18-firstrun-summary.txt"
grep -aE 'opengoal-gk|Decompressing|asset bundle|storage ok|integrity' "$R/17-firstrun-logcat.log" | tee -a "$R/18-firstrun-summary.txt"
echo "--- boot marker ---" | tee -a "$R/18-firstrun-summary.txt"
grep -aE 'link finish: *logo' "$R/17-firstrun-logcat.log" | head -3 | tee -a "$R/18-firstrun-summary.txt"

say "5. VERIFY on-device unpacked state after first run"
A shell "run-as $PKG sh -c 'echo stamp=\$(cat files/.asset_bundle_stamp 2>/dev/null); echo iso_data_jak1_files=\$(ls files/iso_data/jak1 | wc -l); echo out_jak1_fr3_files=\$(ls files/out/jak1/fr3 2>/dev/null | wc -l); echo iso_data_size=\$(du -sh files/iso_data 2>/dev/null | cut -f1)'" 2>&1 | tee "$R/19-firstrun-ondevice.txt"

# ----------------------------------------------------------------------------
say "6. SECOND RUN — stamp present, must SKIP decompress and boot directly"
A shell am force-stop "$PKG" >/dev/null 2>&1
sleep 2
A logcat -c >/dev/null 2>&1
SECOND_START=$(date +%s)
A shell am start -n "$PKG/.LoaderActivity" > "$R/20-secondrun-amstart.txt" 2>&1
for i in $(seq 1 20); do
  sleep 5
  A logcat -d > "$R/21-secondrun-logcat.log" 2>&1
  if grep -aqE 'already unpacked' "$R/21-secondrun-logcat.log"; then break; fi
done
echo "--- second-run loader decision (expect 'already unpacked ... skipping decompress, data ready') ---" | tee "$R/22-secondrun-summary.txt"
grep -aE 'opengoal-gk|already unpacked|Decompressing|asset bundle' "$R/21-secondrun-logcat.log" | tee -a "$R/22-secondrun-summary.txt"
echo "--- second run must NOT contain 'Decompressing'/'decompressed' (idempotent skip) ---" | tee -a "$R/22-secondrun-summary.txt"
DECOMP2=$(grep -acE 'asset bundle decompressed|Decompressing game data' "$R/21-secondrun-logcat.log" || true)
echo "second_run_decompress_lines=$DECOMP2 (expect 0)" | tee -a "$R/22-secondrun-summary.txt"

# ----------------------------------------------------------------------------
say "7. DEPLOY VERIFY (device provably runs fresh HEAD libgk.so)"
bash .autoport/lib/deploy_verify.sh "$SERIAL" 2>&1 | tee "$R/23-deploy-verify.txt"
echo "deploy_verify_rc=${PIPESTATUS[0]}" | tee -a "$R/23-deploy-verify.txt"

say "DEVICE TEST COMPLETE — artifacts in $R"
