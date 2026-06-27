#!/usr/bin/env bash
# Gledge-glitch edge-grab reproduction+capture driver.
#
# Assumes the GLEDGE-INSTRUMENT libgk is ALREADY deployed to the device (this
# script does NOT build or install). It warps to Geyser Rock (F1), arms the
# readable GLEDGE log path (kmachine.cpp gledge_dump_collision, gated by prop
# debug.opengoal.gledge.log==1, runs while pad_replay is OFF), then drives a
# cpad_inject forward-jump-into-walls sweep to provoke ledge/edge grabs and the
# "projects/launches Jak" glitch. It captures the per-frame readable GLEDGE
# lines:
#   GLEDGE f=.. st=EGRAB|EGRAB-OFF|EGRAB-JUMP|other tr=.. tv=.. |tv|=.. uv100=..
#          uv101=.. wv0=.. wv1=.. egpat=........
# st=other heartbeats appear every 600 frames; edge-grab states emit EGRAB lines;
# a launch shows a large |tv|. The end-of-run summary reports the distinct st=
# tags, every EGRAB* line, any large-|tv| (launch) line, and app foreground.
#
# Usage: gledge_drive.sh <run_tag>
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh
. .autoport/lib/device-validate.sh

RUN_TAG="${1:-run1}"
OUT_DIR=".autoport/reports/Gledge-glitch"
mkdir -p "$OUT_DIR"
PACKAGE="org.opengoal.gk.jak1"
SERIAL="${ANDROID_SERIAL:-eae4df44}"
export ANDROID_SERIAL="$SERIAL"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
INJECT="/data/data/$PACKAGE/files/cpad_inject"
LOG="$OUT_DIR/$RUN_TAG-gledge.log"
RESULT="$OUT_DIR/$RUN_TAG-result.txt"
A(){ "$ADB" -s "$SERIAL" "$@"; }
inj(){ printf '%s' "$1" | A shell "run-as $PACKAGE sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; }
snap(){ A shell screencap -p /sdcard/gledge.png >/dev/null 2>&1 || true; A pull /sdcard/gledge.png "$OUT_DIR/$RUN_TAG-$1.png" >/dev/null 2>&1 || true; }

# Require device attached + unlocked; reuse the already-deployed instrumented libgk.
device_require_attached; device_stayon_on
A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
device_require_unlocked

echo "== arm F1 warp + readable GLEDGE log, pad_replay OFF, (re)launch =="
A shell setprop debug.opengoal.f1.warp 1 >/dev/null 2>&1 || true
A shell setprop debug.opengoal.gledge.log 1 >/dev/null 2>&1 || true
A shell setprop debug.opengoal.pad_replay "" >/dev/null 2>&1 || true
A shell setprop debug.opengoal.gledge 0 >/dev/null 2>&1 || true
inj ""
A shell am force-stop "$PACKAGE" >/dev/null 2>&1 || true
sleep 2
A logcat -c >/dev/null 2>&1 || true
A shell am start -n "$PACKAGE/.LoaderActivity" >/dev/null 2>&1 || true
( A logcat -v time GK_STDOUT:I '*:S' > "$LOG" 2>&1 ) &
LCPID=$!
# Disarm gledge.log + f1.warp on exit, kill logcat, clear injection.
trap 'kill $LCPID 2>/dev/null || true; inj ""; A shell setprop debug.opengoal.gledge.log 0 >/dev/null 2>&1 || true; A shell setprop debug.opengoal.f1.warp 0 >/dev/null 2>&1 || true' EXIT

echo "== wait for link finish + F1-SPAWN (up to 120s) =="
for i in $(seq 1 60); do grep -aq "F1-SPAWN" "$LOG" && break; sleep 2; done
grep -aq "F1-SPAWN" "$LOG" || echo "WARN: no F1-SPAWN yet"
sleep 6
snap 00_spawn

# Baseline: NO input, standing. Lets the st=other heartbeat establish.
echo "== baseline: 6s no input =="; inj ""; sleep 6; snap 01_idle

# Drive: forward-jumps into walls right of the steps, with steering sweeps.
# Each micro-step: hold a token ~0.9s, release ~0.3s, so a dropped event has a
# window; repeat across steering angles to hit several walls / ledges.
drive_seq() {
  local steer="$1"
  inj "ly=20 ${steer}"; sleep 1.0
  inj "ly=20 ${steer} x"; sleep 0.7
  inj "ly=20 ${steer}"; sleep 1.0
  inj "ly=20 ${steer} x"; sleep 0.7
  inj "ly=20 ${steer}"; sleep 1.2
  inj ""; sleep 1.5     # RELEASE everything, let any latched state settle + log
}
for pass in 1 2 3 4 5 6; do
  for steer in "" "lx=70" "lx=185" "lx=40" "lx=210" ""; do
    drive_seq "$steer"
  done
  inj ""; sleep 2.0
  snap "pass${pass}"
  LAST=$(grep -a "GLEDGE" "$LOG" | tail -1)
  echo "  pass${pass} last: $LAST"
done

# Final: ensure released, dwell 8s so any latched edge-grab state is densely logged.
inj ""; sleep 8; snap 99_final
kill $LCPID 2>/dev/null || true

echo "== ANALYSIS ==" | tee "$RESULT"
echo "-- distinct st= tags seen --" | tee -a "$RESULT"
grep -ao 'st=[A-Z-]*' "$LOG" | sort | uniq -c | sort -rn | tee -a "$RESULT"
echo "-- EGRAB / EGRAB-OFF / EGRAB-JUMP lines --" | tee -a "$RESULT"
grep -aE 'st=EGRAB(-OFF|-JUMP)?\b' "$LOG" | tee -a "$RESULT"
EG_N=$(grep -acE 'st=EGRAB(-OFF|-JUMP)?\b' "$LOG")
echo "  edge-grab line count = $EG_N" | tee -a "$RESULT"
echo "-- launch lines (|tv| > 150000) --" | tee -a "$RESULT"
grep -aE '\|tv\|=[0-9]{6,}' "$LOG" | tee -a "$RESULT"
LV_N=$(grep -acE '\|tv\|=[0-9]{6,}' "$LOG")
echo "  launch (large-|tv|) line count = $LV_N" | tee -a "$RESULT"
echo "-- any non-finite floats? --" | tee -a "$RESULT"
grep -a "GLEDGE" "$LOG" | grep -aciE 'nan|inf' | tee -a "$RESULT"
FOC=$(A shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | grep -c "$PACKAGE")
if [ "$FOC" -ge 1 ]; then
  echo "app_foreground=YES ($PACKAGE)  logcat=$LOG" | tee -a "$RESULT"
else
  echo "app_foreground=NO (app not focused -> possible crash/exit)  logcat=$LOG" | tee -a "$RESULT"
fi
echo "DONE $RUN_TAG"
