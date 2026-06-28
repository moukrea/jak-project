#!/usr/bin/env bash
# Ginput-replay-liverecord: reproduce/verify a LIVE record under the f1.warp anchor
# using the headless cpad INJECTOR (the same merge path a live touch/gamepad uses).
# Arms warp + record, waits for the deterministic Geyser anchor, injects a KNOWN
# held non-neutral state, records ~RECSECS of gameplay, pulls pad_demo.inputs and
# analyzes non-neutral capture + byte-match vs the injected value.
#
#   arg1 = tag           (output basename under .autoport/reports/Ginput-replay-liverecord/)
#   arg2 = record seconds (default 25)
#   arg3 = inject string  (default "lx=200 ly=60 circle")
# Requires the device UNLOCKED (the game loop stalls behind the keyguard).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
TAG="${1:-before}"; RECSECS="${2:-25}"; INJECT="${3:-lx=200 ly=60 circle}"
D=.autoport/reports/Ginput-replay-liverecord; mkdir -p "$D"
adb(){ "$ADB" -s "$S" "$@"; }
say(){ echo "[glive-repro] $*"; }
die(){ echo "[glive-repro FAIL] $*" >&2; exit 1; }

adb get-state >/dev/null 2>&1 || die "device not attached"
# Require unlocked: the game loop needs a render surface.
LOCK=$(adb shell dumpsys window 2>/dev/null | grep -m1 mDreamingLockscreen | grep -c true)
[ "${LOCK:-0}" = "0" ] || die "device is keyguard-locked (mDreamingLockscreen=true) — owner must unlock"

say "force-stop, arm warp+record, clear inject(neutral)+logcat"
adb shell am force-stop $PKG >/dev/null 2>&1 || true
adb shell setprop debug.opengoal.f1.warp 1
adb shell setprop debug.opengoal.pad_replay record
adb shell setprop debug.opengoal.pad_trace '' 2>/dev/null || true
adb shell svc power stayon true 2>/dev/null || true
adb shell run-as $PKG sh -c 'rm -f files/cpad_inject; rm -f files/pad_demo.inputs' 2>/dev/null || true
adb logcat -c >/dev/null 2>&1 || true
LOG=/tmp/glive_${TAG}.log; : > "$LOG"
( adb logcat -v threadtime 2>/dev/null | grep --line-buffered -aE 'pad_replay:|ANCHOR reached|PR-DIAG|F1-WARP|F1-SPAWN|F1D-INJECT|Fatal signal|signal [0-9]+ \(SIG' > "$LOG" ) &
LCP=$!

say "launch"
adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true

say "wait for warp anchor (ANCHOR reached ... record), up to 90s"
t0=$(date +%s); anchored=0
while [ $(( $(date +%s) - t0 )) -lt 90 ]; do
  if grep -aq 'ANCHOR reached' "$LOG"; then anchored=1; break; fi
  if grep -aqE 'Fatal signal|signal [0-9]+ \(SIG' "$LOG"; then kill "$LCP" 2>/dev/null||true; die "CRASH before anchor (see $LOG)"; fi
  sleep 3
done
[ "$anchored" = "1" ] || { kill "$LCP" 2>/dev/null||true; die "warp anchor never reached in 90s (see $LOG)"; }
say "anchored: $(grep -a 'ANCHOR reached' "$LOG" | head -1)"

say "inject held known input: '$INJECT'"
adb shell run-as $PKG sh -c "printf '%s' '$INJECT' > files/cpad_inject"
sleep 1
adb shell run-as $PKG cat files/cpad_inject 2>/dev/null | sed 's/^/[inject-file] /'

say "record ${RECSECS}s of gameplay with held input"
sleep "$RECSECS"

say "clear inject (neutral) + force-stop to finalize"
adb shell run-as $PKG sh -c 'printf "" > files/cpad_inject' 2>/dev/null || true
sleep 1
adb shell am force-stop $PKG >/dev/null 2>&1 || true
kill "$LCP" 2>/dev/null || true

say "pull demo"
adb exec-out run-as $PKG cat files/pad_demo.inputs > "$D/${TAG}.inputs" 2>/dev/null
[ -s "$D/${TAG}.inputs" ] || die "demo pull failed/empty"
cp "$LOG" "$D/${TAG}_logcat.txt" 2>/dev/null || true

say "analyze"
python3 .autoport/glive_analyze.py "$D/${TAG}.inputs" "$INJECT" | tee "$D/${TAG}_analysis.txt"

echo "=== PR-DIAG tail ==="; grep -a 'PR-DIAG' "$LOG" | tail -8
echo "=== ANCHOR ==="; grep -a 'ANCHOR reached' "$LOG" | head -2
echo "=== F1D-INJECT applied ==="; grep -a 'F1D-INJECT applied' "$LOG" | tail -3
say "clear props"
adb shell setprop debug.opengoal.f1.warp '' 2>/dev/null || true
adb shell setprop debug.opengoal.pad_replay '' 2>/dev/null || true
say "OK tag=$TAG -> $D/${TAG}.inputs"
