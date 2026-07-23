#!/usr/bin/env bash
# gpbrf7_capture.sh — Grecharged-pbr-realtime-fusion REOPEN#7 (owner: TANGENT BASIS foundation fix).
# libgk-only rebuild already done by the manager; this ASSEMBLES + INSTALLS the APK and captures the
# objective device evidence on the Redmi (Adreno 618):
#   1. crash-free PBR render + jak1 foreground (the bar)
#   2. [gpbrf-tangent] per-tree load log  => per-vertex tangents COMPUTED on device (un-fakeable)
#   3. [recharged] REOPEN#7 TESS ...       => the tessellation loader-name resolution (EXT/OES) result
#   4. displacement=2 (Tessellation)       => actually runs, or the captured GL error / fallback line
#   5. relief A/B (relief 0 vs 3.0)        => coherent relief with NO contrast cracks (owner #7 gate)
# ALL logcat is timeout-wrapped (owner harness mandate: un-timeouted logcat zombies + wedges capture).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
OUT=.autoport/reports/Grecharged-pbr-realtime-fusion; DEV="$OUT/device"; mkdir -p "$DEV"
say(){ echo; echo "######## $* ########"; }
die(){ echo "[gpbrf7 FAIL] $*" >&2; exit 1; }
focus(){ $ADB -s $S shell dumpsys window 2>/dev/null | grep -m1 -iE 'mCurrentFocus' | tr -d '\r'; }
setp(){ $ADB -s $S shell setprop "$1" "$2" 2>/dev/null || true; }
# record N seconds of screen -> pull to $2, extract a mid still to $3
rec(){ local secs="$1" mp4="$2" png="$3"
  $ADB -s $S shell screenrecord --time-limit "$secs" /sdcard/r7.mp4 2>/dev/null &
  local sr=$!; sleep $((secs+2)) 2>/dev/null || true; wait $sr 2>/dev/null || true
  $ADB -s $S pull /sdcard/r7.mp4 "$mp4" 2>&1 | tail -1
  if command -v ffmpeg >/dev/null 2>&1 && [ -f "$mp4" ]; then
    ffmpeg -y -i "$mp4" -vf 'select=eq(n\,90)' -vframes 1 "$png" >/dev/null 2>&1 || \
    ffmpeg -y -i "$mp4" -vframes 1 "$png" >/dev/null 2>&1 || true
  fi
  $ADB -s $S shell rm -f /sdcard/r7.mp4 2>/dev/null || true
}

say "0. adb refresh"
$ADB kill-server >/dev/null 2>&1 || true; sleep 1; $ADB start-server >/dev/null 2>&1 || true; sleep 2
$ADB -s $S wait-for-device
[ -f build-android/lib/arm64-v8a/libgk.so ] || die "libgk.so not built (run the manager's build first)"

say "1. assemble + install APK (bundles fresh REOPEN#7 libgk)"
( cd android && ./gradlew assembleJak1Debug 2>&1 | tail -6 ) || die "gradle assemble failed"
[ -f "$APK" ] || die "APK not produced"
$ADB -s $S shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
if $ADB -s $S shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1'; then die "DEVICE_LOCKED — needs owner unlock"; fi
$ADB -s $S shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow 2>/dev/null || true
$ADB -s $S shell settings put global verifier_verify_adb_installs 0 >/dev/null 2>&1 || true
$ADB -s $S shell pm trim-caches 999G 2>/dev/null || true
$ADB -s $S install -r -d -t -i com.android.vending "$APK" 2>&1 | tail -3 || die "apk install failed"

say "2. deploy_verify (build==APK==device libgk)"
bash .autoport/lib/deploy_verify.sh "$S" jak1 2>&1 | tail -6 || echo "  (deploy_verify non-zero — continuing, will judge on device markers)"

# default PBR-on look: realtime + pbr ON, displacement Parallax, relief default.
setp debug.opengoal.pbr.displacement 1
setp debug.opengoal.pbr.relief 1.5
$ADB -s $S shell setprop debug.opengoal.pbr.nstrength "" 2>/dev/null || true

say "3. BOOT + full logcat (captures the tangent load log + tess loader-name resolution at shader build)"
$ADB -s $S shell am force-stop "$PKG" 2>/dev/null || true
$ADB -s $S logcat -c 2>/dev/null || true
BOOTLOG="$DEV/r7-boot-logcat.log"; : > "$BOOTLOG"
timeout 200 $ADB -s $S logcat -v time > "$BOOTLOG" 2>&1 &
BLP=$!
$ADB -s $S shell am start -n "$PKG/$ACT" 2>&1 | tail -2
FG=0
for i in $(seq 1 30); do
  sleep 5 2>/dev/null || true
  if focus | grep -q "org.opengoal.gk.jak1"; then FG=1; echo "  jak1 foreground at ~$((i*5))s"; break; fi
done
sleep 45 2>/dev/null || true   # let it render the attract flythrough (PBR village)
say "4. capture DEFAULT fused render (relief on, parallax)"
rec 12 "$DEV/r7_default.mp4" "$DEV/r7_default.png"
FOCUS_DEF=$(focus); echo "  focus(default)=$FOCUS_DEF"

say "5. relief A/B for the CRACK gate — relief 0 (flat) vs 3.0 (max). New continuous TBN => no cracks at max."
setp debug.opengoal.pbr.relief 0.0; sleep 3
rec 8 "$DEV/r7_relief0.mp4" "$DEV/r7_relief0.png"
setp debug.opengoal.pbr.relief 3.0; sleep 3
rec 8 "$DEV/r7_relief_max.mp4" "$DEV/r7_relief_max.png"
setp debug.opengoal.pbr.relief 1.5

say "6. normal-map A/B (nstrength 0 => flat, 3 => sculpted) proves the vertex-TBN drives detail"
setp debug.opengoal.pbr.nstrength 0.0; sleep 3
rec 6 "$DEV/r7_n0.mp4" "$DEV/r7_n0.png"
setp debug.opengoal.pbr.nstrength 3.0; sleep 3
rec 6 "$DEV/r7_n3.mp4" "$DEV/r7_n3.png"
$ADB -s $S shell setprop debug.opengoal.pbr.nstrength "" 2>/dev/null || true

say "7. TESSELLATION test: force displacement=2, capture whether it runs or falls back"
$ADB -s $S logcat -c 2>/dev/null || true
TESSLOG="$DEV/r7-tess-logcat.log"; : > "$TESSLOG"
timeout 60 $ADB -s $S logcat -v time > "$TESSLOG" 2>&1 &
TLP=$!
setp debug.opengoal.pbr.displacement 2; sleep 8
rec 8 "$DEV/r7_tess.mp4" "$DEV/r7_tess.png"
setp debug.opengoal.pbr.displacement 1
sleep 2; kill $TLP 2>/dev/null || true

say "8. OBJECTIVE EVIDENCE SUMMARY"
FOCUS_END=$(focus); echo "FOCUS_END: $FOCUS_END"
echo "--- [gpbrf-tangent] per-vertex tangent load log (device-truth: tangents computed on device) ---"
grep -aE '\[gpbrf-tangent\]' "$BOOTLOG" | head -12 || echo "  (none — tangent log absent!)"
echo "--- [recharged] REOPEN#7 TESS loader-name resolution (EXT/OES) + tess build ---"
grep -aiE 'REOPEN#7 TESS|glPatchParameteri|tessellation (ENABLED|disabled|unavailable)|TESS BUILD|falling back' "$BOOTLOG" "$TESSLOG" | head -20 || echo "  (none)"
echo "--- shader compile / GLES link errors (must be none) ---"
grep -aiE 'shader.*(error|fail)|GL_INVALID|failed to (compile|link)|InfoLog' "$BOOTLOG" "$TESSLOG" | head -12 || echo "  (none)"
echo "--- crash signals (our PID; signal 9 is not a crash) ---"
grep -aE 'Fatal signal (11|6|4)|SIGSEGV|SIGABRT|SIGILL' "$BOOTLOG" | grep -v 'signal 9' | tail -8 || echo "  (none)"
echo "--- render heartbeat + PBR material load ---"
grep -aiE 'A35-RENDER|custom pbr material|Grecharged-pbr|crash-loop guard' "$BOOTLOG" | tail -10 || echo "  (none)"
kill $BLP 2>/dev/null || true
case "$FOCUS_END" in *org.opengoal.gk.jak1*) echo "  FOREGROUND OK (jak1)";; *) echo "  WARN not foreground";; esac
ls -la "$DEV"/r7_*.png "$DEV"/r7_*.mp4 2>/dev/null
echo "[gpbrf7 capture DONE]"
