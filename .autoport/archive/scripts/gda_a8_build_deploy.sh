#!/usr/bin/env bash
# gda_a8_build_deploy.sh — Grecharged-directional-ambient ATTEMPT 8 (owner playtest #4) LIGHT build+deploy.
# CHANGED: background_common.cpp (widened sun/green elevation ramps -> gradual yellow<->green handoff,
# max-elevation shadow-map ownership, new u_rt_shadow_conf that fades the cast shadow at the handoff) +
# the 4 world shaders (tfrag3/etie_base/shrub/tie_wind .frag) consume u_rt_shadow_conf.
# goal_src is UNCHANGED => the 28 arm64 CGO/DGO + text banks already on the device stay consistent;
# rebuild ONLY libgk (embeds the shader blob + the C++ push) + reassemble/reinstall the APK.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
OUT=.autoport/reports/Grecharged-directional-ambient/device; mkdir -p "$OUT"
say(){ echo; echo "######## $* ########"; }
die(){ echo "[gda-a8 FAIL] $*" >&2; exit 1; }

say "0. adb server refresh (wedged daemon => false 'not installed')"
"$ADB" kill-server >/dev/null 2>&1 || true; sleep 1; "$ADB" start-server >/dev/null 2>&1 || true; sleep 2
$ADB -s $S wait-for-device

say "1. build android libgk (regenerates the shader blob + the new C++ crossfade push)"
cmake --build build-android --target gk -j"$(nproc)" 2>&1 | tail -16
[ -f build-android/lib/arm64-v8a/libgk.so ] || die "libgk.so not built"
# the new stepless-handoff uniform must be inside the compiled shader blob AND the additive composite kept
CONF=$(strings -a build-android/lib/arm64-v8a/libgk.so | grep -ciE 'u_rt_shadow_conf')
ADD=$(strings -a build-android/lib/arm64-v8a/libgk.so | grep -ciE 'albedo \* base \+ albedo \* u_rt_sun_color')
echo "  libgk u_rt_shadow_conf strings=${CONF:-0}  additive-composite strings=${ADD:-0}"
[ "${CONF:-0}" -gt 0 ] || die "libgk.so missing u_rt_shadow_conf (shader blob not rebuilt from edited .frag)"
[ "${ADD:-0}" -gt 0 ] || die "libgk.so missing the additive composite (regression)"

say "2. assemble APK (bundles the fresh libgk)"
( cd android && ./gradlew assembleJak1Debug 2>&1 | tail -8 ) || die "gradle assemble failed"
[ -f "$APK" ] || die "APK not produced"

say "3. install APK + deploy_verify (build==APK==device libgk)"
$ADB -s $S shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
if $ADB -s $S shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1'; then die "DEVICE_LOCKED — needs owner unlock"; fi
$ADB -s $S shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow 2>/dev/null || true
$ADB -s $S shell settings put global verifier_verify_adb_installs 0 >/dev/null 2>&1 || true
$ADB -s $S shell pm trim-caches 999G 2>/dev/null || true
$ADB -s $S install -r -d -t -i com.android.vending "$APK" 2>&1 | tail -3 || die "apk install failed"
bash .autoport/lib/deploy_verify.sh "$S" jak1 2>&1 | tail -6 || die "deploy_verify (libgk) failed"

say "4. relaunch: reach live render, SHADERS COMPILE (GLES), no crash, jak1 foreground"
$ADB -s $S shell am force-stop $PKG >/dev/null 2>&1 || true
$ADB -s $S logcat -c >/dev/null 2>&1 || true
LOG="$OUT/gda-a8-boot-logcat.log"; : > "$LOG"
( $ADB -s $S logcat -v threadtime GK_STDOUT:I GK_STDERR:I opengoal-gk:I '*:S' \
   | grep --line-buffered -aE 'A35-RENDER|link finish|Fatal signal|signal [0-9]+ \(SIG|GK-DIAG sig=|shaders (FAILED|compiled)' >> "$LOG" ) 2>/dev/null &
LCP=$!
trap 'kill ${LCP:-0} 2>/dev/null || true' EXIT
$ADB -s $S shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
t0=$(date +%s); ok=0
while [ $(( $(date +%s) - t0 )) -lt 240 ]; do
  if grep -aqE 'GK-DIAG sig=11|Fatal signal (11|6|4)|signal (11|6|4) \(SIG' "$LOG" 2>/dev/null; then echo "  CRASH during boot"; break; fi
  rf=$(grep -acE 'A35-RENDER frame=' "$LOG" 2>/dev/null); rf=${rf:-0}
  [ "$rf" -ge 5 ] 2>/dev/null && { ok=1; break; }
  sleep 3
done
echo "  --- shader compile lines ---"; grep -aE 'shaders (FAILED|compiled)' "$LOG" | tail -3
if grep -aqE 'shaders FAILED to compile' "$LOG"; then die "a shader FAILED to compile under GLES (u_rt_shadow_conf syntax issue)"; fi
FOCUS=$($ADB -s $S shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r')
echo "  reached_render=$ok focus=$FOCUS"
case "$FOCUS" in *org.opengoal.gk.jak1*) : ;; *) die "app not foreground: $FOCUS" ;; esac
[ "$ok" = 1 ] || die "did not reach render (crash or hang)"
$ADB -s $S shell am force-stop $PKG >/dev/null 2>&1 || true
echo "[gda-a8] DONE — stepless-handoff libgk on device, shaders compiled, boots to render, deploy_verify PASS."
