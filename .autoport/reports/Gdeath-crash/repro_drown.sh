#!/usr/bin/env bash
# Free death repro on the CURRENT (owner) device build: warp to Geyser Rock, then
# drive Jak into the water / off edges to provoke a drown-death or endlessfall.
# Tracks target Y (GK-DIAG F1D target-pos) and watches for the crash forensics.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh 2>/dev/null
ADB="/home/emeric/Android/platform-tools/adb"; S=eae4df44; PKG=org.opengoal.gk.jak1
INJECT="/data/data/$PKG/files/cpad_inject"
OUT=.autoport/reports/Gdeath-crash
LOG="$OUT/drown-logcat.log"; ST="$OUT/drown-status.txt"
A(){ "$ADB" -s "$S" "$@"; }
inject(){ printf '%s' "$1" | A shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; }
clr(){ inject ""; }
crash(){ grep -qaE 'Fatal signal|signal (11|6|4) \(SIG|GK-DIAG sig=(4|6|11)' "$LOG" 2>/dev/null; }

echo "START $(date -Iseconds)" > "$ST"
A shell svc power stayon true >/dev/null 2>&1 || true
A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
A shell setprop debug.opengoal.pad_replay "" >/dev/null 2>&1 || true
A shell setprop debug.opengoal.f1.warp 1 >/dev/null 2>&1 || true
A shell setprop debug.opengoal.f1.census 1 >/dev/null 2>&1 || true
A shell am force-stop $PKG; clr
A logcat -G 64M >/dev/null 2>&1 || true; A logcat -c 2>/dev/null || true
sleep 1
( A logcat -v threadtime opengoal-gk:V GK_STDOUT:V GK_STDERR:V libc:F DEBUG:V '*:S' > "$LOG" 2>&1 ) &
LC=$!
A shell am start -W -n "$PKG/.LoaderActivity" >/dev/null 2>&1
echo "launched $(date -Iseconds)" >> "$ST"

# wait for warp + training load (up to 9 min)
TR=0
for i in $(seq 1 108); do
  sleep 5
  grep -qaE 'Adding level training|link finish: training-vis' "$LOG" && { TR=1; echo "training ~$((i*5))s" >> "$ST"; break; }
  crash && { echo "CRASH-before-training $((i*5))s" >> "$ST"; break; }
done
echo "TR=$TR" >> "$ST"

if [ "$TR" = 1 ] && ! crash; then
  sleep 20   # settle
  echo "begin death-seeking inject $(date -Iseconds)" >> "$ST"
  # Sweep headings, run hard off the island into water; hold long enough to drown
  # (swim-stuck ~10s) or fall below bottom-height (endlessfall ~2s).
  for rx in 0 32 64 96 128 160 192 224; do
    crash && break
    inject "rx=$rx"; sleep 0.8
    inject "ly=10 rx=$rx"; sleep 6.0   # full forward (off edge / into water), long hold
    inject "ly=10 x";      sleep 0.4   # jump (clear ledge)
    inject "ly=10";        sleep 5.0   # keep going (drown timer)
    Y=$(grep -aoE 'target-pos f=[0-9]+ \*target\* 0x[0-9a-f]+ =\([^)]*\)' "$LOG" | tail -1)
    echo "  heading rx=$rx lastpos: $Y" >> "$ST"
    clr; sleep 1
  done
  # observe for drown/endlessfall death + crash
  for i in $(seq 1 40); do sleep 1; crash && { echo "CRASH-during-observe" >> "$ST"; break; }; done
fi
clr
DEATH=$(grep -aoE 'target-death|drown|endlessfall|initialize.*dead|continue-point' "$LOG" | sort | uniq -c | tr '\n' ';')
FOCUS=$(A shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1)
PID=$(A shell pidof $PKG 2>/dev/null)
{ echo "DEATH-MARKERS: ${DEATH:-none}"; echo "FOCUS: $FOCUS"; echo "PID: ${PID:-none}"; echo "CRASH: $(crash && echo YES || echo no)"; echo "DONE $(date -Iseconds)"; } >> "$ST"
A shell setprop debug.opengoal.f1.warp 0 >/dev/null 2>&1 || true
kill $LC 2>/dev/null || true
echo "loglines: $(wc -l < "$LOG")" >> "$ST"
