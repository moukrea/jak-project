#!/usr/bin/env bash
# hd3_x86_movie_check.sh — defect-6 (cutscene HD ghost) x86 MECHANISM gate.
# Cutscenes hide Jak via (draw-status hidden) on *target*; the defect-6 fix makes the jak-hd
# companion mirror that bit each frame (hidden gates dma-add-process-drawable, so a mirrored
# companion cannot submit a ghost pose). Real scenes are hard to trigger deterministically from
# the listener AND the intro movie has no *target* (companion never spawns there) — so this
# gate tests the MIRROR MECHANISM directly in gameplay: spawn a setter process that forces the
# hidden bit on *target* for ~90 frames then clears it, and require the companion's hidden bit
# to track it both ways (<=2 transition-lag frames tolerated). The REAL-scene proof stays a
# device obligation (intro + a sage cutscene). Template: hd_x86_mercdiag.sh + gcine_cut_capture.sh.
# PRE-REQ: out/jak1/iso is FRESH vs goal_src/jak1/pc/jak-hd.gc ((mi) done — gated below).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
GK=build/game/gk; GOALC=build/goalc/goalc; ISO=out/jak1/iso
export DISPLAY="${DISPLAY:-:0}" XAUTHORITY="${XAUTHORITY:-/run/user/1000/.mutter-Xwaylandauth.RKSTQ3}"
export SDL_VIDEODRIVER=x11 LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
OUT=.autoport/reports/Grecharged-hd-models3; mkdir -p "$OUT"
R="$OUT/movie_check_x86.txt"; : > "$R"
GKLOG="$OUT/.mv_gk.log"; GCLOG="$OUT/.mv_gc.log"; FIFO="$(mktemp -u)"; mkfifo "$FIFO"
: > "$GKLOG"; : > "$GCLOG"
WATCH="${WATCH:-180}"

[ "$ISO/GAME.CGO" -nt goal_src/jak1/pc/jak-hd.gc ] || { echo "FAIL: GAME.CGO stale vs jak-hd.gc — run (mi) first" | tee -a "$R"; exit 1; }
# loado under -fakeiso opens out/jak1/obj/<name>-ag.go (same dir Loader.cpp stages into on
# device) — NOT $ISO. (mi) repopulates obj/ without it, so stage on every run. Proven by the
# 02:33 run: staging only $ISO -> sceOpen(out/jak1/obj/jak-hd-ag.go) failed -> no companion.
mkdir -p out/jak1/obj
cp -f recharged_assets/hd_anim/jak-hd-ag.go out/jak1/obj/jak-hd-ag.go || { echo "FAIL: cannot stage jak-hd-ag.go" | tee -a "$R"; exit 1; }
cp -f recharged_assets/hd_anim/jak-hd-ag.go "$ISO/jak-hd-ag.go" 2>/dev/null

"$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data "$ISO" -- -boot -debug-mem > "$GKLOG" 2>&1 &
GKPID=$!
cleanup(){ exec 3>&- 2>/dev/null||true; kill "$GKPID" "${GCPID:-0}" 2>/dev/null||true; wait 2>/dev/null||true; rm -f "$FIFO"; }
trap cleanup EXIT
booted=0
for i in $(seq 1 150); do
  kill -0 "$GKPID" 2>/dev/null || { echo "FAIL: gk exited during boot" | tee -a "$R"; tail -20 "$GKLOG" >> "$R"; exit 1; }
  grep -aqE "link finish: default-menu($|-pc)" "$GKLOG" 2>/dev/null && { booted=1; break; }
  grep -aqE "link finish: logo($|-)" "$GKLOG" 2>/dev/null && [ "$i" -ge 30 ] && { booted=1; break; }
  sleep 1
done
[ "$booted" = 1 ] || { echo "FAIL: boot timeout" | tee -a "$R"; tail -20 "$GKLOG" >> "$R"; exit 1; }
sleep 4

timeout $((WATCH+700)) "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" < "$FIFO" > "$GCLOG" 2>&1 &
GCPID=$!; exec 3>"$FIFO"
echo '(lt)' >&3; sleep 5
echo '(build-game)' >&3
built=0
for i in $(seq 1 240); do
  sleep 1
  grep -aqiE "Successfully built all|Build Successful" "$GCLOG" 2>/dev/null && { built=1; break; }
  kill -0 "$GKPID" 2>/dev/null || { echo "FAIL: gk died during build-game" | tee -a "$R"; exit 1; }
done
[ "$built" = 1 ] || echo "WARN: build-game marker not seen" | tee -a "$R"
sleep 4

echo '(set! (-> *pc-settings* recharged-enhanced-models?) #t)' >&3
echo "(start (quote play) (get-continue-by-name *game-info* \"game-start\"))" >&3
# wait for the player
tgtok=0
for i in $(seq 1 45); do
  echo '(when *target* (format 0 "TGT-READY~%"))' >&3; sleep 2
  grep -qa TGT-READY "$GKLOG" 2>/dev/null && { tgtok=1; break; }
done
[ "$tgtok" = 1 ] || { echo "FAIL: *target* never spawned" | tee -a "$R"; exit 1; }
sleep 8   # give maybe-spawn-jak-hd! time to spawn the companion

# per-frame probe: target existence + hidden bit, companion aliveness + hidden bit.
# th/ch: 1 = (draw-status hidden) set. ca: companion alive. tp: *target* non-#f.
PROBE="(process-spawn-function process (lambda () (loop (format 0 \"MVHD f=~D tp=~D th=~D ca=~D ch=~D~%\" (current-time) (if *target* 1 0) (if (and *target* (logtest? (-> *target* draw status) (draw-status hidden))) 1 0) (if (and *jak-hd-process* (nonzero? (-> *jak-hd-process* 0))) 1 0) (if (and *jak-hd-process* (nonzero? (-> *jak-hd-process* 0)) (logtest? (-> (the-as jak-hd (-> *jak-hd-process* 0)) draw status) (draw-status hidden))) 1 0)) (suspend))))"
echo "$PROBE" >&3
sleep 2
echo "$PROBE" >&3
sleep 6   # baseline frames with th=0 before the forced window

# the setter: force hidden on *target* for 90 frames (re-set EVERY frame in case target
# logic clears it), then clear it and exit. This emulates what movie code does to hide Jak.
SETTER="(process-spawn-function process (lambda () (dotimes (i 90) (when *target* (logior! (-> *target* draw status) (draw-status hidden))) (suspend)) (when *target* (logclear! (-> *target* draw status) (draw-status hidden))) (format 0 \"MVHD-SETTER-DONE~%\")))"
echo "$SETTER" >&3

t0=$(date +%s)
while [ $(( $(date +%s) - t0 )) -lt "$WATCH" ]; do
  kill -0 "$GKPID" 2>/dev/null || { echo "gk exited at $(( $(date +%s) - t0 ))s" | tee -a "$R"; break; }
  grep -qa 'MVHD-SETTER-DONE' "$GKLOG" 2>/dev/null && { sleep 6; break; }
  sleep 5
done
exec 3>&-; sleep 2

# dedupe identical probe lines: the PROBE is sent twice (listener-drop insurance), so every
# frame logs twice and all counters double — the 02:40 run saturated the <=2 lag tolerance
# with a real lag of 1. awk-dedupe keeps order (sort -u would reorder frames).
grep -a 'MVHD f=' "$GKLOG" | awk '!seen[$0]++' > "$OUT/movie_check_frames.txt" || true
# NOTE: never `grep -c ... || echo 0` — grep already prints 0 on no-match (exit 1), the
# fallback then appends a second 0 -> "0\n0" breaks [ -lt ] (proven 02:33 run).
TOTAL=$(grep -ac 'MVHD f=' "$OUT/movie_check_frames.txt" 2>/dev/null); TOTAL=${TOTAL:-0}
TGT_HID=$(grep -ac 'th=1' "$OUT/movie_check_frames.txt" 2>/dev/null); TGT_HID=${TGT_HID:-0}
CO_ALIVE=$(grep -ac 'ca=1' "$OUT/movie_check_frames.txt" 2>/dev/null); CO_ALIVE=${CO_ALIVE:-0}
# violation A = target hidden, companion alive but NOT hidden (the ghost)
VIOL_A=$(grep -a 'th=1' "$OUT/movie_check_frames.txt" 2>/dev/null | grep 'ca=1' | grep -c 'ch=0'); VIOL_A=${VIOL_A:-0}
# violation B = target visible, companion alive but STUCK hidden (post-clear)
VIOL_B=$(grep -a 'tp=1 th=0' "$OUT/movie_check_frames.txt" 2>/dev/null | grep 'ca=1' | grep -c 'ch=1'); VIOL_B=${VIOL_B:-0}
{
  echo "MOVIE-CHECK x86 (forced-hidden window, enhanced ON) frames=$TOTAL tgt-hidden=$TGT_HID companion-alive=$CO_ALIVE ghost-violations=$VIOL_A stuck-hidden=$VIOL_B"
  echo "spawn log: $(grep -a '\[JAK-HD\] spawned' "$GKLOG" | tail -1)"
  if [ "$TOTAL" -lt 100 ] || [ "$CO_ALIVE" -lt 50 ]; then echo "RESULT: INCONCLUSIVE (frames=$TOTAL companion-alive=$CO_ALIVE — companion or probe missing)";
  elif [ "$TGT_HID" -lt 60 ]; then echo "RESULT: INCONCLUSIVE (forced-hidden window too short: $TGT_HID frames — target logic may clear the bit; check setter)";
  elif [ "$VIOL_A" -le 2 ] && [ "$VIOL_B" -le 2 ]; then echo "RESULT: PASS — companion mirrors the hidden bit both ways (<=2 transition-lag frames)";
  else echo "RESULT: FAIL — ghost-violations=$VIOL_A stuck-hidden=$VIOL_B"; fi
} | tee -a "$R"
cp -f "$GKLOG" "$OUT/movie_check.gk.log"; cp -f "$GCLOG" "$OUT/movie_check.goalc.log"
grep -q 'RESULT: PASS' "$R"
