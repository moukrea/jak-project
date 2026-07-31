#!/usr/bin/env bash
# gmb_v25_x86_proof.sh — Grecharged-mesh-browser V2.5 DESKTOP proof (device is with the owner):
# marks RESUME across an app restart. Flow:
#   RUN 1: browser open (set-active 1 + pick-levels, the exact chain the GOAL open path drives),
#          target row 2156, mark TWO beach polygons via the hover channel -> active(13) and
#          renderer-drawn(14) counters reach 2, mesh_marks.jsonl has 2 lines. KILL the app.
#   SEED : append one CORRUPT line and one valid OTHER-LEVEL ("beach") line to the file.
#   RUN 2 (relaunch = new gk process): browser open again -> the C++ reload must rebuild the
#          store from the file: 13==2 and renderer 14==2 (corrupt line ignored without crash,
#          beach line NOT loaded but PRESERVED), 16==0 (store not full). Re-aim mark #1's ray:
#          hover returns the SAME triangle ordinal; pc-mb-mark-poly! now UNMARKS the RELOADED
#          mark -> 13/14 drop to 1 AND exactly that line leaves the JSONL (others byte-identical).
# REPL notes (v2.4 lessons): fresh goalc knows no project types — drive pc-mb-hover-ray! as
# (pointer float) with (new 'static 'array float 4 ...). target-set! takes (row SLOT).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
OUT=/tmp/gmbv25
rm -rf "$OUT"; mkdir -p "$OUT"
GK=build-mbrowse/game/gk
[ -x "$GK" ] || { echo "no $GK"; exit 1; }
XAUTH="$(ls /run/user/1000/.mutter-Xwaylandauth* 2>/dev/null | head -1)"
MARKS_CANDIDATES=("mesh_marks.jsonl" "build-mbrowse/game/mesh_marks.jsonl")

GKPID=""; GCPID=""; FIFO=""; RLOG=""
cleanup() { [ -n "$GCPID" ] && kill "$GCPID" 2>/dev/null; pkill -f "$GK" 2>/dev/null; sleep 1; }
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

start_repl() { # $1=tag — the set-active/pick-levels pair IS the browser-open chain the GOAL
               # open path drives (mesh-browser-open -> pc-mb-set-active! 1 ->
               # mesh-browser-freecam-refresh-levels -> pc-mb-pick-levels!)
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

stop_repl() { exec 9>&- 2>/dev/null || true; [ -n "$GCPID" ] && kill "$GCPID" 2>/dev/null; GCPID=""; }

geti(){ # $1=label $2=field
  echo "READ $1 field=$2"
  say "(pc-mb-rt-geti $2)" 2
  LASTVAL=$(grep -aE '^-?[0-9]+[[:space:]]+#x' "$RLOG" | tail -1 | awk '{print $1}')
  echo "VALUE $1 = ${LASTVAL:-parse-miss}"
}

find_marks() {
  for f in "${MARKS_CANDIDATES[@]}"; do [ -f "$f" ] && { echo "$f"; return; }; done
  find . build-mbrowse -maxdepth 3 -name mesh_marks.jsonl 2>/dev/null | head -1
}

aim_and_prepare() { # target + gizmos + hover ray defs (same rays/rows as the v2.4 battery)
  say "(pc-mb-target-set! 2156 0)" 3
  say "(pc-mb-gizmos-set! 1)" 10
  say "(define mb-dir (new 'static 'array float 4 0.0 -1.0 0.0 0.0))" 2
  say "(define mb-o1 (new 'static 'array float 4 40960.0 61440.0 -102400.0 1.0))" 2
  say "(define mb-o2 (new 'static 'array float 4 81920.0 61440.0 -102400.0 1.0))" 2
}

echo "==================== RUN 1: mark two polygons, then KILL the app ===================="
for f in "${MARKS_CANDIDATES[@]}"; do rm -f "$f"; done
boot_gk "10 3 -25" "R1"
start_repl "R1"
aim_and_prepare
say "(pc-mb-hover-ray! mb-o1 mb-dir 1)" 3
geti "r1_hover1" 12; TRI1=$LASTVAL
echo "MARK 1"; say "(pc-mb-mark-poly!)" 2
geti "r1_marks_after1" 13; geti "r1_drawn_after1" 14
say "(pc-mb-hover-ray! mb-o2 mb-dir 1)" 3
geti "r1_hover2" 12; TRI2=$LASTVAL
echo "MARK 2"; say "(pc-mb-mark-poly!)" 2
geti "r1_marks_after2" 13; geti "r1_drawn_after2" 14
MF=$(find_marks)
echo "MARKS FILE: ${MF:-NOT-FOUND}  TRI1=$TRI1 TRI2=$TRI2"
[ -n "$MF" ] || { echo "FAIL: no marks file after run 1"; exit 1; }
cp "$MF" "$OUT/marks_run1.jsonl"; wc -l "$OUT/marks_run1.jsonl"
stop_repl
echo "---- KILL the app (this is the restart the owner performs) ----"
pkill -f "$GK" 2>/dev/null; sleep 3

echo "==================== SEED: corrupt line + other-level line ===================="
# corrupt village1 line (unparsable row) — must be IGNORED without a crash
echo '{"game":"jak1","level":"village1","system":"TFRAG","row":BROKEN,"tri":garbage-not-json' >> "$MF"
# valid line for ANOTHER level — must NOT be loaded for village1 but must SURVIVE untouched
echo '{"game":"jak1","level":"beach","system":"TFRAG","row":42,"shell":7,"material":"bea-sand","tex_id":123,"tri":99,"v0_m":[1.0000,2.0000,3.0000],"v1_m":[2.0000,2.0000,3.0000],"v2_m":[1.0000,2.0000,4.0000],"face_normal":[0.000000,1.000000,0.000000],"offline_verdict":{"graded":1,"a_sign_x100":100,"b_disp_x100":0},"centroid_m":[1.3000,2.0000,3.3000],"aabb_m":[[1.0000,2.0000,3.0000],[2.0000,2.0000,4.0000]]}' >> "$MF"
cp "$MF" "$OUT/marks_seeded.jsonl"; wc -l "$OUT/marks_seeded.jsonl"

echo "==================== RUN 2: RELAUNCH, reopen browser -> marks must RELOAD ===================="
boot_gk "10 3 -25" "R2"
start_repl "R2"   # set-active 1 + pick-levels village1 = the reload trigger chain
sleep 3
geti "r2_active_marks_after_reload" 13
geti "r2_drawn_after_reload" 14
geti "r2_skipped_store_full" 16
echo "---- unmark a RELOADED mark: re-aim ray 1, toggle ----"
aim_and_prepare
say "(pc-mb-hover-ray! mb-o1 mb-dir 1)" 3
geti "r2_hover1" 12; TRI1B=$LASTVAL
echo "UNMARK RELOADED"; say "(pc-mb-mark-poly!)" 2
geti "r2_marks_after_unmark" 13; geti "r2_drawn_after_unmark" 14
cp "$MF" "$OUT/marks_after_unmark.jsonl"; wc -l "$OUT/marks_after_unmark.jsonl"
stop_repl
pkill -f "$GK" 2>/dev/null; sleep 2

echo "==================== FILE FORENSICS ===================="
echo "TRI1=$TRI1 TRI2=$TRI2 TRI1B(hover after reload)=$TRI1B"
echo "-- run1 file:";          cat "$OUT/marks_run1.jsonl" | cut -c1-160
echo "-- seeded file:";        cat "$OUT/marks_seeded.jsonl" | cut -c1-160
echo "-- after unmark:";       cat "$OUT/marks_after_unmark.jsonl" | cut -c1-160
echo "-- removed line must be tri $TRI1:"
grep -c "\"tri\":$TRI1," "$OUT/marks_seeded.jsonl" || true
grep -c "\"tri\":$TRI1," "$OUT/marks_after_unmark.jsonl" || true
echo "-- beach + corrupt lines must survive byte-identical:"
grep -F '"level":"beach"' "$OUT/marks_after_unmark.jsonl" >/dev/null && echo "BEACH-LINE-SURVIVES"
grep -F 'garbage-not-json' "$OUT/marks_after_unmark.jsonl" >/dev/null && echo "CORRUPT-LINE-SURVIVES"
echo "==================== RLOG DUMPS ===================="
for t in R1 R2; do echo "-------- goalc-$t.log:"; grep -aE '^-?[0-9]+[[:space:]]+#x|Error|error' "$OUT/goalc-$t.log" | tail -60; done
echo "ALL DONE"
