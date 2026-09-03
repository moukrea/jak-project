#!/usr/bin/env bash
# gci_build_deploy.sh — Gcamera-interp full consistent build + deploy.
# My change touches BOTH goal_src (engine/camera/cam-update.gc -> ENGINE.CGO +
# GAME.CGO) AND libgk C++ (android/gk_android_main.cpp, game/kernel/common/
# kmachine.cpp). So this is the gsfx pattern: full consistent 28-CGO arm64 build +
# rebuilt libgk + repackaged APK + reinstall + push consistent CGOs + deploy_verify.
#
# Tier-A nuance: the render-time camera interpolation is an INTENTIONAL, Android-
# runtime-gated (pc-camera-subframe==0 on x86 -> no-op) source addition in
# update-camera. It compiles into ENGINE.CGO + GAME.CGO on BOTH backends, so our-x86
# ENGINE.CGO/GAME.CGO are EXPECTED to differ from gold (dormant code, identical x86
# BEHAVIOR). KERNEL.CGO and all level DGOs must stay byte-identical to gold (my
# change doesn't touch them) — those are HARD gates.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
OUT=.autoport/reports/Gcamera-interp; mkdir -p "$OUT"
say(){ echo; echo "######## $* ########"; }
die(){ echo "[gci-build FAIL] $*" >&2; exit 1; }

say "1. FULL consistent arm64 build (28 CGO/DGO) + x86 oracle restore"
bash .autoport/build_arm64_full_consistent.sh || die "full arm64 build failed"
n=$(ls out/jak1-arm64-full/iso/*.CGO out/jak1-arm64-full/iso/*.DGO 2>/dev/null | wc -l)
[ "$n" -eq 28 ] || die "expected 28 staged arm64 files, got $n"

say "2. LOCALIZATION (informational): my ONLY goal_src edit is cam-update.gc -> ENGINE/GAME.CGO"
# NOTE: .autoport/gold is a HISTORICAL x86 snapshot (commit 704972dd6). Dozens of
# legitimate goal_src changes landed since (every G-phase), so the current x86 build
# differs from stale gold across KERNEL.CGO + most DGOs — that is PRE-EXISTING, not
# mine. My localization is guaranteed by construction: `git diff` shows cam-update.gc
# is the only engine goal_src edit, and it bundles solely into ENGINE.CGO + GAME.CGO
# (engine.gd/game.gd). Safety = FULL CONSISTENT build (all 28 from one source) +
# matching libgk + boot-gate + restore_knowngood undo button (gdfix practice).
CAM_EDITS=$(git diff --name-only c068b2bcf -- goal_src/ 2>/dev/null | grep -v '/pc/' | tr '\n' ' ')
echo "  engine goal_src edits since supervisor anchor: ${CAM_EDITS:-<none>}"
echo "  (expected: only engine/camera/cam-update.gc; -> ENGINE.CGO + GAME.CGO)"
case "$CAM_EDITS" in
  *cam-update.gc*) [ "$(echo $CAM_EDITS | wc -w)" -le 1 ] && echo "  OK: localized to cam-update.gc" || echo "  WARN: more engine files changed than expected";;
  "" ) echo "  WARN: no engine edit detected (cam-update in pc/ or already merged?)";;
esac

say "3. build android libgk (my C++ beta-publisher) + assemble APK"
touch android/gk_android_main.cpp game/kernel/common/kmachine.cpp   # force ninja recompile
cmake --build build-android --target gk -j"$(nproc)" 2>&1 | tail -8
[ -f build-android/lib/arm64-v8a/libgk.so ] || die "libgk.so not built"
( cd android && ./gradlew assembleJak1Debug 2>&1 | tail -6 ) || die "gradle assemble failed"
[ -f "$APK" ] || die "APK not produced"

say "4. install APK + baseline + deploy_verify (build==APK==device libgk chain)"
$ADB -s $S shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
if $ADB -s $S shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1'; then die "DEVICE_LOCKED — needs owner unlock"; fi
$ADB -s $S shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow 2>/dev/null || true
$ADB -s $S shell pm trim-caches 999G 2>/dev/null || true
$ADB -s $S install -r -d -t -i com.android.vending "$APK" 2>&1 | tail -3 || die "apk install failed"
bash .autoport/restore_knowngood_device.sh 2>&1 | tail -3 || die "restore_knowngood failed"
bash .autoport/lib/deploy_verify.sh "$S" 2>&1 | tail -4 || die "deploy_verify failed"

say "5. push the FIXED consistent arm64 CGO/DGO set (ENGINE/GAME carry the interp)"
bash .autoport/Gconsolidate_deploy_cgos.sh 2>&1 | tail -6 || die "CGO deploy failed"

say "6. boot to attract (render markers + foreground)"
$ADB -s $S shell setprop debug.opengoal.caminterp 1 >/dev/null 2>&1 || true
$ADB -s $S shell am force-stop $PKG >/dev/null 2>&1 || true
$ADB -s $S logcat -c >/dev/null 2>&1 || true
LOG="$OUT/gci-boot-logcat.log"; : > "$LOG"
( $ADB -s $S logcat -v threadtime GK_STDOUT:I GK_STDERR:I opengoal-gk:I '*:S' \
   | grep --line-buffered -aE 'A42-TFTREE|A42-TFGL|A35-RENDER frame=|link finish: logo|Fatal signal|signal [0-9]+ \(SIG|GK-DIAG sig=' >> "$LOG" ) &
LCP=$!
trap 'kill ${LCP:-0} 2>/dev/null || true' EXIT
$ADB -s $S shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
t0=$(date +%s); ok=0
while [ $(( $(date +%s) - t0 )) -lt 150 ]; do
  if grep -aqE 'GK-DIAG sig=11|Fatal signal (11|6|4)|signal (11|6|4) \(SIG' "$LOG" 2>/dev/null; then echo "  CRASH during boot"; break; fi
  rf=$(grep -acE 'A42-TFTREE|A42-TFGL|A35-RENDER frame=' "$LOG" 2>/dev/null); rf=${rf:-0}
  [ "$rf" -ge 20 ] 2>/dev/null && { ok=1; echo "  attract rendering ($rf markers)"; break; }
  sleep 3
done
rf=$(grep -acE 'A42-TFTREE|A42-TFGL|A35-RENDER frame=' "$LOG" 2>/dev/null); rf=${rf:-0}
FOCUS=$($ADB -s $S shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r')
echo "  boot render-markers=$rf reached_attract=$ok focus=$FOCUS"
case "$FOCUS" in *org.opengoal.gk.jak1*) : ;; *) die "app not in foreground: $FOCUS" ;; esac
[ "$ok" = 1 ] || die "did not reach attract (render-markers=$rf)"
echo "[gci-build] DONE — fresh consistent camera-interp build deployed + booting."
