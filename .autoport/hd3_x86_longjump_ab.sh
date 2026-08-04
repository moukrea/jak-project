#!/usr/bin/env bash
# hd3_x86_longjump_ab.sh — defect-7 (long jump broken with HD toggle ON) x86 A/B repro.
# Same synthesized pad_replay demo (3x roll+X long-jump combos, see hd3_gen_longjump_inputs.py)
# replayed twice: enhanced-models OFF then ON. OG_PAD_REPLAY_REALTIME=1 keeps the real-time
# clock (the DEFAULT replay forces a fixed timestep, which would neutralize the suspected
# timing mechanism: frame hitches feeding target-wheel-flip's stuck/smack detector,
# target.gc:1857-1863). Per-frame probe dumps *target*'s state name + position; the verdict
# compares the two state traces: defect REPRODUCED if OFF completes wheel-flips but ON
# truncates them / snaps into target-hit.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
GK=build/game/gk; GOALC=build/goalc/goalc; ISO=out/jak1/iso
export DISPLAY="${DISPLAY:-:0}" XAUTHORITY="${XAUTHORITY:-/run/user/1000/.mutter-Xwaylandauth.RKSTQ3}"
export SDL_VIDEODRIVER=x11 LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
OUT=.autoport/reports/Grecharged-hd-models3; mkdir -p "$OUT"
R="$OUT/longjump_ab_x86.txt"; : > "$R"
INPUTS=/tmp/hd3_longjump.inputs
WATCH="${WATCH:-120}"

[ "$ISO/GAME.CGO" -nt goal_src/jak1/pc/jak-hd.gc ] || { echo "FAIL: GAME.CGO stale vs jak-hd.gc — run (mi) first" | tee -a "$R"; exit 1; }
python3 .autoport/hd3_gen_longjump_inputs.py "$INPUTS" | tee -a "$R"
mkdir -p out/jak1/obj && cp -f recharged_assets/hd_anim/jak-hd-ag.go out/jak1/obj/jak-hd-ag.go

run_leg() {  # $1 = off|on
  local LEG="$1" TOGGLE GKLOG GCLOG FIFO GKPID GCPID
  [ "$LEG" = on ] && TOGGLE='#t' || TOGGLE='#f'
  GKLOG="$OUT/.lj_${LEG}_gk.log"; GCLOG="$OUT/.lj_${LEG}_gc.log"; : > "$GKLOG"; : > "$GCLOG"
  FIFO="$(mktemp -u)"; mkfifo "$FIFO"
  OG_PAD_REPLAY_REPLAY="$INPUTS" OG_PAD_REPLAY_REALTIME=1 \
    "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data "$ISO" -- -boot -debug-mem > "$GKLOG" 2>&1 &
  GKPID=$!
  local booted=0
  for i in $(seq 1 150); do
    kill -0 "$GKPID" 2>/dev/null || { echo "[$LEG] FAIL: gk exited during boot" | tee -a "$R"; rm -f "$FIFO"; return 1; }
    grep -aqE "link finish: default-menu($|-pc)" "$GKLOG" 2>/dev/null && { booted=1; break; }
    grep -aqE "link finish: logo($|-)" "$GKLOG" 2>/dev/null && [ "$i" -ge 30 ] && { booted=1; break; }
    sleep 1
  done
  [ "$booted" = 1 ] || { echo "[$LEG] FAIL: boot timeout" | tee -a "$R"; kill "$GKPID" 2>/dev/null; rm -f "$FIFO"; return 1; }
  sleep 4
  timeout $((WATCH+700)) "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" < "$FIFO" > "$GCLOG" 2>&1 &
  GCPID=$!; exec 3>"$FIFO"
  echo '(lt)' >&3; sleep 5
  echo '(build-game)' >&3
  for i in $(seq 1 240); do sleep 1; grep -aqiE "Successfully built all|Build Successful" "$GCLOG" 2>/dev/null && break; done
  sleep 3
  echo "(set! (-> *pc-settings* recharged-enhanced-models?) $TOGGLE)" >&3
  # probe BEFORE target spawns so frame 0 of the replay is covered
  echo '(process-spawn-function process (lambda () (loop (when (and *target* (-> *target* state)) (format 0 "TGTST st=~S x=~f z=~f~%" (-> *target* state name) (-> *target* root trans x) (-> *target* root trans z))) (suspend))))' >&3
  sleep 2
  echo "(start (quote play) (get-continue-by-name *game-info* \"game-start\"))" >&3
  local tgtok=0
  for i in $(seq 1 45); do
    echo '(when *target* (format 0 "TGT-READY~%"))' >&3; sleep 2
    grep -qa TGT-READY "$GKLOG" 2>/dev/null && { tgtok=1; break; }
  done
  [ "$tgtok" = 1 ] || { echo "[$LEG] FAIL: *target* never spawned" | tee -a "$R"; exec 3>&-; kill "$GKPID" "$GCPID" 2>/dev/null; rm -f "$FIFO"; return 1; }
  # demo = ~29s post-anchor; watch the full window
  local t0=$(date +%s)
  while [ $(( $(date +%s) - t0 )) -lt "$WATCH" ]; do
    kill -0 "$GKPID" 2>/dev/null || { echo "[$LEG] gk DIED mid-replay at $(( $(date +%s) - t0 ))s (itself a finding)" | tee -a "$R"; break; }
    sleep 5
  done
  exec 3>&-; sleep 1
  kill "$GKPID" "$GCPID" 2>/dev/null; wait 2>/dev/null || true; rm -f "$FIFO"
  grep -a 'TGTST st=' "$GKLOG" > "$OUT/longjump_${LEG}_trace.txt"
  grep -a "\[JAK-HD\]" "$GKLOG" | head -4 > "$OUT/longjump_${LEG}_hdlog.txt" || true
  cp -f "$GKLOG" "$OUT/longjump_${LEG}.gk.log"
  return 0
}

analyze_leg() {  # $1 = off|on -> summary line + episode list
  local LEG="$1" T="$OUT/longjump_${LEG}_trace.txt"
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
  echo "=== defect-7 A/B (x86, realtime replay, same synthesized demo) ==="
  analyze_leg off
  analyze_leg on
  echo "--- companion presence check (ON leg must have it, OFF must not) ---"
  echo "ON : $(cat "$OUT/longjump_on_hdlog.txt" 2>/dev/null | head -2)"
  echo "OFF: $(cat "$OUT/longjump_off_hdlog.txt" 2>/dev/null | head -2)"
  OFF_FLIPS=$(awk '/^LEG off/{for(i=1;i<=NF;i++) if($i ~ /^flip-entries=/){split($i,a,"=");print a[2]}}' <(analyze_leg off))
  ON_FLIPS=$(awk '/^LEG on/{for(i=1;i<=NF;i++) if($i ~ /^flip-entries=/){split($i,a,"=");print a[2]}}' <(analyze_leg on))
  OFF_MAX=$(awk '/^LEG off/{for(i=1;i<=NF;i++) if($i ~ /^max-flip-len=/){split($i,a,"=");print a[2]}}' <(analyze_leg off))
  ON_MAX=$(awk '/^LEG on/{for(i=1;i<=NF;i++) if($i ~ /^max-flip-len=/){split($i,a,"=");print a[2]}}' <(analyze_leg on))
  if [ "${OFF_FLIPS:-0}" -eq 0 ]; then echo "VERDICT: HARNESS-INCONCLUSIVE — OFF leg never reached target-wheel-flip (demo timing/runway wrong; fix the demo before concluding anything)";
  elif [ "${ON_FLIPS:-0}" -lt "${OFF_FLIPS:-0}" ] || [ $(( ${ON_MAX:-0} * 2 )) -lt "${OFF_MAX:-0}" ]; then echo "VERDICT: REPRODUCED — ON leg loses or truncates wheel-flips vs OFF (defect 7 exists on x86)";
  else echo "VERDICT: NOT-REPRODUCED-X86 — ON == OFF on identical input; suspicion moves to device-only factors (perf, touch overlay)"; fi
} | tee -a "$R"
