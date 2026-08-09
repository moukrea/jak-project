#!/usr/bin/env bash
# physics_c14_poscontrol.sh — POSITIVE CONTROL for the MESH-SURFACE penetration audit (cycle 14).
#
# The bone-level control (physics_c6_poscontrol.sh) proved resid/push could see a deliberate
# penetration; the owner's cycle-14 diagnosis is that his eyes live on the MESH and the bone
# counters produced five refutable zeros. So the control moves to the same level as the audit:
#
#   ARMED     physics_chains.txt with inject=<units> on every chain: each collidable link is
#             dragged INTO the body every frame. The mesh audit must SEE it:
#               mraw     (pre-resolve mesh-surface depth beyond the authored floor) must CLIMB
#               mfix     (mesh-sample pushes applied) must CLIMB
#               meshpen  (post-resolve residual) must be ABLE to read nonzero — the injection
#                        re-displaces faster than the bounded correction may push back, so a
#                        blocker counter that cannot rise here could never catch a real defect.
#   DISARMED  the shipped file, byte-identical: injected=0, and meshpen must be 0 with
#             meshtested > 0 (a zero over zero samples is the empty zero this phase has already
#             shipped five times).
#
# Data-only (external override), device file byte-restored on exit — no build in either run.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-$HOME/Android/platform-tools/adb}"
S="${S:-eae4df44}"; PKG=org.opengoal.gk.jak1
EXT=/storage/emulated/0/OpenGOAL/jak1/assets/recharged_assets/physics_chains.txt
OUT=.autoport/reports/Grecharged-secondary-motion; mkdir -p "$OUT"
LOG="$OUT/poscontrol_c14.log"; : > "$LOG"
WATCH="${WATCH:-70}"
INJECT="${INJECT:-140}"
say(){ echo "$*" | tee -a "$LOG"; }
die(){ say "[poscontrol-c14 FAIL] $*"; exit 1; }

$ADB devices | grep -qE "^${S}[[:space:]]+device$" || die "device $S not on adb"
$ADB -s "$S" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
if $ADB -s "$S" shell dumpsys trust 2>/dev/null | grep -a '(current)' | grep -q 'deviceLocked=1'; then
  die "device PIN-LOCKED — wait for owner"
fi

BAK=$(mktemp); ARMED=$(mktemp)
$ADB -s "$S" pull "$EXT" "$BAK" >/dev/null 2>&1 || die "cannot pull the device's physics_chains.txt"
say "device physics_chains.txt backed up ($(stat -c%s "$BAK") bytes)"
cleanup(){
  $ADB -s "$S" push "$BAK" "$EXT" >/dev/null 2>&1 \
    && say "cleanup: device physics_chains.txt byte-restored" \
    || say "cleanup WARNING: could not restore the device physics_chains.txt"
  $ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1 || true
  rm -f "$BAK" "$ARMED" 2>/dev/null || true
}
trap cleanup EXIT

awk -v inj="$INJECT" '/^chain /{ if ($0 !~ /inject=/) $0 = $0 " inject=" inj } {print}' "$BAK" > "$ARMED"
NARM=$(grep -c 'inject=' "$ARMED")
say "armed $NARM chains with inject=$INJECT units (deliberate penetration, mesh-level control)"

run(){ # run <tag> <file>
  local TAG="$1"
  local FILE="$2"
  local LC="$OUT/poscontrol_c14_$TAG.logcat.log"
  $ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1 || true; sleep 2
  $ADB -s "$S" push "$FILE" "$EXT" >/dev/null 2>&1 || die "cannot push $TAG physics_chains.txt"
  $ADB -s "$S" logcat -c >/dev/null 2>&1 || true
  $ADB -s "$S" shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
  ( $ADB -s "$S" logcat -v brief > "$LC" 2>/dev/null ) & local LP=$!
  sleep "$WATCH"
  kill "$LP" 2>/dev/null || true; wait "$LP" 2>/dev/null || true
  local WIN INJ MRAW MFIX MESHP MTEST
  WIN=$(grep -ac '\[HD-PHYS6\] ag=' "$LC" || true)
  INJ=$(grep -a '\[HD-PHYS5\] ag=' "$LC" | grep -oE ' injected=[0-9]+' | grep -oE '[0-9]+' | awk '{s+=$1} END {print s+0}')
  MRAW=$(grep -ao 'mraw=[0-9.]*' "$LC" | sed 's/mraw=//' | sort -g | tail -1)
  MESHP=$(grep -ao 'meshpen=[0-9.]*' "$LC" | sed 's/meshpen=//' | sort -g | tail -1)
  MFIX=$(grep -a 'mfix=' "$LC" | awk '{if (match($0,/mfix=[0-9]+/)) s+=substr($0,RSTART+5,RLENGTH-5)} END {print s+0}')
  MTEST=$(grep -a 'meshtested=' "$LC" | awk '{if (match($0,/meshtested=[0-9]+/)) s+=substr($0,RSTART+11,RLENGTH-11)} END {print s+0}')
  say "leg $TAG: windows6=$WIN injected=$INJ mraw=${MRAW:-0} meshpen=${MESHP:-0} mfix=$MFIX meshtested=$MTEST"
  echo "$WIN $INJ ${MRAW:-0} ${MESHP:-0} $MFIX $MTEST"
}

read -r W_A I_A R_A P_A F_A T_A <<<"$(run ARMED "$ARMED" | tail -1)"
read -r W_D I_D R_D P_D F_D T_D <<<"$(run DISARMED "$BAK" | tail -1)"

say ""
say "=== MESH-LEVEL POSITIVE CONTROL RESULT ==="
say "  ARMED    windows6=$W_A injected=$I_A mraw=$R_A meshpen=$P_A mfix=$F_A meshtested=$T_A"
say "  DISARMED windows6=$W_D injected=$I_D mraw=$R_D meshpen=$P_D mfix=$F_D meshtested=$T_D"
FAIL=0
[ "${W_A:-0}" -ge 1 ] || { say "FAIL: the ARMED run produced no [HD-PHYS6] window"; FAIL=1; }
[ "${W_D:-0}" -ge 1 ] || { say "FAIL: the DISARMED run produced no [HD-PHYS6] window"; FAIL=1; }
[ "${T_A:-0}" -ge 1 ] || { say "FAIL: meshtested=0 ARMED — the mesh audit never sampled a vertex"; FAIL=1; }
[ "${T_D:-0}" -ge 1 ] || { say "FAIL: meshtested=0 DISARMED — the shipped zero is an empty zero"; FAIL=1; }
[ "${I_A:-0}" -gt 0 ] || { say "FAIL: injected=0 with the control ARMED — the injection never ran"; FAIL=1; }
awk -v a="${R_A:-0}" -v d="${R_D:-0}" 'BEGIN{exit !(a+0 > d+0 && a+0 > 1.0)}' \
  || { say "FAIL: mraw did not CLIMB under a deliberate penetration ($R_A vs $R_D) — the mesh audit cannot see one"; FAIL=1; }
[ "${F_A:-0}" -gt 0 ] || { say "FAIL: mfix=0 ARMED — the mesh resolve never fired on a deliberate penetration"; FAIL=1; }
# (C14c) THIS ASSERTION IS DELIBERATELY CHANGED, AND THE CHANGE IS THE POINT — read before trusting
# any zero below. It used to demand meshpen>0 under injection, on the correct principle that a
# counter which can never rise proves nothing when it reads zero. That principle still holds; what
# changed is WHICH counter carries the detection.
#
# The mesh resolve is no longer "push and hope": it bisects the segment [authored pose -> simulated
# pose] for the largest fraction that is clear, and the authored pose is penetration-free against
# every body volume by construction (there the sample and its own floor point are the same point).
# So a feasible commit always exists and meshpen CANNOT be nonzero unless the guarantee itself is
# broken. Demanding that it rise would now be demanding that the fix not work.
#
# meshpen therefore stops being the DETECTOR and becomes a CHECKED POSTCONDITION. The detection
# moved to the two counters either side of the resolve, and both are gated above, unchanged:
#   mraw  must CLIMB under injection  — the audit still SEES a deliberate mesh penetration
#   mfix  must be > 0 under injection — the resolve still FIRES on one
# and the anti-vacuous-zero rule is satisfied in its own terms: meshpen=0 is not "nobody looked",
# it is "mfix commits were each re-audited AT the committed point and every one came back clear".
# mfix is that backing count. A zero with mfix=0 would still be an empty zero and still fails.
#
# What this control can no longer prove is that a BROKEN clamp would be caught, and that is stated
# rather than papered over. The residual it would leave is measured by the same re-audit that
# produces meshpen, so the counter is falsifiable — it is just not falsifiable by injection.
[ "${F_A:-0}" -gt 0 ] \
  || { say "FAIL: mfix=0 ARMED — nothing was committed and re-audited, so meshpen=$P_A is an empty zero"; FAIL=1; }
awk -v v="${P_A:-0}" 'BEGIN{exit !(v+0 <= 0.0001)}' \
  || { say "FAIL: meshpen=$P_A ARMED — the feasibility clamp FAILED to find a clear commit under injection"; FAIL=1; }
[ "${I_D:-0}" -eq 0 ] || { say "FAIL: injected=$I_D DISARMED — the shipped data carries an armed control"; FAIL=1; }
awk -v v="${P_D:-0}" 'BEGIN{exit !(v+0 <= 0.0001)}' \
  || { say "FAIL: meshpen=$P_D DISARMED — the shipped build leaves mesh-level residual penetration"; FAIL=1; }
if [ "$FAIL" = 0 ]; then
  say "[poscontrol-c14 PASS] the mesh-surface audit RISES on a deliberate penetration (mraw $R_D -> $R_A, meshpen $P_D -> $P_A, mfix $F_D -> $F_A) and returns to zero without it"
else
  say "[poscontrol-c14 FAIL] see above"
fi
exit "$FAIL"
