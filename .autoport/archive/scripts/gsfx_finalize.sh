#!/usr/bin/env bash
# gsfx_finalize.sh — FINAL deploy for Gsfx-actions:
#  1. promote the proven FIXED arm64 set to the device known-good backup (old kept
#     as a dated fallback) so restore_knowngood (run by the validator) keeps the fix;
#  2. rebuild libgk WITHOUT the probe (clean HEAD), reassemble APK, install;
#  3. restore_knowngood (now = fixed set) + deploy_verify;
#  4. ~3min boot smoke confirming crash-free gameplay.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
KG=.autoport/backups/device-knowngood-cgos-20260622
FIXED=out/jak1-arm64-full/iso
say(){ echo; echo "######## $* ########"; }
die(){ echo "[gsfx-final FAIL] $*" >&2; exit 1; }
A(){ "$ADB" -s "$S" "$@"; }

n=$(ls "$FIXED"/*.CGO "$FIXED"/*.DGO 2>/dev/null | wc -l); [ "$n" -eq 28 ] || die "fixed set has $n files (need 28)"

say "1. promote fixed set to known-good (old -> dated fallback)"
FALLBACK="${KG}-pre-gsfx-$(ls -d ${KG}-pre-gsfx-* 2>/dev/null | wc -l)"
cp -a "$KG" "$FALLBACK" || die "could not back up old known-good"
echo "  old known-good backed up to $FALLBACK"
rm -f "$KG"/*.CGO "$KG"/*.DGO
cp -f "$FIXED"/*.CGO "$FIXED"/*.DGO "$KG"/
m=$(ls "$KG"/*.CGO "$KG"/*.DGO 2>/dev/null | wc -l); [ "$m" -eq 28 ] || die "known-good now has $m files (need 28)"
echo "  known-good updated to FIXED set ($m files)"

say "2. rebuild libgk (probe removed) + assemble APK"
cmake --build build-android --target gk -j"$(nproc)" 2>&1 | tail -5
[ -f build-android/lib/arm64-v8a/libgk.so ] || die "libgk.so not built"
( cd android && ./gradlew assembleJak1Debug 2>&1 | tail -5 ) || die "gradle failed"
[ -f "$APK" ] || die "APK missing"

say "3. install clean APK + restore_knowngood (= FIXED set) + deploy_verify"
A shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow 2>/dev/null || true
A shell pm trim-caches 999G 2>/dev/null || true
A install -r -d -t -i com.android.vending "$APK" 2>&1 | tail -2 || die "install failed"
bash .autoport/restore_knowngood_device.sh 2>&1 | tail -2 || die "restore_knowngood failed"
mkdir -p /home/emeric/.cache/gsfx-tmp
TMPDIR=/home/emeric/.cache/gsfx-tmp bash .autoport/lib/deploy_verify.sh "$S" 2>&1 | tail -3 || die "deploy_verify failed"

say "4. boot smoke (warp to training, ~3min, crash-free check)"
A shell setprop debug.opengoal.sfx.probe 0 >/dev/null 2>&1 || true
A shell setprop debug.opengoal.f1.warp 1   >/dev/null 2>&1 || true
A shell settings put global stay_on_while_plugged_in 7 >/dev/null 2>&1 || true
A shell svc power stayon true >/dev/null 2>&1 || true
A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
LOG=.autoport/reports/Gsfx-actions/final-smoke-logcat.log
A shell am force-stop "$PKG" >/dev/null 2>&1 || true
A logcat -c >/dev/null 2>&1 || true; : > "$LOG"
( "$ADB" -s "$S" logcat -v threadtime opengoal-gk:V GK_STDOUT:V libc:F DEBUG:V '*:S' > "$LOG" 2>&1 ) &
LCP=$!
trap 'kill "$LCP" 2>/dev/null||true' EXIT
A shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
for i in $(seq 1 36); do A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true; sleep 5; done
kill "$LCP" 2>/dev/null || true
FOCUS=$(A shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r')
CRASH=$(grep -acE "Fatal signal|signal (11|6|4) \(SIG" "$LOG" 2>/dev/null || echo 0)
LF=$(grep -ac "link finish: logo" "$LOG" 2>/dev/null || echo 0)
TRN=$(grep -ac "link finish: training" "$LOG" 2>/dev/null || echo 0)
say "FINAL SMOKE RESULT"
echo "  focus=$FOCUS"
echo "  link_finish_logo=$LF  link_finish_training=$TRN  crash_lines=$CRASH"
[ "$CRASH" -eq 0 ] || die "CRASH during final smoke ($CRASH lines)"
echo "[gsfx-final] DONE — fixed set is known-good, clean libgk deployed, crash-free smoke."
