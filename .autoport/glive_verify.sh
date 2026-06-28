#!/usr/bin/env bash
# Ginput-replay-liverecord verification (device eae4df44, must be UNLOCKED):
#  BEFORE  — warp+record, NO input -> all-neutral demo + the honest-failure WARN fires.
#  AFTER   — warp+record + robust PROP inject (known held state) -> demo byte-matches + record-trace.
#  REPLAY  — warp+replay AFTER demo -> replay-trace; record-trace == replay-trace (determinism intact).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
INJECT="lx=200 ly=60"
D=.autoport/reports/Ginput-replay-liverecord; mkdir -p "$D"
adb(){ "$ADB" -s "$S" "$@"; }
say(){ echo "[glive-verify] $*"; }
die(){ echo "[glive-verify FAIL] $*" >&2; exit 1; }

adb get-state >/dev/null 2>&1 || die "device not attached"
[ "$(adb shell dumpsys window 2>/dev/null | grep -m1 mDreamingLockscreen | grep -c true)" = "0" ] || die "device locked"
adb shell svc power stayon true >/dev/null 2>&1 || true

# launch + wait for the warp anchor (record or replay). $1=logfile
launch_wait_anchor(){
  local LOG="$1"; : > "$LOG"
  adb logcat -c >/dev/null 2>&1 || true
  ( adb logcat -v threadtime 2>/dev/null | grep --line-buffered -aE 'pad_replay:|ANCHOR reached|PR-DIAG|LIVE-RECORD WARNING|F1D-INJECT applied|Fatal signal' > "$LOG" ) &
  LCP=$!
  adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
  local t0; t0=$(date +%s)
  while [ $(( $(date +%s) - t0 )) -lt 100 ]; do
    grep -aq 'ANCHOR reached' "$LOG" && return 0
    grep -aqE 'Fatal signal' "$LOG" && { kill "$LCP" 2>/dev/null||true; die "crash before anchor"; }
    sleep 3
  done
  kill "$LCP" 2>/dev/null||true; die "anchor not reached in 100s"
}
pull(){ adb exec-out run-as "$PKG" cat "files/$1" > "$2" 2>/dev/null; }

# ---------- BEFORE: all-neutral + WARN ----------
say "BEFORE: warp+record, NO input"
adb shell am force-stop $PKG >/dev/null 2>&1 || true
adb shell "setprop debug.opengoal.cpad_inject ''" 2>/dev/null || true
adb shell run-as $PKG sh -c 'rm -f files/pad_demo.inputs files/cpad_inject' 2>/dev/null || true
adb shell setprop debug.opengoal.f1.warp 1
adb shell setprop debug.opengoal.pad_replay record
adb shell "setprop debug.opengoal.pad_trace ''" 2>/dev/null || true
launch_wait_anchor /tmp/glive_before.log
say "  anchored; recording 13s with NO input"
sleep 13
adb shell am force-stop $PKG >/dev/null 2>&1 || true
kill "$LCP" 2>/dev/null || true
pull pad_demo.inputs "$D/before.inputs"
cp /tmp/glive_before.log "$D/before_logcat.txt" 2>/dev/null || true
[ -s "$D/before.inputs" ] || die "before.inputs empty"
say "  BEFORE warn lines: $(grep -ac 'LIVE-RECORD WARNING' /tmp/glive_before.log)"

# ---------- AFTER: prop inject -> capture + record-trace ----------
say "AFTER: warp+record + PROP inject '$INJECT' + trace"
adb shell am force-stop $PKG >/dev/null 2>&1 || true
adb shell run-as $PKG sh -c 'rm -f files/pad_demo.inputs files/after_rec.statedump.txt' 2>/dev/null || true
adb shell "setprop debug.opengoal.cpad_inject '$INJECT'"
adb shell setprop debug.opengoal.f1.warp 1
adb shell setprop debug.opengoal.pad_replay record
adb shell setprop debug.opengoal.pad_trace after_rec.statedump.txt
launch_wait_anchor /tmp/glive_after.log
say "  anchored; recording 15s with held inject"
sleep 15
adb shell am force-stop $PKG >/dev/null 2>&1 || true
kill "$LCP" 2>/dev/null || true
pull pad_demo.inputs "$D/after.inputs"
pull after_rec.statedump.txt "$D/after_rec.trace"
cp /tmp/glive_after.log "$D/after_logcat.txt" 2>/dev/null || true
[ -s "$D/after.inputs" ] || die "after.inputs empty"

# ---------- REPLAY: replay AFTER demo -> replay-trace ----------
say "REPLAY: warp+replay after.inputs + trace"
adb shell am force-stop $PKG >/dev/null 2>&1 || true
adb shell "setprop debug.opengoal.cpad_inject ''" 2>/dev/null || true
adb push "$D/after.inputs" /data/local/tmp/pad_demo.inputs >/dev/null 2>&1 || die "push demo failed"
adb shell run-as $PKG cp /data/local/tmp/pad_demo.inputs files/pad_demo.inputs || die "cp demo failed"
adb shell run-as $PKG sh -c 'rm -f files/after_rep.statedump.txt' 2>/dev/null || true
adb shell setprop debug.opengoal.f1.warp 1
adb shell setprop debug.opengoal.pad_replay replay
adb shell setprop debug.opengoal.pad_trace after_rep.statedump.txt
launch_wait_anchor /tmp/glive_replay.log
say "  anchored; replaying 15s"
sleep 15
adb shell am force-stop $PKG >/dev/null 2>&1 || true
kill "$LCP" 2>/dev/null || true
pull after_rep.statedump.txt "$D/after_rep.trace"

# clear props
adb shell "setprop debug.opengoal.f1.warp ''" 2>/dev/null || true
adb shell "setprop debug.opengoal.pad_replay ''" 2>/dev/null || true
adb shell "setprop debug.opengoal.pad_trace ''" 2>/dev/null || true
adb shell "setprop debug.opengoal.cpad_inject ''" 2>/dev/null || true

# ---------- analyze ----------
say "=== ANALYZE ==="
echo "--- BEFORE (expect all-neutral) ---"
python3 .autoport/glive_analyze.py "$D/before.inputs" "$INJECT" | grep -E 'INPUT CAPTURED|VERDICT'
echo "--- AFTER (expect captured + byte-match) ---"
python3 .autoport/glive_analyze.py "$D/after.inputs" "$INJECT" | grep -E 'INPUT CAPTURED|byte-match|VERDICT'
echo "--- DETERMINISM (record-trace vs replay-trace) ---"
if [ -s "$D/after_rec.trace" ] && [ -s "$D/after_rep.trace" ]; then
  python3 - "$D/after_rec.trace" "$D/after_rep.trace" <<'PY'
import sys
rec=[l.rstrip("\n") for l in open(sys.argv[1]) if l.startswith("ci frame=")]
rep=[l.rstrip("\n") for l in open(sys.argv[2]) if l.startswith("ci frame=")]
n=min(len(rec),len(rep))
div=-1
for i in range(n):
    if rec[i]!=rep[i]: div=i; break
print(f"record-trace frames={len(rec)} replay-trace frames={len(rep)} common={n}")
if div<0: print(f"DETERMINISM: record-trace == replay-trace, BIT-IDENTICAL over all {n} common logic frames (0/{n} divergences) — determinism intact")
else: print(f"DETERMINISM: FIRST DIVERGENCE at common frame {div}")
PY
else
  echo "DETERMINISM: trace(s) missing rec=$(wc -l < "$D/after_rec.trace" 2>/dev/null) rep=$(wc -l < "$D/after_rep.trace" 2>/dev/null)"
fi
echo "--- WARN fired in BEFORE? ---"
grep -a 'LIVE-RECORD WARNING' /tmp/glive_before.log | head -2
say "DONE"
