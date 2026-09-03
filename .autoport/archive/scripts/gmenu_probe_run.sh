#!/usr/bin/env bash
# gmenu_probe_run.sh — DECISIVE measurement for Gmenu-textures.
# Build libgk (improved GMENU-PROBE) -> slim APK -> install -> boot -> open progress
# menu -> harvest GMENU-PROBE. Answers: is the menu-particle user-hvdf matrix SOURCE
# (launch-control.matrix, s1+28) 0 or positive (1..34) on the arm64 device, and does
# the is-3d #f-guard diverge (is2d32 != is2d64)?
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh 2>/dev/null || true
ADB="/home/emeric/Android/platform-tools/adb"
S=eae4df44
PKG=org.opengoal.gk.jak1
ACT=.LoaderActivity
INJECT="/data/data/$PKG/files/cpad_inject"
APK="android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk"
OUT=.autoport/reports/Gmenu-textures
LOG="$OUT/probe-capture.log"
SUM="$OUT/probe-summary.txt"
RUNLOG="$OUT/probe-run.log"
mkdir -p "$OUT"
exec > >(tee "$RUNLOG") 2>&1
A(){ "$ADB" -s $S "$@"; }
say(){ echo "[$(date +%H:%M:%S)] $*"; }
inject(){ printf '%s' "$1" | A shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; }
clr(){ inject ""; }
maxframe(){ grep -aoE 'A35-RENDER frame=[0-9]+' "$LOG" 2>/dev/null | grep -oE '[0-9]+$' | sort -n | tail -1; }
sigs(){ local n; n=$(grep -acE 'Fatal signal|signal (11|6|4) \(SIG|GK-DIAG sig=(4|6|11)' "$LOG" 2>/dev/null); echo "${n:-0}"; }

say "=== 1. build libgk (cmake --build build-android --target gk) ==="
bash .autoport/lib/d3_build.sh > "$OUT/build-libgk.log" 2>&1
BRC=$?
tail -n 8 "$OUT/build-libgk.log"
[ $BRC -eq 0 ] || { say "BUILD FAILED rc=$BRC (see $OUT/build-libgk.log)"; exit 10; }
say "libgk.so: $(stat -c '%y' build-android/lib/arm64-v8a/libgk.so)"

say "=== 2. assemble slim APK (gradlew assembleJak1Debug -PslimIso=true) ==="
( cd android && ./gradlew assembleJak1Debug -PslimIso=true ) > "$OUT/gradle.log" 2>&1
GRC=$?
tail -n 8 "$OUT/gradle.log"
[ $GRC -eq 0 ] || { say "GRADLE FAILED rc=$GRC (see $OUT/gradle.log)"; exit 11; }
[ -f "$APK" ] || { say "APK missing at $APK"; exit 12; }
say "APK: $(stat -c '%y %s' "$APK")"

say "=== 3. install (pm install) ==="
A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
A shell svc power stayon true >/dev/null 2>&1 || true
A shell cmd appops set com.android.shell REQUEST_INSTALL_PACKAGES allow >/dev/null 2>&1 || true
A shell settings put global adb_install_need_confirm 0 >/dev/null 2>&1 || true
STAGE="/data/local/tmp/$(basename "$APK")"
A push "$APK" "$STAGE" >/dev/null 2>&1 || { say "push failed"; exit 13; }
A shell pm install -r -d -t -i com.android.vending "$STAGE" > "$OUT/pm-install.log" 2>&1
grep -q Success "$OUT/pm-install.log" || { say "pm install no Success:"; cat "$OUT/pm-install.log"; exit 14; }
A shell rm -f "$STAGE" >/dev/null 2>&1 || true
say "installed."
say "=== deploy_verify ==="
bash .autoport/lib/deploy_verify.sh $S > "$OUT/deploy-verify.log" 2>&1
DRC=$?; tail -n 3 "$OUT/deploy-verify.log"
[ $DRC -eq 0 ] || say "WARN deploy_verify rc=$DRC"

say "=== 4. boot + open progress menu + harvest GMENU-PROBE ==="
A shell am force-stop $PKG >/dev/null 2>&1 || true
clr
A logcat -G 64M >/dev/null 2>&1 || true
A logcat -c >/dev/null 2>&1 || true
: > "$LOG"
GREP='GK-FPCR|GMENU-PROBE|GK-COMMIT|GK-SPB-|GK-MWRITE|GK-G1 |GMENU-ALLOC|GK-SPR3 mode=|A35-RENDER frame=|link finish: logo|GK-DIAG sig=|Fatal signal|signal [0-9]+ \(SIG|backtrace:'
( A logcat -v threadtime GK_STDOUT:I GK_STDERR:I opengoal-gk:I libc:F DEBUG:V '*:S' \
    | grep --line-buffered -aE "$GREP" >> "$LOG" ) &
LCPID=$!
A shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true

say "boot: waiting for title (link finish: logo / frame>=1500, up to 180s)"
for ((i=1;i<=60;i++)); do
  sleep 3
  FM=$(maxframe); FM=${FM:-0}; CS=$(sigs)
  (( i % 5 == 0 )) && say "  [boot ${i}] frame=$FM sigs=$CS"
  [ "$CS" -gt 0 ] && { say "  crash during boot sigs=$CS"; break; }
  [ "$FM" -ge 1500 ] && { say "  title reached frame=$FM"; break; }
done

say "settle 40s before opening menu (unsettled title eats the first inject)"
sleep 40
A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true

say "open menu: inject START, hold + navigate ~45s so menu particles spawn each frame"
inject "start"; sleep 2; clr; sleep 1
for ((s=0;s<45;s+=5)); do
  sleep 5
  CS=$(sigs); [ "$CS" -gt 0 ] && { say "  crash during menu sigs=$CS"; break; }
  A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
  NP=$(grep -ac 'GMENU-PROBE' "$LOG" 2>/dev/null); NP=${NP:-0}
  NZ=$(grep -aoE 'nz=[0-9]+' "$LOG" 2>/dev/null | grep -oE '[0-9]+$' | sort -n | tail -1); NZ=${NZ:-0}
  say "  [+${s}s] probe_lines=$NP nz=$NZ frame=$(maxframe)"
  inject "down"; sleep 0.4; inject "up"; sleep 0.4; clr
  # if no menu particle activity yet, re-press START
  [ "$s" -ge 15 ] && [ "$NP" -eq 0 ] && { say "  (no probe lines — re-press START)"; inject "start"; sleep 1.2; clr; }
done

say "=== 5. harvest + summarize ==="
kill ${LCPID:-0} 2>/dev/null || true
pkill -f "logcat -v threadtime GK_STDOUT" 2>/dev/null || true
FINAL=$(maxframe); FINAL=${FINAL:-0}; FCS=$(sigs)
A shell am force-stop $PKG >/dev/null 2>&1 || true
{
echo "# Gmenu-textures GMENU-PROBE summary $(date -Is)"
echo "device=$S reached_frame=$FINAL crash_sigs=$FCS"
echo "libgk_built=$(stat -c '%y' build-android/lib/arm64-v8a/libgk.so)"
echo
echo "## GK-FPCR arm64 FPU control (fz=1 => denormal flush-to-zero ON = the bug; after clear, menu matrix should survive)"
grep -aoE 'GK-FPCR .*' "$LOG" 2>/dev/null | sort -u | head -3
echo
echo "## GK-COMMIT sp-launch: staging matrix (sp148) vs committed (v1_20) at the SAME point, gated sp148!=0"
echo "   (sp148=1..34 & v1_20=1..34 => commit OK; sp148=1..34 & v1_20=0 => store-to-v1 broken; no lines => never reaches commit)"
grep -aoE 'GK-COMMIT sp148=-?[0-9]+ v1=[0-9a-f]+ v1_20=-?[0-9]+' "$LOG" 2>/dev/null | sort -u | head -30
echo "   -- distinct (sp148,v1_20) pairs --"
grep -aoE 'sp148=-?[0-9]+ v1=[0-9a-f]+ v1_20=-?[0-9]+' "$LOG" 2>/dev/null | sed -E 's/ v1=[0-9a-f]+//' | sort -u | head -40
echo
echo "## GK-SPB-IN/OUT sp-process-block-2d: sprite matrix ENTERING vs LEAVING the per-frame processing"
echo "   (IN has 1..34 but OUT has none => the per-particle processing/GOAL callback zeroed it; both 1..34 => loss is copy-from-spr/DMA; neither => copy-to-spr/spawn lost it)"
echo "   -- GK-SPB-IN scratchpad addr range --"
grep -aoE 'GK-SPB-IN a=[0-9a-f]+' "$LOG" 2>/dev/null | sort -u | head -3
echo "   -- GK-SPB-IN matrix histogram --"
grep -aE 'GK-SPB-IN ' "$LOG" 2>/dev/null | grep -aoE 'mtx=-?[0-9]+' | sort -t= -k2 -n | uniq -c | head -40
echo "   -- GK-SPB-OUT matrix histogram --"
grep -aE 'GK-SPB-OUT ' "$LOG" 2>/dev/null | grep -aoE 'mtx=-?[0-9]+' | sort -t= -k2 -n | uniq -c | head -40
echo
echo "## GK-MWRITE sp-launch matrix SOURCE (launch-control.matrix s1+28) vs WRITTEN (sprite sp+148)"
echo "   (src=1..34 written=1..34 => copy delivers index, loss downstream; written=0/1 => fallback/guard zeroed)"
grep -aoE 'GK-MWRITE s1=[0-9a-f]+ src=-?[0-9]+ written=-?[0-9]+' "$LOG" 2>/dev/null | sed -E 's/ s1=[0-9a-f]+//' | sort | uniq -c | sort -rn | head -25
echo "   -- distinct (src,written) pairs --"
grep -aoE 'src=-?[0-9]+ written=-?[0-9]+' "$LOG" 2>/dev/null | sort -u | head -40
echo
echo "## GK-G1 render_2d_group1 (HUD/ModeHUD): chunks/sprites this frame + nonzero-matrix count + first 8 matrices"
echo "   (sprites=0 => HUD group empty/routing bug; sprites>0 nz=0 => matrix index lost; nz>0 first=[1..34] => FIXED)"
grep -aoE 'GK-G1 .*' "$LOG" 2>/dev/null | sort | uniq -c | sort -rn | head -25
echo "   -- GK-G1 lines with sprites>0 (HUD active) --"
grep -aoE 'GK-G1 chunks=[0-9]+ sprites=[1-9][0-9]* .*' "$LOG" 2>/dev/null | sort -u | head -20
echo
echo "## counters (last GMENU-PROBE line: all2d total 2D-system spawns, nz = those with matrix!=0)"
grep -aoE 'all2d=[0-9]+ nz=[0-9]+' "$LOG" 2>/dev/null | tail -3
echo
echo "## distinct nonzero-matrix (lcm!=0) GMENU-PROBE lines (THE MENU PARTICLES if source correct)"
grep -aE 'GMENU-PROBE' "$LOG" 2>/dev/null | grep -avE 'lcm=0 ' | sort -u | head -60
echo
echo "## distinct lcm values seen (sorted)"
grep -aoE 'lcm=-?[0-9]+' "$LOG" 2>/dev/null | sort -u
echo
echo "## is-3d guard divergence sample (is2d32=1 is2d64=0 means the 64-bit compare WOULD have wrongly skipped)"
grep -aoE 'is2d32=[01] is2d64=[01]' "$LOG" 2>/dev/null | sort | uniq -c
echo
echo "## zero-matrix sampled lines (background 2D activity, 1/200)"
grep -aE 'GMENU-PROBE' "$LOG" 2>/dev/null | grep -aE 'lcm=0 ' | sort -u | head -10
echo
echo "## GMENU-ALLOC (sprite-allocate-user-hvdf returns) if present"
grep -aoE 'GMENU-ALLOC.*' "$LOG" 2>/dev/null | sort -u | head -40
echo
echo "## GK-SPR3 HUD sprites (mode=2 = ModeHUD): on-screen px/py, consumed mtx index, user-hvdf uhx/uhy"
grep -aoE 'GK-SPR3 mode=2 .*' "$LOG" 2>/dev/null | sort -u | head -60
echo
echo "## GK-SPR3 mtx histogram (consumed matrix index at draw time; mtx=0 => bunched to center)"
grep -aoE 'GK-SPR3 mode=2 .*mtx=-?[0-9]+' "$LOG" 2>/dev/null | grep -aoE 'mtx=-?[0-9]+' | sort | uniq -c | sort -rn | head -20
echo
echo "## crash signatures"
grep -aiE 'GK-DIAG sig=|Fatal signal|signal [0-9]+ \(SIG|backtrace:' "$LOG" 2>/dev/null | tail -8
} | tee "$SUM"
say "DONE. summary=$SUM full-log=$LOG"
