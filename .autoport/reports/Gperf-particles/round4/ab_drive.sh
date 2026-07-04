#!/usr/bin/env bash
# Gperf-particles round-4 in-session A/B driver — Rock Village fire pose.
# Measures the phase-level A/B (ALL-OLD vs ALL-FIX) plus isolates the NEW round-4
# 2D-vectorize fix (no2dvec) marginal contribution on top of the round-1..3 fixes.
#
# Windows (all in ONE boot, camera untouched after warp-settle, scale pinned floor=40):
#   A  = ALL 7 switches = 1  (fully OLD / pre-phase)
#   C  = prior fixes ON, new fix OFF (no2dvec=1, others=0)  -> round-3 state
#   B  = ALL 7 switches = 0  (ALL fixes ON incl round-4)    -> HEADLINE after
#   A2 = ALL 7 switches = 1  (revert -> reversibility proof)
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
OUT=.autoport/reports/Gperf-particles/round4
mkdir -p "$OUT"
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
SERIAL="${ANDROID_SERIAL:-eae4df44}"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
LOG="$OUT/ab-logcat.txt"; MK="$OUT/timemarkers.txt"
A(){ "$ADB" -s "$SERIAL" "$@"; }
SW=(nospritelean nostatecache noinstance nooverlap notodpp noshrubidx no2dvec)
setall(){ for s in "${SW[@]}"; do A shell setprop "debug.opengoal.perf.$s" "$1" >/dev/null 2>&1; done; }
setlist(){ # setlist "val_default" name=val name=val ...
  local d="$1"; shift; for s in "${SW[@]}"; do A shell setprop "debug.opengoal.perf.$s" "$d" >/dev/null 2>&1; done
  for kv in "$@"; do A shell setprop "debug.opengoal.perf.${kv%=*}" "${kv#*=}" >/dev/null 2>&1; done; }
now(){ date +%H:%M:%S; }
focus_ok(){ A shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | grep -q "$PKG"; }
maxframe(){ grep -aoE 'A35-RENDER frame=[0-9]+' "$LOG" | grep -oE '[0-9]+$' | sort -n | tail -1; }
: > "$MK"

# --- keep awake / unlock gate ---
A shell svc power stayon true >/dev/null 2>&1 || true
A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
if A shell dumpsys window 2>/dev/null | grep -q 'mDreamingLockscreen=true'; then
  echo "PIN-LOCKED — needs owner unlock" | tee "$OUT/ABORT.txt"; exit 2; fi

# --- arm warp + perf dump, fresh boot ---
setall 0                                   # start clean (fixes ON); windows re-set below
A shell setprop debug.opengoal.perf.buckets 1 >/dev/null 2>&1
A shell setprop debug.opengoal.level.warp village2-start >/dev/null 2>&1
A shell setprop debug.opengoal.spart.dump '""' >/dev/null 2>&1
A shell am force-stop "$PKG" >/dev/null 2>&1 || true
A logcat -G 128M >/dev/null 2>&1 || true; A logcat -c >/dev/null 2>&1 || true
A logcat -v threadtime opengoal-gk:V GK_STDOUT:V GK_STDERR:V opengoal-loader:V libc:F DEBUG:V '*:S' > "$LOG" 2>&1 &
LPID=$!; trap 'kill $LPID 2>/dev/null; A shell setprop debug.opengoal.level.warp "\"\"" >/dev/null 2>&1' EXIT
A shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true

echo "warming to title + warp-spawn (<=180s)..."
for i in $(seq 1 180); do
  grep -qaE "LEVEL-WARP-SPAWN name=village2-start" "$LOG" && { echo "  warp fired ~${i}s"; break; }
  grep -qaE 'Fatal signal|signal (11|6|4) \(SIG|GK-DIAG sig=(4|6|11)' "$LOG" && { echo "  CRASH pre-warp ~${i}s" | tee "$OUT/ABORT.txt"; exit 3; }
  sleep 1
done
grep -qaE "LEVEL-WARP-SPAWN name=village2-start" "$LOG" || { echo "NO WARP" | tee "$OUT/ABORT.txt"; exit 3; }
echo "settle 30s (camera released, untouched hereafter)..."; sleep 30
focus_ok && echo "focus OK pre-A" || echo "!! focus NOT app pre-A"
A exec-out screencap -p > "$OUT/A-pose.png" 2>/dev/null || true

run_window(){ # run_window NAME SECONDS  (props already set)
  local nm="$1" sec="$2"
  echo "  [$nm] poll-settle 16s"; sleep 16
  local s=$(now); echo "WINDOW_${nm}_START=$s" | tee -a "$MK"
  echo "WINDOW_${nm}_STARTFRAME=$(maxframe)" >> "$MK"
  sleep "$sec"
  local e=$(now); echo "WINDOW_${nm}_END=$e" | tee -a "$MK"
  echo "WINDOW_${nm}_ENDFRAME=$(maxframe)" >> "$MK"
  focus_ok && echo "  [$nm] focus OK" || echo "  [$nm] !! focus NOT app"
  A exec-out screencap -p > "$OUT/${nm}-end.png" 2>/dev/null || true
}

echo "== WINDOW A: ALL OLD =="; setall 1; run_window A 90
echo "== WINDOW C: prior fixes ON, new fix OFF =="; setlist 0 no2dvec=1; run_window C 90
echo "== WINDOW B: ALL FIX ON =="; A exec-out screencap -p > "$OUT/B-pose.png" 2>/dev/null; setall 0; run_window B 90
echo "== WINDOW A2: revert ALL OLD =="; setall 1; run_window A2 55

# leave device in fixes-ON, clear warp
setall 0
A shell setprop debug.opengoal.level.warp '""' >/dev/null 2>&1
kill $LPID 2>/dev/null; trap - EXIT
echo "DONE. log=$LOG markers=$MK"
