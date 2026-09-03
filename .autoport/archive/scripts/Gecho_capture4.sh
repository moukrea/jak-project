#!/usr/bin/env bash
# Gecho-pool capture 4: measure the arm64 thread-suspend stack OVERFLOW magnitude.
# The cinematic crash is a genuine (break) in thread-suspend: the display TOP-thread
# (256-byte PROCESS_STACK_SAVE_SIZE child) overflows its suspend backup because arm64
# frames are fatter than x86. A40-DPROC now dumps the top-thread used-vs-size at crash.
#   Usage: bash .autoport/Gecho_capture4.sh <run#>
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
RUN="${1:-103}"
say(){ echo; echo "######## $* ########"; }
die(){ echo "[Gecho-cap4 FAIL] $*" >&2; exit 1; }

say "1. build libgk + assemble APK"
cmake --build build-android --target gk -j"$(nproc)" 2>&1 | tail -6
[ -f build-android/lib/arm64-v8a/libgk.so ] || die "libgk not built"
( cd android && ./gradlew assembleJak1Debug 2>&1 | tail -5 ) || die "gradle failed"
[ -f "$APK" ] || die "APK not produced"

say "2. install + restore + deploy_verify"
$ADB -s $S shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow 2>/dev/null || true
$ADB -s $S shell pm trim-caches 999G 2>/dev/null || true
$ADB -s $S install -r -d -t -i com.android.vending "$APK" 2>&1 | tail -2 || die "install failed"
bash .autoport/restore_knowngood_device.sh 2>&1 | tail -2 || die "restore failed"
bash .autoport/lib/deploy_verify.sh "$S" 2>&1 | tail -3 || die "deploy_verify failed"

say "3. props: clear warp/census, arm a40.dproc (at-crash topthr dump); probes off"
$ADB -s $S shell setprop debug.opengoal.f1.warp 0
$ADB -s $S shell setprop debug.opengoal.f1.census 0
$ADB -s $S shell setprop debug.opengoal.gecho.gen 0
$ADB -s $S shell setprop debug.opengoal.gecho.merc 0
$ADB -s $S shell setprop debug.opengoal.echo.oob 0
$ADB -s $S shell setprop debug.opengoal.a40.dproc 1
echo "  a40.dproc=$($ADB -s $S shell getprop debug.opengoal.a40.dproc|tr -d '\r') f1.warp=$($ADB -s $S shell getprop debug.opengoal.f1.warp|tr -d '\r')"

say "4. drive NEW-GAME -> intro cinematic"
FLOW=newgame bash .autoport/f1d_run.sh "$RUN" skip || echo "  (f1d returned $?)"

L=".autoport/reports/F1d-routed-logcat-run${RUN}.log"
say "5. HARVEST (log $L, $(wc -l <"$L" 2>/dev/null||echo 0) lines)"
echo "--- level sequence ---"; grep -aoE 'Displaying level [a-z0-9]+ ?\[[a-z-]+\]' "$L" | uniq -c
echo "--- crash ---"; grep -aE 'GK-DIAG sig=' "$L" | head -2
echo "--- A40-DPROC TOPTHR (THE MAGNITUDE: used vs stack-size, OVER) ---"
grep -aE 'A40-DPROC.*TOPTHR' "$L" | tail -6
echo "--- A40-DPROC at-crash proc/mthr (context) ---"
grep -aE 'A40-DPROC at-crash (proc|mthr)' "$L" | tail -4
say "Gecho-capture4 DONE (run $RUN)"
