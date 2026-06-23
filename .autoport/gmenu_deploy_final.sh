#!/usr/bin/env bash
# Deploy the FINAL fix-only (instrumentation-stripped) libgk and confirm a crash-free boot.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh 2>/dev/null || true
ADB="/home/emeric/Android/platform-tools/adb"; S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
APK="android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk"
OUT=.autoport/reports/Gmenu-textures; LOG="$OUT/final-boot.log"
say(){ echo "[$(date +%H:%M:%S)] $*"; }
say "build libgk (fix-only, should be quick/no-op)"; bash .autoport/lib/d3_build.sh > "$OUT/final-libgk.log" 2>&1; tail -2 "$OUT/final-libgk.log"
say "assemble slim APK"; ( cd android && ./gradlew assembleJak1Debug -PslimIso=true ) > "$OUT/final-gradle.log" 2>&1; tail -2 "$OUT/final-gradle.log"
say "install"; "$ADB" -s $S shell cmd appops set com.android.shell REQUEST_INSTALL_PACKAGES allow >/dev/null 2>&1 || true
STAGE="/data/local/tmp/$(basename "$APK")"; "$ADB" -s $S push "$APK" "$STAGE" >/dev/null 2>&1
"$ADB" -s $S shell pm install -r -d -t -i com.android.vending "$STAGE" > "$OUT/final-pm.log" 2>&1
grep -q Success "$OUT/final-pm.log" && say "installed OK" || { say "install FAIL"; cat "$OUT/final-pm.log"; exit 1; }
"$ADB" -s $S shell rm -f "$STAGE" >/dev/null 2>&1 || true
say "deploy_verify"; bash .autoport/lib/deploy_verify.sh $S > "$OUT/final-deploy.log" 2>&1; tail -1 "$OUT/final-deploy.log"
say "boot crash-free check (90s)"
"$ADB" -s $S shell am force-stop $PKG >/dev/null 2>&1 || true
"$ADB" -s $S logcat -c >/dev/null 2>&1 || true
: > "$LOG"
( "$ADB" -s $S logcat -v threadtime GK_STDOUT:I opengoal-gk:I libc:F DEBUG:V '*:S' | grep --line-buffered -aE 'A35-RENDER frame=|link finish: logo|Fatal signal|signal [0-9]+ \(SIG|GK-DIAG sig=' >> "$LOG" ) &
LCPID=$!
"$ADB" -s $S shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
for i in $(seq 1 30); do sleep 3; FM=$(grep -aoE 'A35-RENDER frame=[0-9]+' "$LOG" 2>/dev/null | grep -oE '[0-9]+$' | sort -n | tail -1); FM=${FM:-0}
  CS=$(grep -acE 'Fatal signal|signal (11|6|4) \(SIG|GK-DIAG sig=(4|6|11)' "$LOG" 2>/dev/null)
  [ "${CS:-0}" -gt 0 ] && { say "  CRASH sigs=$CS"; break; }; [ "$FM" -ge 2000 ] && { say "  reached frame=$FM crash-free"; break; }; done
# open menu briefly to confirm HUD renders crash-free
printf 'start' | "$ADB" -s $S shell "run-as $PKG sh -c 'cat > /data/data/$PKG/files/cpad_inject'" >/dev/null 2>&1 || true
sleep 4; printf '' | "$ADB" -s $S shell "run-as $PKG sh -c 'cat > /data/data/$PKG/files/cpad_inject'" >/dev/null 2>&1 || true
sleep 6
FINAL=$(grep -aoE 'A35-RENDER frame=[0-9]+' "$LOG" 2>/dev/null | grep -oE '[0-9]+$' | sort -n | tail -1); FCS=$(grep -acE 'Fatal signal|signal (11|6|4) \(SIG|GK-DIAG sig=(4|6|11)' "$LOG" 2>/dev/null)
kill ${LCPID:-0} 2>/dev/null || true; pkill -f "logcat -v threadtime GK_STDOUT" 2>/dev/null || true
"$ADB" -s $S shell am force-stop $PKG >/dev/null 2>&1 || true
say "RESULT: reached_frame=${FINAL:-0} crash_sigs=${FCS:-0} (menu opened)"
