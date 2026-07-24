#!/usr/bin/env bash
# gpbrf13_reopen9_capture.sh — REOPEN#9 (OWNER PLAYTEST #9): tangent-frame facet fix.
# libgk-only change (tfrag3.frag frisvad_basis fallback + u_pbr_debug==20 viz; common/TFrag3Data.cpp
# Duff/Frisvad tangent backfill + [tan-fallback] counter + pbr_tan_diag.txt file write). NO goal_src /
# CGO / asset change => rebuild libgk, reassemble APK, install (keep app data), deploy_verify, boot,
# load village1 (flythrough unpacks the tfrag ground => [gpbrf-tangent]/[tan-fallback] run), pull the
# device pbr_tan_diag.txt (Honor-obscured-logcat proof channel), capture default + the debug==20
# tangent-fallback-coverage viz. ALL logcat is `timeout`-wrapped (supervisor mandate).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
OUT=.autoport/reports/Grecharged-pbr-realtime-fusion/device
mkdir -p "$OUT"
say(){ echo; echo "######## $* ########"; }
die(){ echo "[gpbrf13 FAIL] $*" >&2; exit 1; }
A(){ $ADB -s $S "$@"; }

say "0. build libgk.so arm64 (tfrag3.frag + common/TFrag3Data.cpp changes)"
cmake --build build-android --target gk -j"$(nproc)" 2>&1 | tail -12
[ -f build-android/lib/arm64-v8a/libgk.so ] || die "libgk.so not built"
echo "  libgk [tan-fallback] strings: $(strings -a build-android/lib/arm64-v8a/libgk.so | grep -c 'tan-fallback')"
echo "  libgk pbr_tan_diag strings:   $(strings -a build-android/lib/arm64-v8a/libgk.so | grep -c 'pbr_tan_diag')"
echo "  libgk frisvad_basis strings:  $(strings -a build-android/lib/arm64-v8a/libgk.so | grep -c 'frisvad_basis')"

say "1. adb server refresh (wedged daemon => false 'not installed')"
"$ADB" kill-server >/dev/null 2>&1 || true; sleep 1; "$ADB" start-server >/dev/null 2>&1 || true; sleep 2
A wait-for-device
echo "  /data free:"; A shell df -h /data | tail -1

say "2. reassemble APK with fresh libgk (no CGO/asset change)"
( cd android && ./gradlew assembleJak1Debug 2>&1 | tail -6 ) || die "gradle assemble failed"
[ -f "$APK" ] || die "APK not produced"

say "3. install APK (keep app data => CGOs persist, no re-extract)"
A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
A shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1' && die "DEVICE_LOCKED — needs owner unlock"
A shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow 2>/dev/null || true
A shell pm trim-caches 999G 2>/dev/null || true
A install -r -d -t -i com.android.vending "$APK" 2>&1 | tail -3 || die "apk install failed"

say "4. deploy_verify (build==APK==device libgk, built-after-source)"
bash .autoport/lib/deploy_verify.sh "$S" 2>&1 | tail -5 || die "deploy_verify FAILED"

say "5. force fused path ON: recharged master + PBR + realtime lighting (props, never touch saved settings)"
A shell setprop debug.opengoal.recharged 1 >/dev/null 2>&1 || true
A shell setprop debug.opengoal.pbr.kill 0 >/dev/null 2>&1 || true
A shell setprop debug.opengoal.pbr.relief 1.6 >/dev/null 2>&1 || true   # relief>0 (the facet trigger)

say "6. cold boot + capture init logcat (timeout-wrapped) — village1 flythrough unpacks the ground"
A logcat -c >/dev/null 2>&1 || true
A shell am force-stop $PKG >/dev/null 2>&1 || true
sleep 1
A shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
timeout 130 $ADB -s $S logcat -v time GK_STDOUT:I opengoal-gk:I '*:S' > "$OUT/gpbrf13_boot_logcat.log" 2>&1 &
LOGPID=$!
sleep 100
timeout 30 $ADB -s $S logcat -d -v time > "$OUT/gpbrf13_full_logcat.log" 2>&1 || true
kill $LOGPID 2>/dev/null || true

say "7. extract the tangent-coverage device-truth (the REOPEN#9 proof)"
{
  echo "===== [gpbrf-tangent] per-tree tangent validity (device) ====="
  grep -aE '\[gpbrf-tangent\]' "$OUT/gpbrf13_boot_logcat.log" "$OUT/gpbrf13_full_logcat.log" | sed 's/.*\[gpbrf-tangent\]/[gpbrf-tangent]/' | sort -u | head -30
  echo
  echo "===== [tan-fallback] GROUND fallback coverage (device) ====="
  grep -aE '\[tan-fallback\]' "$OUT/gpbrf13_boot_logcat.log" "$OUT/gpbrf13_full_logcat.log" | sed 's/.*\[tan-fallback\]/[tan-fallback]/' | sort -u | head -30
  echo
  echo "===== [pbr-tess] tessellation diagnostics ====="
  grep -aE '\[pbr-tess\]' "$OUT/gpbrf13_boot_logcat.log" "$OUT/gpbrf13_full_logcat.log" | sort -u | head
  echo
  echo "===== shader compile errors (must be EMPTY) ====="
  grep -aiE 'Failed to compile|Failed to link|frisvad' "$OUT/gpbrf13_full_logcat.log" | head
  echo "(end)"
} > "$OUT/gpbrf13_diagnostics.txt" 2>&1
cat "$OUT/gpbrf13_diagnostics.txt"

say "8. pull the device pbr_tan_diag.txt (Honor-obscured-logcat channel => run-as file)"
A shell "run-as $PKG cat files/pbr_tan_diag.txt" > "$OUT/gpbrf13_pbr_tan_diag.txt" 2>/dev/null || true
if [ ! -s "$OUT/gpbrf13_pbr_tan_diag.txt" ]; then
  # find it wherever get_jak_project_dir resolved
  A shell "run-as $PKG find . -name pbr_tan_diag.txt 2>/dev/null" | head > "$OUT/gpbrf13_diag_find.txt" 2>/dev/null || true
  DIAGPATH=$(head -1 "$OUT/gpbrf13_diag_find.txt" 2>/dev/null)
  [ -n "$DIAGPATH" ] && A shell "run-as $PKG cat '$DIAGPATH'" > "$OUT/gpbrf13_pbr_tan_diag.txt" 2>/dev/null || true
fi
echo "----- device pbr_tan_diag.txt -----"; cat "$OUT/gpbrf13_pbr_tan_diag.txt" 2>/dev/null || echo "(not pulled)"

say "9. default render capture (screenrecord+ffmpeg — screencap is black on the GL surface)"
A shell 'rm -f /sdcard/gpbrf13_def.mp4' >/dev/null 2>&1 || true
timeout 20 $ADB -s $S shell screenrecord --time-limit 8 --bit-rate 12000000 /sdcard/gpbrf13_def.mp4 || true
sleep 1
A pull /sdcard/gpbrf13_def.mp4 "$OUT/gpbrf13_default.mp4" 2>&1 | tail -1 || true
[ -f "$OUT/gpbrf13_default.mp4" ] && { ffmpeg -y -sseof -2 -i "$OUT/gpbrf13_default.mp4" -frames:v 1 "$OUT/gpbrf13_default.png" >/dev/null 2>&1 || ffmpeg -y -i "$OUT/gpbrf13_default.mp4" -frames:v 1 "$OUT/gpbrf13_default.png" >/dev/null 2>&1 || true; }

say "10. tangent-fallback-coverage VIZ (u_pbr_debug=20: RED=fallback, GREEN=per-vertex tangent)"
A shell setprop debug.opengoal.pbr.debug 20 >/dev/null 2>&1 || true
sleep 3
A shell 'rm -f /sdcard/gpbrf13_viz.mp4' >/dev/null 2>&1 || true
timeout 20 $ADB -s $S shell screenrecord --time-limit 8 --bit-rate 12000000 /sdcard/gpbrf13_viz.mp4 || true
sleep 1
A pull /sdcard/gpbrf13_viz.mp4 "$OUT/gpbrf13_viz.mp4" 2>&1 | tail -1 || true
[ -f "$OUT/gpbrf13_viz.mp4" ] && { ffmpeg -y -sseof -2 -i "$OUT/gpbrf13_viz.mp4" -frames:v 1 "$OUT/gpbrf13_viz.png" >/dev/null 2>&1 || ffmpeg -y -i "$OUT/gpbrf13_viz.mp4" -frames:v 1 "$OUT/gpbrf13_viz.png" >/dev/null 2>&1 || true; }
A shell setprop debug.opengoal.pbr.debug 0 >/dev/null 2>&1 || true

say "11. foreground focus + pid (shared device: must be jak1)"
A shell dumpsys window 2>/dev/null | grep -aE 'mCurrentFocus|mFocusedApp' | grep -ai "$PKG" | head -2 | tee "$OUT/gpbrf13_focus.txt"
A shell pidof $PKG | tee "$OUT/gpbrf13_pid.txt"

echo; echo "[gpbrf13] capture DONE. Evidence in $OUT/"
ls -la "$OUT"/gpbrf13_* 2>/dev/null
