#!/usr/bin/env bash
# grv_drive.sh — Gcrash-swamp-load REAL-route repro via position-drive.
# Warp to village2-dock, restore the 90-orb pontoons (task 33), spawn Jak just NORTH
# of the (load village2 swamp) boundary, then DRIVE his real world position SOUTH across
# the load->display->vis boundaries (debug.opengoal.target.drive) so SWA.DGO streams in
# from his REAL position (position-triggered, NOT a want-levels replay). Arms
# debug.opengoal.diag.norepair AFTER spawn so the TRUE first swamp-load crash reaches the
# fatal forensic dump instead of being masked. Captures the crash + focus + forensics.
# Usage: grv_drive.sh <tag> [observe_s]
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
TAG="${1:-drive1}"
OBS="${2:-70}"
OUT=.autoport/reports/Gcrash-swamp-load
mkdir -p "$OUT"
PKG=org.opengoal.gk.jak1
ACT=.LoaderActivity
SERIAL="${ANDROID_SERIAL:-eae4df44}"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
LOG="$OUT/$TAG-logcat.log"
RES="$OUT/$TAG-result.txt"
A(){ "$ADB" -s "$SERIAL" "$@"; }
# Spawn just NORTH of the load boundary on the crate column (raw 1778057,9285,-6987442),
# meters. Drive: dx dz pin_y stop_z (raw). dz<0 = south. Stop past the vis boundary.
WARP_POS="${WARP_POS:-434.2 2.27 -1705.9}"
DRIVE="${DRIVE:-0 -4000 9285 -7355000}"

crash_seen(){ grep -qaE 'Fatal signal|signal (11|6|4) \(SIG|GK-DIAG sig=(4|6|11)|BARERET-FORENSIC|F1A-BUCKET' "$LOG"; }
focus_is_app(){ A shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | grep -q "$PKG"; }

A shell svc power stayon true >/dev/null 2>&1 || true
A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
if A shell dumpsys window 2>/dev/null | grep -q 'mDreamingLockscreen=true'; then
  echo "PIN-LOCKED: needs owner unlock" | tee "$RES"; exit 2
fi

echo "== $TAG: warp village2-dock pos=($WARP_POS)m, task 33, drive south ($DRIVE) =="
# Arm warp + pontoons. target.drive and diag.norepair set LATER (after spawn).
A shell setprop debug.opengoal.level.warp village2-dock >/dev/null 2>&1
A shell "setprop debug.opengoal.level.warp.pos '$WARP_POS'" >/dev/null 2>&1
A shell "setprop debug.opengoal.task.close '33'" >/dev/null 2>&1
A shell setprop debug.opengoal.target.drive '""' >/dev/null 2>&1
A shell setprop debug.opengoal.diag.norepair '""' >/dev/null 2>&1
# HEAL: unset/1 = part-group name-heal fix ENABLED (shipping default); 0 = disabled (control).
A shell "setprop debug.opengoal.swamp.heal '${HEAL:-}'" >/dev/null 2>&1
for p in f1.warp mouche.buzz mouche.fx die eco.spawn want.levels want.display want.vis; do
  A shell setprop debug.opengoal.$p '""' >/dev/null 2>&1 || true; done

A shell am force-stop "$PKG" >/dev/null 2>&1
A logcat -G 64M >/dev/null 2>&1 || true
A logcat -c >/dev/null 2>&1 || true
: > "$LOG"
A logcat -v threadtime opengoal-gk:V GK_STDOUT:V GK_STDERR:V opengoal-gk-full:V opengoal-loader:V libc:F DEBUG:V '*:S' > "$LOG" 2>&1 &
LOGPID=$!
cleanup(){ kill "$LOGPID" 2>/dev/null || true
  for p in level.warp level.warp.pos task.close target.drive diag.norepair; do
    A shell setprop debug.opengoal.$p '""' >/dev/null 2>&1 || true; done; }
trap cleanup EXIT
A shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1

echo "  waiting title..."
for i in $(seq 1 160); do grep -qa 'link finish: logo' "$LOG" && break; crash_seen && break; sleep 1; done
echo "  waiting LEVEL-WARP-SPAWN..."
WARP_OK=0
for i in $(seq 1 90); do
  grep -qa "LEVEL-WARP-SPAWN name=village2-dock" "$LOG" && { WARP_OK=1; echo "  warp fired ~${i}s"; break; }
  grep -qa "LEVEL-WARP-FAIL" "$LOG" && { echo "  warp FAILED"; break; }
  crash_seen && { echo "  crash before warp"; break; }
  sleep 1
done
grep -a 'LEVEL-WARP-POS' "$LOG" | tail -1
for i in $(seq 1 30); do grep -qa 'TASK-CLOSE task=' "$LOG" && break; sleep 1; done
grep -a 'TASK-CLOSE' "$LOG" | tail -2
echo "  settle 6s..."; sleep 6

if [ "$WARP_OK" = 1 ] && ! crash_seen; then
  echo "  arming target.drive (marching south across the boundary); norepair=${NOREPAIR:-0} heal=${HEAL:-default}..."
  [ "${NOREPAIR:-0}" = "1" ] && A shell setprop debug.opengoal.diag.norepair 1 >/dev/null 2>&1
  A shell "setprop debug.opengoal.target.drive '$DRIVE'" >/dev/null 2>&1
fi

echo "  observing ${OBS}s for swamp-load + crash..."
SWAMP=0; CR=0
for i in $(seq 1 "$OBS"); do
  if [ "$SWAMP" = 0 ] && grep -qa 'Adding level swamp' "$LOG"; then SWAMP=1; echo "  >>> Adding level swamp ~${i}s (SWA streaming from real position)"; fi
  if crash_seen; then CR=1; echo "  >>> CRASH ~${i}s"; break; fi
  sleep 1
done
sleep 2
A exec-out screencap -p > "$OUT/$TAG-end.png" 2>/dev/null || true

FOC="no"; focus_is_app && FOC="yes"
{
  echo "=== grv_drive $TAG $(date -Is) ==="
  echo "RESULT tag=$TAG warp_ok=$WARP_OK swamp_load=$SWAMP crashed=$CR focus_app=$FOC"
  echo "--- last TARGET-DRIVE pos ---"; grep -aoE 'TARGET-DRIVE pos=\([^)]*\)' "$LOG" | tail -3
  echo "--- adding-level ---"; grep -aoE 'Adding level [a-z0-9-]+' "$LOG" | tail -8 | tr '\n' ' '; echo
  echo "--- links ---"; grep -aoE 'link finish: [a-z0-9-]+' "$LOG" | tail -10 | tr '\n' ' '; echo
  echo "--- crash sig ---"; grep -aoE 'Fatal signal [0-9]+ \(SIG[A-Z]+\)[^,]*|GK-DIAG sig=[0-9]+ fault=0x[0-9a-f]+ pc=0x[0-9a-f]+ lr=0x[0-9a-f]+' "$LOG" | tail -4
  echo "--- BARERET-FORENSIC ---"; grep -aE 'BARERET-FORENSIC' "$LOG" | tail -20
  echo "--- nearest goal fn (pc/lr/fault) ---"; grep -aE 'GK-DIAG.*(pc|lr|fault|caller)=.*\+0x|nearest|goal-fn|A34-DIAG (fp-walk|pp)' "$LOG" | tail -20
  echo "--- GECHO break-probe / suspend-tolerate ---"; grep -aE 'GECHO|ECHO-SUSPEND-TOLERATE|GRV-BARE-RET-REPAIR|ENTER-STATE-CODE-REPAIR|RFTD-NULLRET' "$LOG" | tail -8
} | tee "$RES"
kill "$LOGPID" 2>/dev/null || true
trap - EXIT
for p in level.warp level.warp.pos task.close target.drive diag.norepair; do
  A shell setprop debug.opengoal.$p '""' >/dev/null 2>&1 || true; done
A shell am force-stop "$PKG" >/dev/null 2>&1 || true
echo "== $TAG done: swamp_load=$SWAMP crashed=$CR =="
