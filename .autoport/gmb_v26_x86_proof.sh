#!/usr/bin/env bash
# gmb_v26_x86_proof.sh — Grecharged-mesh-browser V2.6 DESKTOP proof: NO 256-mark cap.
# Owner hit MB_MARKS_MAX=256 (silent refusal). The store is now a std::vector (MB_MARKS_MAX
# removed; 1M sanity bound only, announced on screen via the STORE FULL line) and the highlight
# renderer batches ALL marks in one VBO rebuilt only when the store changes. Flow:
#   SEED : write 1099 valid village1 JSONL marks (distinct tris, small triangles near the warp).
#   RUN 1: browser open (set-active 1 + pick-levels) -> reload: active(13)==drawn(14)==1099,
#          skipped(16)==0 (no false STORE FULL). Mark TWO real beach polygons via the hover
#          channel -> 1100 then 1101: marks #1100/#1101 ACCEPTED, far beyond the old 256 cap.
#          KILL the app.
#   RUN 2 (relaunch = new gk process): reload -> 13==14==1101 (resume with the same count).
#          Re-aim ray 1: unmark the RELOADED real mark (store index >=1099 > 256) ->
#          13/14 drop to 1100 AND exactly that tri's line leaves the JSONL; the 1099 seeded
#          lines survive byte-identical.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
OUT=/tmp/gmbv26
rm -rf "$OUT"; mkdir -p "$OUT"
GK=build-mbrowse/game/gk
[ -x "$GK" ] || { echo "no $GK"; exit 1; }
XAUTH="$(ls /run/user/1000/.mutter-Xwaylandauth* 2>/dev/null | head -1)"
MARKS_CANDIDATES=("mesh_marks.jsonl" "build-mbrowse/game/mesh_marks.jsonl")
NSEED=1099
FAILS=0
ck(){ # $1=label $2=actual $3=expected
  if [ "${2:-x}" = "$3" ]; then echo "CHECK-OK   $1: $2"; else echo "CHECK-FAIL $1: got '${2:-}' want '$3'"; FAILS=$((FAILS+1)); fi
}

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

start_repl() { # $1=tag — set-active/pick-levels IS the browser-open chain (see v2.5 script)
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
  say "(pc-mb-pick-levels! \"village1\" \"\")" 4
}

stop_repl() { exec 9>&- 2>/dev/null || true; [ -n "$GCPID" ] && kill "$GCPID" 2>/dev/null; GCPID=""; }

geti(){ # $1=label $2=field
  say "(pc-mb-rt-geti $2)" 2
  LASTVAL=$(grep -aE '^-?[0-9]+[[:space:]]+#x' "$RLOG" | tail -1 | awk '{print $1}')
  echo "VALUE $1 = ${LASTVAL:-parse-miss}"
}

find_marks() {
  for f in "${MARKS_CANDIDATES[@]}"; do [ -f "$f" ] && { echo "$f"; return; }; done
  find . build-mbrowse -maxdepth 3 -name mesh_marks.jsonl 2>/dev/null | head -1
}

aim_and_prepare() { # same rays/row as the v2.4/v2.5 batteries
  say "(pc-mb-target-set! 2156 0)" 3
  say "(pc-mb-gizmos-set! 1)" 10
  say "(define mb-dir (new 'static 'array float 4 0.0 -1.0 0.0 0.0))" 2
  say "(define mb-o1 (new 'static 'array float 4 40960.0 61440.0 -102400.0 1.0))" 2
  say "(define mb-o2 (new 'static 'array float 4 81920.0 61440.0 -102400.0 1.0))" 2
}

echo "==================== SEED: $NSEED valid village1 marks (distinct tris, > old 256 cap) ===================="
for f in "${MARKS_CANDIDATES[@]}"; do rm -f "$f"; done
# desktop mb_marks_path(): no external game root -> get_jak_project_dir()/mesh_marks.jsonl,
# i.e. the repo root (v2.5 run confirmed). find_marks re-resolves after run 1 regardless.
MF="mesh_marks.jsonl"
: > "$MF"
python3 - "$MF" $NSEED <<'PY'
import sys
path, n = sys.argv[1], int(sys.argv[2])
with open(path, "w") as f:
    for i in range(n):
        # small upward-facing triangles in a grid near the warp point (10,3,-25) m
        x = 8.0 + 0.25 * (i % 64)
        z = -30.0 - 0.25 * (i // 64)
        f.write('{"game":"jak1","level":"village1","system":"TFRAG","row":2156,'
                f'"shell":7,"material":"vil-beach-01","tex_id":123,"tri":{500000+i},'
                f'"v0_m":[{x:.4f},3.0000,{z:.4f}],"v1_m":[{x+0.2:.4f},3.0000,{z:.4f}],'
                f'"v2_m":[{x:.4f},3.0000,{z-0.2:.4f}],"face_normal":[0.000000,1.000000,0.000000],'
                '"offline_verdict":{"graded":1,"a_sign_x100":100,"b_disp_x100":0},'
                f'"centroid_m":[{x+0.07:.4f},3.0000,{z-0.07:.4f}],'
                f'"aabb_m":[[{x:.4f},3.0000,{z-0.2:.4f}],[{x+0.2:.4f},3.0000,{z:.4f}]]}}\n')
PY
wc -l "$MF"

echo "==================== RUN 1: reload 1099, then mark #1100 and #1101 ===================="
boot_gk "10 3 -25" "R1"
start_repl "R1"
sleep 3
geti "r1_active_after_reload" 13;  ck "reload_active_13" "$LASTVAL" "$NSEED"
geti "r1_drawn_after_reload" 14;   ck "reload_drawn_14" "$LASTVAL" "$NSEED"
geti "r1_skipped_16" 16;           ck "reload_skipped_16" "$LASTVAL" "0"
aim_and_prepare
say "(pc-mb-hover-ray! mb-o1 mb-dir 1)" 3
geti "r1_hover1" 12; TRI1=$LASTVAL
echo "MARK #1100"; say "(pc-mb-mark-poly!)" 2
geti "r1_marks_1100" 13;  ck "mark_1100_active" "$LASTVAL" "$((NSEED+1))"
geti "r1_drawn_1100" 14;  ck "mark_1100_drawn" "$LASTVAL" "$((NSEED+1))"
say "(pc-mb-hover-ray! mb-o2 mb-dir 1)" 3
geti "r1_hover2" 12; TRI2=$LASTVAL
echo "MARK #1101"; say "(pc-mb-mark-poly!)" 2
geti "r1_marks_1101" 13;  ck "mark_1101_active" "$LASTVAL" "$((NSEED+2))"
geti "r1_drawn_1101" 14;  ck "mark_1101_drawn" "$LASTVAL" "$((NSEED+2))"
MFX=$(find_marks); echo "MARKS FILE: ${MFX:-NOT-FOUND}  TRI1=$TRI1 TRI2=$TRI2"
[ -n "$MFX" ] || { echo "FAIL: no marks file after run 1"; exit 1; }
MF="$MFX"
cp "$MF" "$OUT/marks_run1.jsonl"
ck "file_lines_run1" "$(wc -l < "$MF")" "$((NSEED+2))"
stop_repl
echo "---- KILL the app (the restart the owner performs) ----"
pkill -f "$GK" 2>/dev/null; sleep 3

echo "==================== RUN 2: RELAUNCH -> resume 1101, unmark a RELOADED mark beyond 256 ===================="
boot_gk "10 3 -25" "R2"
start_repl "R2"
sleep 3
geti "r2_active_after_reload" 13;  ck "resume_active_13" "$LASTVAL" "$((NSEED+2))"
geti "r2_drawn_after_reload" 14;   ck "resume_drawn_14" "$LASTVAL" "$((NSEED+2))"
geti "r2_skipped_16" 16;           ck "resume_skipped_16" "$LASTVAL" "0"
aim_and_prepare
say "(pc-mb-hover-ray! mb-o1 mb-dir 1)" 3
geti "r2_hover1" 12; TRI1B=$LASTVAL
ck "rehover_same_tri" "$TRI1B" "$TRI1"
echo "UNMARK RELOADED (store index >= $NSEED, far beyond the old 256 cap)"
say "(pc-mb-mark-poly!)" 2
geti "r2_marks_after_unmark" 13;  ck "unmark_active" "$LASTVAL" "$((NSEED+1))"
geti "r2_drawn_after_unmark" 14;  ck "unmark_drawn" "$LASTVAL" "$((NSEED+1))"
cp "$MF" "$OUT/marks_after_unmark.jsonl"
ck "file_lines_after_unmark" "$(wc -l < "$MF")" "$((NSEED+1))"
ck "tri1_line_gone" "$(grep -c "\"tri\":$TRI1," "$OUT/marks_after_unmark.jsonl")" "0"
ck "tri2_line_survives" "$(grep -c "\"tri\":$TRI2," "$OUT/marks_after_unmark.jsonl")" "1"
ck "seeded_lines_survive" "$(grep -cE '"tri":50[01][0-9]{3},' "$OUT/marks_after_unmark.jsonl")" "$NSEED"
stop_repl
pkill -f "$GK" 2>/dev/null; sleep 2

echo "==================== VERDICT ===================="
echo "TRI1=$TRI1 TRI2=$TRI2 TRI1B=$TRI1B  FAILS=$FAILS"
for t in R1 R2; do echo "-------- goalc-$t.log tail:"; grep -aE '^-?[0-9]+[[:space:]]+#x|Error|error' "$OUT/goalc-$t.log" | tail -30; done
if [ "$FAILS" -eq 0 ]; then echo "V26-X86-PROOF PASS"; else echo "V26-X86-PROOF FAIL ($FAILS)"; exit 1; fi
