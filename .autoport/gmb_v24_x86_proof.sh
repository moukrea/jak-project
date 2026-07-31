#!/usr/bin/env bash
# gmb_v24_x86_proof.sh — Grecharged-mesh-browser V2.4 DESKTOP proofs (device is with the owner):
#   A. MARKED-polygon persistence: mark 3 polygons via the hover channel -> active count (13) and
#      renderer per-frame drawn counter (14) grow 1,2,3; gizmos OFF -> wire(11)==0 while marked(14)
#      stays 3 (highlight independent of the Circle toggle); re-aim polygon 1 and mark again ->
#      UNMARK: 13 and 14 drop to 2 and the polygon's line leaves mesh_marks.jsonl (3 -> 2 lines).
#   B. OCCLUSION: the gizmo pass depth-tests (LEQUAL) against the scene depth buffer inside a
#      GL_SAMPLES_PASSED query -> counter 15. Same target (fireplace rim, TIE row 2735) probed
#      along the fixed camera facing (-Z per census A: campos NE of Jak, looking mostly -Z) from
#      4 distances: close/clear first, then with the hut wall interposed. Clear -> large sample
#      count; interposed -> collapsed count, census (-M in-frustum) proving arrows still face
#      the camera.
# REPL notes (run 1 lessons): a FRESH goalc REPL knows no project types — 'vector' fails to
# compile. Drive pc-mb-hover-ray! as (pointer float) with (new 'static 'array float 4 ...).
# pc-mb-target-set! takes (row SLOT), slot 0 = first pick level, NOT the system.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
OUT=/tmp/gmbv24
mkdir -p "$OUT"
GK=build-mbrowse/game/gk
[ -x "$GK" ] || { echo "no $GK"; exit 1; }
XAUTH="$(ls /run/user/1000/.mutter-Xwaylandauth* 2>/dev/null | head -1)"
MARKS_CANDIDATES=("mesh_marks.jsonl" "build-mbrowse/game/mesh_marks.jsonl")

GKPID=""
GCPID=""
FIFO=""
RLOG=""

cleanup() {
  [ -n "$GCPID" ] && kill "$GCPID" 2>/dev/null
  pkill -f "$GK" 2>/dev/null
  sleep 1
}
trap cleanup EXIT

boot_gk() { # $1=POS meters "x y z"  $2=tag
  local pos="$1" tag="$2"
  pkill -f "$GK" 2>/dev/null; sleep 2
  GKLOG=$OUT/gk-$tag.log
  DISPLAY="${DISPLAY:-:0}" XAUTHORITY="$XAUTH" LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
  OG_LEVEL_WARP=village1-hut OG_LEVEL_WARP_POS="$pos" \
  stdbuf -oL -eL "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi \
    -- -boot -debug-mem > "$GKLOG" 2>&1 &
  GKPID=$!
  local t=0
  until grep -qa "LEVEL-WARP-SPAWN" "$GKLOG"; do
    sleep 3; t=$((t+3))
    kill -0 $GKPID 2>/dev/null || { echo "[$tag] gk died during boot"; tail -20 "$GKLOG"; exit 1; }
    [ $t -ge 300 ] && { echo "[$tag] no warp after ${t}s"; exit 1; }
  done
  sleep 25
}

say(){ printf '%s\n' "$1" >&9; sleep "${2:-1.5}"; }

start_repl() { # $1=tag
  RLOG=$OUT/goalc-$1.log
  FIFO=$OUT/repl-$1.fifo
  rm -f "$FIFO"; mkfifo "$FIFO"
  ( build/goalc/goalc --game jak1 --proj-path . < "$FIFO" > "$RLOG" 2>&1 ) &
  GCPID=$!
  exec 9>"$FIFO"
  say "(lt)" 6
  say "(define-extern pc-mb-set-active! (function int none))" 1
  say "(define-extern pc-mb-pick-levels! (function string string none))" 1
  say "(define-extern pc-mb-target-set! (function int int none))" 1
  say "(define-extern pc-mb-gizmos-set! (function int none))" 1
  say "(define-extern pc-mb-hover-ray! (function (pointer float) (pointer float) int none))" 1
  say "(define-extern pc-mb-mark-poly! (function int))" 1
  say "(define-extern pc-mb-rt-geti (function int int))" 1
  say "(pc-mb-set-active! 1)" 1
  say "(pc-mb-pick-levels! \"village1\" \"\")" 2
}

stop_repl() {
  exec 9>&- 2>/dev/null || true
  [ -n "$GCPID" ] && kill "$GCPID" 2>/dev/null
  GCPID=""
}

geti(){ # $1=label $2=field — value lands in RLOG; we also parse the LAST int echo for branching
  echo "READ $1 field=$2"
  say "(pc-mb-rt-geti $2)" 2
  LASTVAL=$(grep -aE '^-?[0-9]+[[:space:]]+#x' "$RLOG" | tail -1 | awk '{print $1}')
  echo "VALUE $1 = ${LASTVAL:-parse-miss}"
}

find_marks() {
  for f in "${MARKS_CANDIDATES[@]}"; do [ -f "$f" ] && { echo "$f"; return; }; done
  find . build-mbrowse -maxdepth 3 -name mesh_marks.jsonl 2>/dev/null | head -1
}

echo "==================== PHASE A: marks persistence + unmark (vantage 10 3 -25, row 2156) ===="
for f in "${MARKS_CANDIDATES[@]}"; do rm -f "$f"; done
boot_gk "10 3 -25" "A"
start_repl "A"
say "(pc-mb-target-set! 2156 0)" 3
say "(pc-mb-gizmos-set! 1)" 10
# hover rays: straight down onto the beach from 15 m up, three spots ~10-15 m apart (GOAL units)
say "(define mb-dir (new 'static 'array float 4 0.0 -1.0 0.0 0.0))" 2
say "(define mb-o1 (new 'static 'array float 4 40960.0 61440.0 -102400.0 1.0))" 2
say "(define mb-o2 (new 'static 'array float 4 81920.0 61440.0 -102400.0 1.0))" 2
say "(define mb-o3 (new 'static 'array float 4 40960.0 61440.0 -143360.0 1.0))" 2

say "(pc-mb-hover-ray! mb-o1 mb-dir 1)" 3
geti "hover1" 12
echo "MARK 1"; say "(pc-mb-mark-poly!)" 2
geti "marks_after1" 13; geti "marked_drawn_after1" 14

say "(pc-mb-hover-ray! mb-o2 mb-dir 1)" 3
geti "hover2" 12
echo "MARK 2"; say "(pc-mb-mark-poly!)" 2
geti "marks_after2" 13; geti "marked_drawn_after2" 14

say "(pc-mb-hover-ray! mb-o3 mb-dir 1)" 3
geti "hover3" 12
echo "MARK 3"; say "(pc-mb-mark-poly!)" 2
geti "marks_after3" 13; geti "marked_drawn_after3" 14

MF=$(find_marks)
echo "MARKS FILE: ${MF:-NOT-FOUND}"
[ -n "$MF" ] && cp "$MF" "$OUT/mesh_marks_3.jsonl" && wc -l "$OUT/mesh_marks_3.jsonl"

echo "---- gizmos OFF: wire must hit 0 while marked stays 3 (independence) ----"
say "(pc-mb-gizmos-set! 0)" 4
geti "wire_gizmoff" 11; geti "marked_gizmoff" 14; geti "prims_gizmoff" 6

echo "---- gizmos back ON, re-aim spot 1, mark again = UNMARK ----"
say "(pc-mb-gizmos-set! 1)" 5
say "(pc-mb-hover-ray! mb-o1 mb-dir 1)" 3
geti "hover1_again" 12
echo "UNMARK"; say "(pc-mb-mark-poly!)" 2
geti "marks_after_unmark" 13; geti "marked_drawn_after_unmark" 14
[ -n "$MF" ] && cp "$MF" "$OUT/mesh_marks_2.jsonl" && wc -l "$OUT/mesh_marks_2.jsonl"

echo "---- occlusion CLEAR baseline on row 2156 from this vantage ----"
for i in 1 2 3 4 5; do geti "occ_clear_$i" 15; done
geti "prims_clear" 6; geti "px_clear" 10; geti "faces_clear" 3
stop_repl
grep -a "census in-frustum" "$OUT/gk-A.log" | tail -2 > "$OUT/census-A.txt"; cat "$OUT/census-A.txt"
pkill -f "$GK" 2>/dev/null; sleep 2

probe_occ() { # $1=POS $2=row $3=tag  (slot is always 0 = village1)
  echo "==================== OCC PROBE $3: vantage($1) row=$2 slot=0 ===="
  boot_gk "$1" "$3"
  start_repl "$3"
  say "(pc-mb-target-set! $2 0)" 3
  say "(pc-mb-gizmos-set! 1)" 12
  for i in 1 2 3 4 5; do geti "occ_$3_$i" 15; done
  geti "prims_$3" 6; geti "px_$3" 10; geti "faces_$3" 3
  stop_repl
  grep -a "census in-frustum\|built .* normal arrows" "$OUT/gk-$3.log" | tail -3 > "$OUT/census-$3.txt"
  cat "$OUT/census-$3.txt"
  pkill -f "$GK" 2>/dev/null; sleep 2
}

# SAME-VANTAGE clear/occluded battery (the decisive V2.4 occlusion instrument). ONE boot at the
# D2 warp — its campos (-86.7,15.6,89.5) and facing were measured in run 3 and every candidate
# ray below is CPU-verified from that exact point (mb_pick_ref over the full level geometry,
# /tmp/gmbv24/rays_d2.txt):
#   row 2747 vil-bench-wood  d=32.7 m — OCCLUDED (first hit row 9417 at 16.3 m, a hut wall)
#   row 4255 vil-plankwood   d=15.4 m — CLEAR    (first hit IS row 4255)
#   row  108 vil-hut-roof    d=36.4 m — OCCLUDED (first hit row 608, the near roof, at 11.4 m)
#   row  611 vil-hut-roof    d=12.9 m — CLEAR    (first hit IS row 611)
# Same boot, same camera => "meme vantage": only the interposed geometry differs per target.
# The census log re-measures campos + in-frustum arrow verts per rebuild for post-hoc checks.
echo "==================== PHASE E: same-vantage occlusion battery (warp -79.5 13 75.1) ===="
boot_gk "-79.5 13 75.1" "E"
start_repl "E"
probe_row() { # $1=row $2=tag
  say "(pc-mb-gizmos-set! 0)" 2
  say "(pc-mb-target-set! $1 0)" 3
  say "(pc-mb-gizmos-set! 1)" 12
  for i in 1 2 3; do geti "occ_$2_$i" 15; done
  geti "prims_$2" 6; geti "px_$2" 10; geti "faces_$2" 3
}
probe_row 2747 "E_bench_occl"
probe_row 4255 "E_plank_clear"
probe_row 108  "E_roof_occl"
probe_row 611  "E_roof_clear"
stop_repl
grep -a "census in-frustum\|built .* normal arrows" "$OUT/gk-E.log" > "$OUT/census-E.txt"
cat "$OUT/census-E.txt"
pkill -f "$GK" 2>/dev/null; sleep 2

echo "==================== RLOG DUMPS (positional cross-check) ===="
for t in A E; do echo "-------- goalc-$t.log:"; grep -aE '^-?[0-9]+[[:space:]]+#x|Error|error' "$OUT/goalc-$t.log" | tail -100; done
echo "ALL DONE"
