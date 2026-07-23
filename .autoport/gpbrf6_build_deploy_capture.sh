#!/usr/bin/env bash
# gpbrf6_build_deploy_capture.sh — Grecharged-pbr-realtime-fusion REOPEN #6
# (owner playtest #5/#6: the "10cm epoxy float" = POM depth too large -> SURFACE-LOCK
# calibration + tess-K decouple + matte-dielectric default).
#
# libgk-only rebuild (my changes add NO new FFI symbols -> consistent with the on-device
# GOAL) + APK reassemble + install + boot capture. Proves the NEW build renders crash-free.
# The aesthetic call (does the epoxy-float read as surface depth now) is owner_verify on the
# Honor per standing guidance — this script produces OBJECTIVE evidence only.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
OUT=.autoport/reports/Grecharged-pbr-realtime-fusion; DEV="$OUT/device"; mkdir -p "$DEV"
LOG="$DEV/reopen6-boot-logcat.log"
say(){ echo; echo "######## $* ########"; }
die(){ echo "[gpbrf6 FAIL] $*" >&2; exit 1; }
focus(){ $ADB -s $S shell dumpsys window 2>/dev/null | grep -m1 -iE 'mCurrentFocus' | tr -d '\r'; }

say "1. build android libgk (embeds tfrag3.frag SURFACE-LOCK POM clamp + tese TESS_DISP_K + matte gate)"
cmake --build build-android --target gk -j"$(nproc)" 2>&1 | tail -14
[ -f build-android/lib/arm64-v8a/libgk.so ] || die "libgk.so not built"
SL=$(strings -a build-android/lib/arm64-v8a/libgk.so | grep -c 'SURFACE-LOCK')
MG=$(strings -a build-android/lib/arm64-v8a/libgk.so | grep -c 'MATTE-DIELECTRIC')
echo "  libgk embedded shader markers: SURFACE-LOCK=$SL  MATTE-DIELECTRIC=$MG"
[ "$SL" -gt 0 ] || die "new libgk missing SURFACE-LOCK marker (shader edit not embedded in blob)"

say "2. assemble APK (bundles the fresh libgk)"
( cd android && ./gradlew assembleJak1Debug 2>&1 | tail -8 ) || die "gradle assemble failed"
[ -f "$APK" ] || die "APK not produced"

say "3. install APK (MIUI unblock) + verify"
$ADB -s $S shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
$ADB -s $S shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow 2>/dev/null || true
$ADB -s $S shell pm trim-caches 999G 2>/dev/null || true
$ADB -s $S install -r -d -t -i com.android.vending "$APK" 2>&1 | tail -3 || die "apk install failed"

say "4. launch jak1 + capture boot->gameplay"
$ADB -s $S shell am force-stop "$PKG" 2>/dev/null || true
$ADB -s $S logcat -c 2>/dev/null || true
# timeout-wrapped logcat (MANDATED: un-timeouted logcat zombies + wedges the capture)
timeout 240 $ADB -s $S logcat -v time > "$LOG" 2>&1 &
LCPID=$!
$ADB -s $S shell am start -n "$PKG/$ACT" 2>&1 | tail -2
# wait up to ~150s for jak1 foreground
FG=0
for i in $(seq 1 30); do
  sleep 5 2>/dev/null || true
  if focus | grep -q "org.opengoal.gk.jak1"; then FG=1; echo "  jak1 foreground at ~$((i*5))s"; break; fi
done
[ "$FG" = 1 ] || echo "  WARN: jak1 not confirmed foreground (see focus below)"
# let it render to gameplay
sleep 40 2>/dev/null || true
FOCUS_MID=$(focus)
echo "  focus mid: $FOCUS_MID"

say "5. screenrecord (screencap is all-black on the GL surface) + still"
$ADB -s $S shell screenrecord --time-limit 12 /sdcard/gpbrf6_boot.mp4 2>/dev/null &
SRPID=$!
sleep 14 2>/dev/null || true
wait $SRPID 2>/dev/null || true
$ADB -s $S pull /sdcard/gpbrf6_boot.mp4 "$DEV/gpbrf6_boot.mp4" 2>&1 | tail -1
# extract a mid still from the mp4
if command -v ffmpeg >/dev/null 2>&1 && [ -f "$DEV/gpbrf6_boot.mp4" ]; then
  ffmpeg -y -i "$DEV/gpbrf6_boot.mp4" -vf 'select=eq(n\,120)' -vframes 1 "$DEV/gpbrf6_boot.png" >/dev/null 2>&1 || \
  ffmpeg -y -i "$DEV/gpbrf6_boot.mp4" -vframes 1 "$DEV/gpbrf6_boot.png" >/dev/null 2>&1 || true
fi

say "6. objective evidence"
FOCUS_END=$(focus)
echo "FOCUS_END: $FOCUS_END"
echo "--- crash signals (Fatal signal 11/6/4) in our PID window ---"
grep -aE 'Fatal signal (11|6|4)|SIGSEGV|SIGABRT|SIGILL' "$LOG" | grep -v 'signal 9' | tail -10 || echo "  (none)"
echo "--- shader compile / GLES errors ---"
grep -aiE 'shader.*(error|fail)|GL_INVALID|link.*fail|tessellation' "$LOG" | tail -10 || echo "  (none)"
echo "--- frame progression (renderer heartbeat) ---"
grep -aiE 'A35-RENDER|frame [0-9]|render frames|GLES 3' "$LOG" | tail -6 || echo "  (no explicit frame log)"
echo "--- recharged guard / tess fallback lines ---"
grep -aiE 'recharged|crash-loop|tessellation|falling back' "$LOG" | tail -8 || echo "  (none)"
# kill the logcat capture
kill $LCPID 2>/dev/null || true
$ADB -s $S shell rm -f /sdcard/gpbrf6_boot.mp4 2>/dev/null || true
ls -la "$DEV"/gpbrf6_boot.* 2>/dev/null
echo "[gpbrf6 capture DONE]"
