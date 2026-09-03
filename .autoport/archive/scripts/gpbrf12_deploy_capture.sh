#!/usr/bin/env bash
# gpbrf12_deploy_capture.sh — attempt 12 (OWNER PLAYTEST #8): faceted-shading fix + [pbr-tess]
# diagnostics. libgk-only change (Shader.cpp / background_common.cpp / tfrag3.frag / TFrag3Data.cpp
# facet counter). NO goal_src / CGO / asset change => reassemble APK with fresh libgk, install
# (keeps app data => CGOs persist, loader skips re-extract), deploy_verify, boot, capture the
# [pbr-tess] init diagnostics + the [gda-facet]/[gda-crease] device-truth normal stats + a default
# render. ALL logcat is `timeout`-wrapped (supervisor mandate: un-timeouted logcat zombied 5x).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
OUT=.autoport/reports/Grecharged-pbr-realtime-fusion/device
mkdir -p "$OUT"
say(){ echo; echo "######## $* ########"; }
die(){ echo "[gpbrf12 FAIL] $*" >&2; exit 1; }
A(){ $ADB -s $S "$@"; }

say "0. adb server refresh (wedged daemon => false 'not installed')"
"$ADB" kill-server >/dev/null 2>&1 || true; sleep 1; "$ADB" start-server >/dev/null 2>&1 || true; sleep 2
A wait-for-device
echo "  /data free:"; A shell df -h /data | tail -1
[ -f build-android/lib/arm64-v8a/libgk.so ] || die "libgk.so missing (build first)"
echo "  libgk [pbr-tess] strings: $(strings -a build-android/lib/arm64-v8a/libgk.so | grep -c 'pbr-tess')"

say "1. reassemble APK with fresh libgk (no CGO/asset change)"
( cd android && ./gradlew assembleJak1Debug 2>&1 | tail -6 ) || die "gradle assemble failed"
[ -f "$APK" ] || die "APK not produced"

say "2. install APK (keep app data => CGOs persist, no re-extract)"
A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
A shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1' && die "DEVICE_LOCKED — needs owner unlock"
A shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow 2>/dev/null || true
A shell pm trim-caches 999G 2>/dev/null || true
A install -r -d -t -i com.android.vending "$APK" 2>&1 | tail -3 || die "apk install failed"

say "3. deploy_verify (build==APK==device libgk, built-after-source)"
bash .autoport/lib/deploy_verify.sh "$S" 2>&1 | tail -5 || die "deploy_verify FAILED"

say "4. ensure fused path ON: recharged master + PBR + realtime lighting + custom assets"
# force-props (never touch saved settings): recharged ON, PBR mode on, realtime lighting on.
A shell setprop debug.opengoal.recharged 1 >/dev/null 2>&1 || true
A shell setprop debug.opengoal.pbr.kill 0 >/dev/null 2>&1 || true
# displacement=Tessellation (2) so the [pbr-tess] fallback path is exercised if tess is unavailable.
A shell setprop debug.opengoal.pbr.displacement 2 >/dev/null 2>&1 || true

say "5. cold boot + capture init logcat (timeout-wrapped)"
A logcat -c >/dev/null 2>&1 || true
A shell am force-stop $PKG >/dev/null 2>&1 || true
sleep 1
A shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
# capture 90s of logcat, hard-timeout 120s (covers boot to render). NEVER un-timeouted.
timeout 120 $ADB -s $S logcat -v time GK_STDOUT:I opengoal-gk:I '*:S' > "$OUT/gpbrf12_boot_logcat.log" 2>&1 &
LOGPID=$!
sleep 90
# also grab the full unfiltered tail in case tags differ
timeout 30 $ADB -s $S logcat -d -v time > "$OUT/gpbrf12_full_logcat.log" 2>&1 || true
kill $LOGPID 2>/dev/null || true

say "6. extract the [pbr-tess] + [gda-facet]/[gda-crease] diagnostics"
{
  echo "===== [pbr-tess] tessellation diagnostics (init) ====="
  grep -aE '\[pbr-tess\]' "$OUT/gpbrf12_boot_logcat.log" "$OUT/gpbrf12_full_logcat.log" | sort -u
  echo
  echo "===== [gda-facet] base-normal smoothness (device-truth, per tfrag tree) ====="
  grep -aE '\[gda-facet\]' "$OUT/gpbrf12_boot_logcat.log" "$OUT/gpbrf12_full_logcat.log" | sort -u | head -12
  echo
  echo "===== [gda-crease] crease clustering ====="
  grep -aE '\[gda-crease\]' "$OUT/gpbrf12_boot_logcat.log" "$OUT/gpbrf12_full_logcat.log" | sort -u | head -12
  echo
  echo "===== shader compile errors (must be EMPTY) ====="
  grep -aiE 'Failed to compile|Failed to link|A35-RENDER shader' "$OUT/gpbrf12_full_logcat.log" | head
  echo "(end)"
} > "$OUT/gpbrf12_diagnostics.txt" 2>&1
cat "$OUT/gpbrf12_diagnostics.txt"

say "7. default render capture (screenrecord+ffmpeg — screencap is black on the GL surface)"
A shell 'rm -f /sdcard/gpbrf12.mp4' >/dev/null 2>&1 || true
timeout 20 $ADB -s $S shell screenrecord --time-limit 8 --bit-rate 12000000 /sdcard/gpbrf12.mp4 || true
sleep 1
A pull /sdcard/gpbrf12.mp4 "$OUT/gpbrf12_default.mp4" 2>&1 | tail -1 || true
if [ -f "$OUT/gpbrf12_default.mp4" ]; then
  ffmpeg -y -sseof -2 -i "$OUT/gpbrf12_default.mp4" -frames:v 1 "$OUT/gpbrf12_default.png" >/dev/null 2>&1 || \
  ffmpeg -y -i "$OUT/gpbrf12_default.mp4" -frames:v 1 "$OUT/gpbrf12_default.png" >/dev/null 2>&1 || true
fi

say "8. foreground focus check (shared device: must be jak1)"
A shell dumpsys window 2>/dev/null | grep -aE 'mCurrentFocus|mFocusedApp' | grep -ai "$PKG" | head -2 | tee "$OUT/gpbrf12_focus.txt"

say "9. app alive (no crash) + pid"
A shell pidof $PKG | tee "$OUT/gpbrf12_pid.txt"

echo; echo "[gpbrf12] capture DONE. Evidence in $OUT/"
ls -la "$OUT"/gpbrf12_* 2>/dev/null
