#!/usr/bin/env bash
# gmb_v26b_x86_proof.sh — Grecharged-mesh-browser V2.6-bis DESKTOP proof: ISOLATION MODE.
# Owner (2026-07-31 ~10:30): "Quand on a selectionne un mesh, on devrait avoir la possibilite
# de cacher les autres". Under test: gs.mb_isolate — while a target is active, TFragment/Tie3
# skip every NON-target draw and the world renderers (Shrub/Merc2/Generic2/Ocean/Shadow)
# early-out; sky/UI untouched. Proof is RENDERER-side counters (the V2.1 lesson — variables
# that toggle prove nothing), read per frame via pc-mb-rt-geti:
#   field 4  = target draws submitted last frame        (must stay >0 under isolation)
#   field 17 = NON-target TFRAG+TIE draws submitted     (nominal >0; isolation ON -> 0)
#   field 18 = render work suppressed by isolation      (OFF -> 0; ON -> >0)
# Battery:
#   A. baseline OFF          : 4>0, 17>0, 18==0
#   B. isolate ON            : 17==0, 4>0, 18>0
#   C. isolate OFF           : 17>0, 18==0
#   D. isolate ON again      : 17==0, 18>0          (the on -> off -> on both-ways demand)
#   E. target CHANGE under ON: 17==0, 18>0          (re-isolates the new target, flag survives)
#   F. defocus clears it     : re-target -> 17>0, 18==0 (target-clear reset the flag)
#   G. close clears it       : isolate on, set-active 0, reopen+retarget -> 17>0, 18==0
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
OUT=/tmp/gmbv26b
rm -rf "$OUT"; mkdir -p "$OUT"
GK=build-mbrowse/game/gk
[ -x "$GK" ] || { echo "no $GK"; exit 1; }
XAUTH="$(ls /run/user/1000/.mutter-Xwaylandauth* 2>/dev/null | head -1)"
FAILS=0
ck_eq(){ if [ "${2:-x}" = "$3" ]; then echo "CHECK-OK   $1: $2"; else echo "CHECK-FAIL $1: got '${2:-}' want '$3'"; FAILS=$((FAILS+1)); fi; }
ck_gt0(){ if [ "${2:-0}" -gt 0 ] 2>/dev/null; then echo "CHECK-OK   $1: $2 (>0)"; else echo "CHECK-FAIL $1: got '${2:-}' want >0"; FAILS=$((FAILS+1)); fi; }

GKPID=""; GCPID=""; FIFO=""; RLOG=""
cleanup() { [ -n "$GCPID" ] && kill "$GCPID" 2>/dev/null; pkill -f "$GK" 2>/dev/null; sleep 1; }
trap cleanup EXIT

echo "==================== BOOT (village1 hut warp, marks-battery vantage) ===================="
pkill -f "$GK" 2>/dev/null; sleep 2
GKLOG=$OUT/gk.log
DISPLAY="${DISPLAY:-:0}" XAUTHORITY="$XAUTH" LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
OG_LEVEL_WARP=village1-hut OG_LEVEL_WARP_POS="10 3 -25" \
stdbuf -oL -eL "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi \
  -- -boot -debug-mem > "$GKLOG" 2>&1 &
GKPID=$!
t=0
until grep -qa "LEVEL-WARP-SPAWN" "$GKLOG"; do
  sleep 3; t=$((t+3))
  kill -0 $GKPID 2>/dev/null || { echo "gk died during boot"; tail -20 "$GKLOG"; exit 1; }
  [ $t -ge 300 ] && { echo "no warp after ${t}s"; exit 1; }
done
sleep 25

RLOG=$OUT/goalc.log
FIFO=$OUT/repl.fifo
rm -f "$FIFO"; mkfifo "$FIFO"
( build/goalc/goalc --game jak1 --proj-path . < "$FIFO" > "$RLOG" 2>&1 ) &
GCPID=$!
exec 9>"$FIFO"
say(){ printf '%s\n' "$1" >&9; sleep "${2:-1.5}"; }
geti(){ # $1=label $2=field -> LASTVAL
  say "(pc-mb-rt-geti $2)" 2
  LASTVAL=$(grep -aE '^-?[0-9]+[[:space:]]+#x' "$RLOG" | tail -1 | awk '{print $1}')
  echo "VALUE $1 = ${LASTVAL:-parse-miss}"
}
say "(lt)" 6
say "(define-extern pc-mb-set-active! (function int none))" 1
say "(define-extern pc-mb-pick-levels! (function string string none))" 1
say "(define-extern pc-mb-target-set! (function int int none))" 1
say "(define-extern pc-mb-target-clear! (function none))" 1
say "(define-extern pc-mb-isolate-set! (function int none))" 1
say "(define-extern pc-mb-rt-geti (function int int))" 1
say "(pc-mb-set-active! 1)" 1
say "(pc-mb-pick-levels! \"village1\" \"\")" 4
say "(pc-mb-target-set! 2156 0)" 3

echo "==================== A. BASELINE OFF ===================="
geti a_target 4;    ck_gt0 "A_target_draws" "$LASTVAL"
geti a_nontgt 17;   ck_gt0 "A_nontarget_draws" "$LASTVAL"
geti a_skips 18;    ck_eq  "A_isolated_skips" "$LASTVAL" "0"

echo "==================== B. ISOLATE ON ===================="
say "(pc-mb-isolate-set! 1)" 2
geti b_nontgt 17;   ck_eq  "B_nontarget_draws_zero" "$LASTVAL" "0"
geti b_target 4;    ck_gt0 "B_target_draws_still" "$LASTVAL"
geti b_skips 18;    ck_gt0 "B_isolated_skips" "$LASTVAL"

echo "==================== C. ISOLATE OFF (both directions) ===================="
say "(pc-mb-isolate-set! 0)" 2
geti c_nontgt 17;   ck_gt0 "C_nontarget_back" "$LASTVAL"
geti c_skips 18;    ck_eq  "C_skips_zero" "$LASTVAL" "0"

echo "==================== D. ISOLATE ON AGAIN (on -> off -> on) ===================="
say "(pc-mb-isolate-set! 1)" 2
geti d_nontgt 17;   ck_eq  "D_nontarget_zero_again" "$LASTVAL" "0"
geti d_skips 18;    ck_gt0 "D_skips_again" "$LASTVAL"

echo "==================== E. TARGET CHANGE UNDER ISOLATION (re-isolates) ===================="
say "(pc-mb-target-set! 2200 0)" 3
geti e_nontgt 17;   ck_eq  "E_new_target_still_isolated" "$LASTVAL" "0"
geti e_skips 18;    ck_gt0 "E_skips_persist" "$LASTVAL"

echo "==================== F. DEFOCUS CLEARS THE FLAG ===================="
say "(pc-mb-target-clear!)" 2
say "(pc-mb-target-set! 2156 0)" 3
geti f_nontgt 17;   ck_gt0 "F_retarget_not_isolated" "$LASTVAL"
geti f_skips 18;    ck_eq  "F_skips_zero" "$LASTVAL" "0"

echo "==================== G. BROWSER CLOSE CLEARS THE FLAG ===================="
say "(pc-mb-isolate-set! 1)" 2
geti g_pre 17;      ck_eq  "G_isolated_before_close" "$LASTVAL" "0"
say "(pc-mb-set-active! 0)" 2
say "(pc-mb-set-active! 1)" 1
say "(pc-mb-pick-levels! \"village1\" \"\")" 4
say "(pc-mb-target-set! 2156 0)" 3
geti g_nontgt 17;   ck_gt0 "G_reopen_not_isolated" "$LASTVAL"
geti g_skips 18;    ck_eq  "G_skips_zero" "$LASTVAL" "0"

exec 9>&- 2>/dev/null || true
kill "$GCPID" 2>/dev/null; GCPID=""
pkill -f "$GK" 2>/dev/null; sleep 2

echo "==================== VERDICT ===================="
echo "FAILS=$FAILS"
grep -aE '^-?[0-9]+[[:space:]]+#x' "$RLOG" | tail -40
if [ "$FAILS" -eq 0 ]; then echo "V26B-X86-PROOF PASS"; else echo "V26B-X86-PROOF FAIL ($FAILS)"; exit 1; fi
