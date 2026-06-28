#!/usr/bin/env bash
# Record a MOVEMENT-ONLY held input (no attack button) on the device, then replay
# TWICE; compare per-logic-frame state traces — tests whether the device replay is
# state-deterministic for pure movement (isolates the held-attack/circle as the
# non-determinism trigger).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
INJECT="lx=200 ly=60"   # right+forward, no buttons
D=.autoport/reports/Ginput-replay-liverecord
adb(){ "$ADB" -s "$S" "$@"; }
die(){ echo "[movdet FAIL] $*" >&2; exit 1; }
adb shell svc power stayon true >/dev/null 2>&1 || true
launch_wait_anchor(){ local LOG="$1"; : > "$LOG"; adb logcat -c >/dev/null 2>&1||true
  ( adb logcat -v threadtime 2>/dev/null | grep --line-buffered -aE 'ANCHOR reached|Fatal signal' > "$LOG" ) & LCP=$!
  adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1||true
  local t0; t0=$(date +%s); while [ $(( $(date +%s)-t0 )) -lt 100 ]; do grep -aq 'ANCHOR reached' "$LOG" && return 0; sleep 3; done
  kill "$LCP" 2>/dev/null||true; die "anchor timeout"; }

echo "[movdet] RECORD movement-only '$INJECT'"
adb shell am force-stop $PKG >/dev/null 2>&1||true
adb shell run-as $PKG sh -c 'rm -f files/pad_demo.inputs files/mov_rec.statedump.txt' 2>/dev/null||true
adb shell "setprop debug.opengoal.cpad_inject '$INJECT'"
adb shell setprop debug.opengoal.f1.warp 1
adb shell setprop debug.opengoal.pad_replay record
adb shell setprop debug.opengoal.pad_trace mov_rec.statedump.txt
launch_wait_anchor /tmp/movrec.log; echo "  recording 15s"; sleep 15
adb shell am force-stop $PKG >/dev/null 2>&1||true; kill "$LCP" 2>/dev/null||true
adb exec-out run-as $PKG cat files/pad_demo.inputs > "$D/mov.inputs" 2>/dev/null
adb exec-out run-as $PKG cat files/mov_rec.statedump.txt > "$D/mov_rec.trace" 2>/dev/null
adb shell "setprop debug.opengoal.cpad_inject ''" 2>/dev/null||true

do_replay(){ adb shell am force-stop $PKG >/dev/null 2>&1||true
  adb push "$D/mov.inputs" /data/local/tmp/pad_demo.inputs >/dev/null 2>&1||die push
  adb shell run-as $PKG cp /data/local/tmp/pad_demo.inputs files/pad_demo.inputs||die cp
  adb shell run-as $PKG sh -c "rm -f files/$1.statedump.txt" 2>/dev/null||true
  adb shell setprop debug.opengoal.f1.warp 1; adb shell setprop debug.opengoal.pad_replay replay
  adb shell setprop debug.opengoal.pad_trace "$1.statedump.txt"
  launch_wait_anchor /tmp/$1.log; echo "  $1 replaying 15s"; sleep 15
  adb shell am force-stop $PKG >/dev/null 2>&1||true; kill "$LCP" 2>/dev/null||true
  adb exec-out run-as $PKG cat "files/$1.statedump.txt" > "$D/$1.trace" 2>/dev/null; }
echo "[movdet] REPLAY #1"; do_replay movrep1
echo "[movdet] REPLAY #2"; do_replay movrep2
adb shell "setprop debug.opengoal.f1.warp ''" 2>/dev/null||true
adb shell "setprop debug.opengoal.pad_replay ''" 2>/dev/null||true
adb shell "setprop debug.opengoal.pad_trace ''" 2>/dev/null||true
echo "[movdet] BYTE-MATCH + DETERMINISM"
python3 .autoport/glive_analyze.py "$D/mov.inputs" "$INJECT" | grep -E 'INPUT CAPTURED|byte-match|VERDICT'
python3 - "$D/mov_rec.trace" "$D/movrep1.trace" "$D/movrep2.trace" <<'PY'
import sys,os
def load(p):
    return {int(l.split()[1].split('=')[1]):l.strip() for l in open(p) if l.startswith("ci frame=")} if os.path.exists(p) else {}
rec,r1,r2=load(sys.argv[1]),load(sys.argv[2]),load(sys.argv[3])
def cmp(a,b):
    c=sorted(set(a)&set(b)); d=[f for f in c if a[f]!=b[f]]; return (d[0] if d else -1), len(c)
d12,n12=cmp(r1,r2); dr1,nr1=cmp(rec,r1)
print(f"frames rec={len(rec)} rep1={len(r1)} rep2={len(r2)}")
print(f"REPLAY==REPLAY: {'BIT-IDENTICAL 0/'+str(n12)+' — determinism intact' if d12<0 else 'diverge at '+str(d12)+'/'+str(n12)}")
print(f"RECORD==REPLAY: {'BIT-IDENTICAL 0/'+str(nr1)+' (record-trace == replay-trace)' if dr1<0 else 'diverge at '+str(dr1)+'/'+str(nr1)}")
PY
echo "[movdet] DONE"
