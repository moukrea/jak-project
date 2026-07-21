#!/usr/bin/env bash
# glp_clean_install_verify.sh — OWNER 2026-07-20 REOPEN gate.
# Prove village1.probes ships IN the APK (bundled in the port-custom pack) and is
# extracted on install, so a plain `adb install` (NO separate adb push of .probes)
# loads the probe grid. Deletes every NON-APK probe source first, so the ONLY
# possible source of the loaded grid is the APK's bundled custom pack.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
OUT=.autoport/reports/Grecharged-lightprobes/device; mkdir -p "$OUT"
EXT_FR3=/storage/emulated/0/OpenGOAL/jak1/assets/fr3
say(){ echo; echo "######## $* ########"; }
die(){ echo "[glp-clean FAIL] $*" >&2; exit 1; }

say "0. adb refresh (wedged daemon => false 'not installed')"
"$ADB" kill-server >/dev/null 2>&1 || true; sleep 1; "$ADB" start-server >/dev/null 2>&1 || true; sleep 2
$ADB -s $S wait-for-device
$ADB -s $S shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
if $ADB -s $S shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1'; then die "DEVICE_LOCKED — needs owner unlock"; fi

say "1. reassemble APK so it bundles the new custom pack (fr3/village1.probes)"
( cd android && ./gradlew assembleJak1Debug 2>&1 | tail -10 ) || die "gradle assemble failed"
[ -f "$APK" ] || die "APK missing"

say "1b. PROVE the APK itself carries fr3/village1.probes in its bundled custom pack"
python3 - "$APK" <<'PY' || die "APK does NOT contain fr3/village1.probes"
import sys, zipfile, io
apk = sys.argv[1]
with zipfile.ZipFile(apk) as z:
    cand = [n for n in z.namelist() if n.endswith('jak1_custom.zip')]
    assert cand, "no jak1_custom.zip in APK"
    inner_bytes = z.read(cand[0])
with zipfile.ZipFile(io.BytesIO(inner_bytes)) as inner:
    hits = [m for m in inner.namelist() if m.endswith('village1.probes')]
    assert hits, "custom pack members: %r" % inner.namelist()
    sz = inner.getinfo(hits[0]).file_size
    print("  APK -> assets/%s -> %s  size=%d" % (cand[0], hits[0], sz))
    assert sz > 4096, "probes trivially small"
PY

say "2. remove ALL non-APK probe sources (prove there is NO side-load fallback)"
$ADB -s $S shell "rm -f $EXT_FR3/village1.probes" >/dev/null 2>&1 || true
echo -n "  external assets/fr3 probes after rm: "
$ADB -s $S shell "ls $EXT_FR3/village1.probes 2>/dev/null || echo NONE" | tr -d '\r'
# wipe app-private extraction + stamp so the extractor MUST re-unpack from the APK
$ADB -s $S shell "run-as $PKG rm -rf files/custom files/.custom_pack_stamp_jak1" >/dev/null 2>&1 || true
echo -n "  app-private custom probes after wipe: "
$ADB -s $S shell "run-as $PKG ls files/custom/jak1/fr3/village1.probes 2>/dev/null || echo NONE" | tr -d '\r'

say "3. install -r the fresh APK (MIUI unblock) — NO adb push of any .probes"
$ADB -s $S shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow 2>/dev/null || true
$ADB -s $S shell settings put global verifier_verify_adb_installs 0 >/dev/null 2>&1 || true
$ADB -s $S shell pm trim-caches 999G 2>/dev/null || true
$ADB -s $S install -r -d -t -i com.android.vending "$APK" 2>&1 | tail -3 || die "apk install failed"

say "4. boot + capture the probe load (must come from the APK-extracted custom dir)"
$ADB -s $S shell am force-stop $PKG >/dev/null 2>&1 || true
$ADB -s $S logcat -c >/dev/null 2>&1 || true
LOG="$OUT/glp-clean-install-logcat.log"; : > "$LOG"
( $ADB -s $S logcat -v threadtime GK_STDOUT:I GK_STDERR:I opengoal-gk:I '*:S' \
   | grep --line-buffered -aE 'A35-RENDER frame=|link finish|lightprobe|custom.?pack|unpack|Fatal signal|signal [0-9]+ \(SIG|GK-DIAG sig=' >> "$LOG" ) 2>/dev/null &
LCP=$!
trap 'kill ${LCP:-0} 2>/dev/null || true' EXIT
$ADB -s $S shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
t0=$(date +%s); loaded=0; rendered=0
while [ $(( $(date +%s) - t0 )) -lt 900 ]; do
  if grep -aqE 'GK-DIAG sig=11|Fatal signal (11|6|4)|signal (11|6|4) \(SIG' "$LOG"; then echo "  CRASH during boot"; break; fi
  grep -aqiE "lightprobe.*loaded.*custom/jak1/fr3/village1\.probes" "$LOG" && loaded=1
  rf=$(grep -acE 'A35-RENDER frame=' "$LOG" 2>/dev/null); rf=${rf:-0}
  [ "$rf" -ge 5 ] 2>/dev/null && rendered=1
  [ "$loaded" = 1 ] && [ "$rendered" = 1 ] && break
  sleep 5
done

say "5. verify the extracted probes are at the APK custom dir (run-as), no external file"
DEV_CUSTOM=$($ADB -s $S shell "run-as $PKG stat -c%s files/custom/jak1/fr3/village1.probes 2>/dev/null" | tr -d '\r')
DEV_EXT=$($ADB -s $S shell "ls $EXT_FR3/village1.probes 2>/dev/null || echo NONE" | tr -d '\r')
echo "  extracted custom probes size = ${DEV_CUSTOM:-MISSING}  (local 35992599)"
echo "  external side-load probes     = ${DEV_EXT}"
LOADED_LINE=$(grep -aiE "lightprobe.*loaded" "$LOG" | tail -1)
echo "  loaded line: $LOADED_LINE"

say "6. capture a device still + short clip + focus"
$ADB -s $S shell screencap -p /sdcard/glp_clean.png >/dev/null 2>&1 || true
$ADB -s $S pull /sdcard/glp_clean.png "$OUT/glp_clean_install.png" >/dev/null 2>&1 || true
( $ADB -s $S shell screenrecord --time-limit 6 /sdcard/glp_clean.mp4 >/dev/null 2>&1; \
  $ADB -s $S pull /sdcard/glp_clean.mp4 "$OUT/glp_clean_install.mp4" >/dev/null 2>&1 ) || true
FOCUS=$($ADB -s $S shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r')
echo "  focus=$FOCUS"

echo
echo "==== VERDICT ===="
case "$FOCUS" in *org.opengoal.gk.jak1*) : ;; *) die "app not foreground: $FOCUS" ;; esac
[ "${DEV_CUSTOM:-0}" = "35992599" ] || die "extracted custom probes size wrong/missing (got '${DEV_CUSTOM:-MISSING}')"
[ "$DEV_EXT" = "NONE" ] || die "external side-load probes still present ($DEV_EXT) — not a clean no-side-load proof"
[ "$loaded" = 1 ] || die "did not observe lightprobe load from the custom (APK) dir"
echo "[glp-clean] PASS — clean install-only: village1.probes extracted FROM THE APK to"
echo "            files/custom/jak1/fr3/village1.probes and loaded by LightProbeGrid,"
echo "            with the external side-load deleted. NO adb push of .probes."
