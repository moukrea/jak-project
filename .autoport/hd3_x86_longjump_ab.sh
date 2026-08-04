#!/usr/bin/env bash
# hd3_x86_longjump_ab.sh — defect-7 (long jump broken with HD toggle ON) x86 A/B repro. v2.
# Same synthesized pad_replay demo (3x roll+X long-jump combos + 1 duck high jump, see
# hd3_gen_longjump_inputs.py) replayed twice: enhanced-models OFF then ON.
#
# v2 harness fixes (the 02:55 run was HARNESS-INCONCLUSIVE — target never left stance):
#  1. ANCHOR: pad_replay anchors on "*target* valid", which is TRUE ON THE TITLE SCREEN
#     (target-title-wait) — the whole demo was consumed before gameplay. Fix: OG_F1_WARP=1;
#     kmachine's pad_replay_anchor_reached defers the anchor until the warp has spawned Jak
#     at game-start (post title + level load). No manual (start 'play ...) needed.
#  2. TOGGLE: set recharged-enhanced-models? in the settings.ini BEFORE boot (the owner's real
#     mechanism) instead of a listener write racing the replay. Original file restored at exit.
#  3. PROBE WINDOW: the demo's neutral head is HEAD_S seconds so goalc (lt)+(build-game)+probe
#     install completes before the first combo; the script FAILS the leg as inconclusive if the
#     probe was not confirmed running before anchor+HEAD_S.
#  4. TIMEBASE (the 03:33 lesson): *display* actual-frame-counter (the demo index) counts
#     +1 per frame DRAWN (drawable.gc:1019) and this desktop draws ~12fps — under REALTIME
#     a 180s head = 15min wall, so the combos never played inside the watch window. v2 uses
#     the DESIGNED forced-timestep replay (no REALTIME): 1 logic tick per drawn frame,
#     bit-deterministic — the STRONGER instrument for the logic A/B (both legs are identical
#     sims unless the companion perturbs gameplay). The device-side hitch/timing theory is
#     tested separately ON DEVICE. Watch progress is measured in LOGIC frames polled via the
#     listener, never wall seconds.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
GK=build/game/gk; GOALC=build/goalc/goalc; ISO=out/jak1/iso
export DISPLAY="${DISPLAY:-:0}" XAUTHORITY="${XAUTHORITY:-/run/user/1000/.mutter-Xwaylandauth.RKSTQ3}"
export SDL_VIDEODRIVER=x11 LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
OUT=.autoport/reports/Grecharged-hd-models3; mkdir -p "$OUT"
R="$OUT/longjump_ab_x86.txt"; : > "$R"
INPUTS=/tmp/hd3_longjump.inputs
HEAD_T="${HEAD_T:-1200}"          # neutral head (logic ticks) between anchor and first combo
# gk runs --portable -> config dir = executable's parent -> build/game/OpenGOAL/...
SETTINGS="build/game/OpenGOAL/jak1/settings/settings.ini"

[ "$ISO/GAME.CGO" -nt goal_src/jak1/pc/jak-hd.gc ] || { echo "FAIL: GAME.CGO stale vs jak-hd.gc — run (mi) first" | tee -a "$R"; exit 1; }
[ -f "$SETTINGS" ] || { echo "FAIL: no settings.ini at $SETTINGS" | tee -a "$R"; exit 1; }
grep -q 'recharged-enhanced-models?' "$SETTINGS" || { echo "FAIL: settings.ini lacks recharged-enhanced-models? key" | tee -a "$R"; exit 1; }
cp -f "$SETTINGS" /tmp/hd3_lj_settings_backup.ini
trap 'cp -f /tmp/hd3_lj_settings_backup.ini "$SETTINGS"' EXIT

python3 .autoport/hd3_gen_longjump_inputs.py "$INPUTS" "$HEAD_T" | tee -a "$R"
TOTAL_T=$(( ($(stat -c%s "$INPUTS") - 64) / 6 ))
echo "demo total: $TOTAL_T logic ticks (head $HEAD_T)" | tee -a "$R"
mkdir -p out/jak1/obj && cp -f recharged_assets/hd_anim/jak-hd-ag.go out/jak1/obj/jak-hd-ag.go

run_leg() {  # $1 = off|on
  local LEG="$1" TOGGLE GKLOG GCLOG FIFO GKPID GCPID
  [ "$LEG" = on ] && TOGGLE='#t' || TOGGLE='#f'
  sed -i "s/^recharged-enhanced-models? = .*/recharged-enhanced-models? = $TOGGLE/" "$SETTINGS"
  GKLOG="$OUT/.lj_${LEG}_gk.log"; GCLOG="$OUT/.lj_${LEG}_gc.log"; : > "$GKLOG"; : > "$GCLOG"
  FIFO="$(mktemp -u)"; mkfifo "$FIFO"
  OG_F1_WARP=1 OG_PAD_REPLAY_REPLAY="$INPUTS" \
    "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data "$ISO" -- -boot -debug-mem > "$GKLOG" 2>&1 &
  GKPID=$!
  # anchor = F1-SPAWN (warp spawned Jak at game-start; pad_replay latches here)
  local anchored=0 T_ANCHOR=0
  for i in $(seq 1 240); do
    kill -0 "$GKPID" 2>/dev/null || { echo "[$LEG] FAIL: gk exited during boot/warp" | tee -a "$R"; rm -f "$FIFO"; return 1; }
    grep -aq 'F1-SPAWN tx=' "$GKLOG" 2>/dev/null && { anchored=1; T_ANCHOR=$(date +%s); break; }
    sleep 1
  done
  [ "$anchored" = 1 ] || { echo "[$LEG] FAIL: F1 warp never spawned (no F1-SPAWN in 240s)" | tee -a "$R"; kill "$GKPID" 2>/dev/null; rm -f "$FIFO"; return 1; }
  echo "[$LEG] warp spawned at $(date +%H:%M:%S); probe must be live before anchor+${HEAD_T} ticks" | tee -a "$R"
  timeout 900 "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" < "$FIFO" > "$GCLOG" 2>&1 &
  GCPID=$!; exec 3>"$FIFO"
  echo '(lt)' >&3; sleep 5
  echo '(build-game)' >&3
  for i in $(seq 1 240); do sleep 1; grep -aqiE "Successfully built all|Build Successful" "$GCLOG" 2>/dev/null && break; done
  sleep 2
  echo '(process-spawn-function process (lambda () (loop (when (and *target* (-> *target* state)) (format 0 "TGTST st=~S x=~f z=~f~%" (-> *target* state name) (-> *target* root trans x) (-> *target* root trans z))) (suspend))))' >&3
  # confirm the probe is live, then check we are still inside the demo head (in LOGIC ticks)
  local probed=0
  for i in $(seq 1 40); do
    sleep 2; grep -qa 'TGTST st=' "$GKLOG" 2>/dev/null && { probed=1; break; }
  done
  # anchor logic frame, printed by pad_replay when the warp latched it
  local ANCHOR_F
  ANCHOR_F=$(grep -a 'ANCHOR reached at logic frame' "$GKLOG" | grep -oE 'frame [0-9]+' | grep -oE '[0-9]+' | head -1)
  if [ "$probed" != 1 ] || [ -z "${ANCHOR_F:-}" ]; then
    echo "[$LEG] FAIL: probe not live / no ANCHOR log (probed=$probed anchor='${ANCHOR_F:-}') — inconclusive" | tee -a "$R"
    exec 3>&-; kill "$GKPID" "$GCPID" 2>/dev/null; rm -f "$FIFO"; return 1
  fi
  lfc_now() {  # poll the game's logic frame via the listener; parse the newest echo
    echo '(format 0 "LFCNOW ~D~%" (-> *display* actual-frame-counter))' >&3
    sleep 3
    grep -a 'LFCNOW' "$GKLOG" | tail -1 | grep -oE '[0-9]+' | tail -1
  }
  local LNOW; LNOW=$(lfc_now); LNOW=${LNOW:-0}
  if [ $(( LNOW - ANCHOR_F )) -ge $(( HEAD_T - 60 )) ]; then
    echo "[$LEG] FAIL: probe live only at anchor+$((LNOW - ANCHOR_F)) ticks (head $HEAD_T) — inconclusive" | tee -a "$R"
    exec 3>&-; kill "$GKPID" "$GCPID" 2>/dev/null; rm -f "$FIFO"; return 1
  fi
  echo "[$LEG] probe live at anchor+$((LNOW - ANCHOR_F)) ticks — watching until anchor+$((TOTAL_T + 60)) ticks" | tee -a "$R"
  local T0=$(date +%s)
  while :; do
    kill -0 "$GKPID" 2>/dev/null || { echo "[$LEG] gk DIED mid-replay at tick $((${LNOW:-0} - ANCHOR_F)) (itself a finding)" | tee -a "$R"; break; }
    LNOW=$(lfc_now); LNOW=${LNOW:-0}
    [ $(( LNOW - ANCHOR_F )) -ge $(( TOTAL_T + 60 )) ] && break
    [ $(( $(date +%s) - T0 )) -gt 900 ] && { echo "[$LEG] WATCH TIMEOUT at tick $((LNOW - ANCHOR_F))/$TOTAL_T" | tee -a "$R"; break; }
    sleep 8
  done
  exec 3>&-; sleep 1
  kill "$GKPID" "$GCPID" 2>/dev/null; wait 2>/dev/null || true; rm -f "$FIFO"
  grep -a 'TGTST st=' "$GKLOG" > "$OUT/longjump_${LEG}_trace.txt"
  grep -a "\[JAK-HD\]" "$GKLOG" | head -6 > "$OUT/longjump_${LEG}_hdlog.txt" || true
  cp -f "$GKLOG" "$OUT/longjump_${LEG}.gk.log"
  return 0
}

analyze_leg() {  # $1 = off|on -> summary line + episode list
  local LEG="$1"
  local T="$OUT/longjump_${LEG}_trace.txt"
  awk -v leg="$LEG" '
    { st=$2; sub(/^st=/,"",st) }
    st != prev {
      if (prev == "target-wheel-flip") printf "  [%s] wheel-flip episode: %d frames -> %s\n", leg, eplen, st
      if (st == "target-wheel")      nwheel++
      if (st == "target-wheel-flip") { nflip++; eplen=0 }
      if (st == "target-hit")        nhit++
      if (st == "target-hit-ground") nhg++
      if (st ~ /^target-(duck-)?high-jump/) nhj++
      prev = st
    }
    st == "target-wheel-flip" { eplen++; if (eplen > maxep) maxep = eplen }
    END {
      printf "LEG %s: frames=%d wheel-entries=%d flip-entries=%d max-flip-len=%d high-jump-entries=%d hit-entries=%d hit-ground-entries=%d\n",
        leg, NR, nwheel, nflip, maxep, nhj, nhit, nhg
    }' "$T"
}

run_leg off || exit 1
run_leg on  || exit 1

{
  echo "=== defect-7 A/B (x86, realtime replay, same synthesized demo, OG_F1_WARP anchor) ==="
  analyze_leg off
  analyze_leg on
  echo "--- companion presence check (ON leg must have it, OFF must not) ---"
  echo "ON : $(cat "$OUT/longjump_on_hdlog.txt" 2>/dev/null | head -2)"
  echo "OFF: $(cat "$OUT/longjump_off_hdlog.txt" 2>/dev/null | head -2)"
  OFF_FLIPS=$(analyze_leg off | awk '/^LEG off/{for(i=1;i<=NF;i++) if($i ~ /^flip-entries=/){split($i,a,"=");print a[2]}}')
  ON_FLIPS=$(analyze_leg on | awk '/^LEG on/{for(i=1;i<=NF;i++) if($i ~ /^flip-entries=/){split($i,a,"=");print a[2]}}')
  OFF_MAX=$(analyze_leg off | awk '/^LEG off/{for(i=1;i<=NF;i++) if($i ~ /^max-flip-len=/){split($i,a,"=");print a[2]}}')
  ON_MAX=$(analyze_leg on | awk '/^LEG on/{for(i=1;i<=NF;i++) if($i ~ /^max-flip-len=/){split($i,a,"=");print a[2]}}')
  ON_SPAWNED=$(grep -ac 'spawned skel-bones' "$OUT/longjump_on_hdlog.txt" 2>/dev/null || echo 0)
  if [ "${OFF_FLIPS:-0}" -eq 0 ]; then echo "VERDICT: HARNESS-INCONCLUSIVE — OFF leg never reached target-wheel-flip (demo timing/runway wrong; fix the demo before concluding anything)";
  elif [ "${ON_SPAWNED:-0}" -eq 0 ]; then echo "VERDICT: HARNESS-INCONCLUSIVE — ON leg companion never spawned (toggle did not take)";
  elif [ "${ON_FLIPS:-0}" -lt "${OFF_FLIPS:-0}" ] || [ $(( ${ON_MAX:-0} * 2 )) -lt "${OFF_MAX:-0}" ]; then echo "VERDICT: REPRODUCED — ON leg loses or truncates wheel-flips vs OFF (defect 7 exists on x86)";
  else echo "VERDICT: NOT-REPRODUCED-X86 — ON == OFF on identical input; suspicion moves to device-only factors (perf, touch overlay)"; fi
} | tee -a "$R"
