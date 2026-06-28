#!/usr/bin/env bash
# Determinism check: replay after.inputs TWICE on the device, compare the two
# per-logic-frame state traces (replay determinism) and vs the record trace.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
D=.autoport/reports/Ginput-replay-liverecord
adb(){ "$ADB" -s "$S" "$@"; }
die(){ echo "[det FAIL] $*" >&2; exit 1; }
[ -s "$D/after.inputs" ] || die "no after.inputs"
adb shell svc power stayon true >/dev/null 2>&1 || true
launch_wait_anchor(){
  local LOG="$1"; : > "$LOG"; adb logcat -c >/dev/null 2>&1 || true
  ( adb logcat -v threadtime 2>/dev/null | grep --line-buffered -aE 'ANCHOR reached|Fatal signal' > "$LOG" ) & LCP=$!
  adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
  local t0; t0=$(date +%s)
  while [ $(( $(date +%s) - t0 )) -lt 100 ]; do grep -aq 'ANCHOR reached' "$LOG" && return 0; sleep 3; done
  kill "$LCP" 2>/dev/null||true; die "anchor timeout"
}
do_replay(){ # $1=trace tag
  adb shell am force-stop $PKG >/dev/null 2>&1 || true
  adb shell "setprop debug.opengoal.cpad_inject ''" 2>/dev/null || true
  adb push "$D/after.inputs" /data/local/tmp/pad_demo.inputs >/dev/null 2>&1 || die "push"
  adb shell run-as $PKG cp /data/local/tmp/pad_demo.inputs files/pad_demo.inputs || die "cp"
  adb shell run-as $PKG sh -c "rm -f files/$1.statedump.txt" 2>/dev/null || true
  adb shell setprop debug.opengoal.f1.warp 1
  adb shell setprop debug.opengoal.pad_replay replay
  adb shell setprop debug.opengoal.pad_trace "$1.statedump.txt"
  launch_wait_anchor /tmp/glive_$1.log
  echo "  $1 anchored; replaying 15s"; sleep 15
  adb shell am force-stop $PKG >/dev/null 2>&1 || true; kill "$LCP" 2>/dev/null||true
  adb exec-out run-as $PKG cat "files/$1.statedump.txt" > "$D/$1.trace" 2>/dev/null
}
echo "[det] replay #1"; do_replay rep1
echo "[det] replay #2"; do_replay rep2
adb shell "setprop debug.opengoal.f1.warp ''" 2>/dev/null || true
adb shell "setprop debug.opengoal.pad_replay ''" 2>/dev/null || true
adb shell "setprop debug.opengoal.pad_trace ''" 2>/dev/null || true
echo "[det] compare"
python3 - "$D/after_rec.trace" "$D/rep1.trace" "$D/rep2.trace" <<'PY'
import sys
def load(p):
    try: return [l.rstrip("\n") for l in open(p) if l.startswith("ci frame=")]
    except: return []
rec,rep1,rep2=load(sys.argv[1]),load(sys.argv[2]),load(sys.argv[3])
def cmp(a,b):
    n=min(len(a),len(b))
    for i in range(n):
        if a[i]!=b[i]: return i,n
    return -1,n
d12,n12=cmp(rep1,rep2); dr1,nr1=cmp(rec,rep1)
print(f"frames rec={len(rec)} rep1={len(rep1)} rep2={len(rep2)}")
if d12<0: print(f"REPLAY DETERMINISM: replay==replay BIT-IDENTICAL over all {n12} common logic frames (0/{n12}) — determinism intact")
else: print(f"REPLAY DETERMINISM: replay1 vs replay2 diverge at common frame {d12}/{n12}")
if dr1<0: print(f"RECORD==REPLAY: record-trace == replay-trace BIT-IDENTICAL over all {nr1} ({nr1} frames, 0 divergences)")
else: print(f"RECORD vs REPLAY: diverge at common frame {dr1}/{nr1}")
PY
echo "[det] DONE"
