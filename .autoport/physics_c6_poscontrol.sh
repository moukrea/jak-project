#!/usr/bin/env bash
# physics_c6_poscontrol.sh — THE POSITIVE CONTROL for the penetration audit, run on the phone.
#
# Owner, cycle 6: "avant de rapporter le moindre zero, l'audit doit PROUVER qu'il sait detecter une
# penetration. Injecter deliberement une chaine dans le corps, montrer que le compteur monte, puis
# retirer l'injection. Un zero sans controle positif est refuse."
#
# He is right to make this non-negotiable: three zeros shipped in one day were vacuous — resid=0
# with push=0, idledrift=0 with idlewin=0, restdevA=0 with restwin=0 — each because the measurement
# never ran. So this runs the SAME build twice and compares:
#
#   ARMED     physics_chains.txt with inject=<units> on every chain. Each collidable link is dragged
#             that far toward the spine of the first volume it is tested against, i.e. INTO the body
#             by construction rather than by luck. injected= and push= must CLIMB.
#   DISARMED  the shipped file, byte-identical to what ships. injected= must be 0.
#
# It is data-only: physics_chains.txt is read at runtime from the EXTERNAL override
# (/storage/emulated/0/OpenGOAL/jak1/assets/recharged_assets), so neither run needs a build.
# The device's file is backed up and byte-restored on exit, whatever happens.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-$HOME/Android/platform-tools/adb}"
S="${S:-eae4df44}"; PKG=org.opengoal.gk.jak1
EXT=/storage/emulated/0/OpenGOAL/jak1/assets/recharged_assets/physics_chains.txt
OUT=.autoport/reports/Grecharged-secondary-motion; mkdir -p "$OUT"
LOG="$OUT/poscontrol.log"; : > "$LOG"
WATCH="${WATCH:-70}"
INJECT="${INJECT:-140}"
say(){ echo "$*" | tee -a "$LOG"; }
die(){ say "[poscontrol FAIL] $*"; exit 1; }

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

# arm every chain: the control must fire on whatever actor the run happens to put on screen
awk -v inj="$INJECT" '/^chain /{ if ($0 !~ /inject=/) $0 = $0 " inject=" inj } {print}' "$BAK" > "$ARMED"
NARM=$(grep -c 'inject=' "$ARMED")
say "armed $NARM chains with inject=$INJECT units"

run(){ # run <tag> <file>
  local TAG="$1" FILE="$2" LC="$OUT/poscontrol_$TAG.logcat.log"
  $ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1 || true; sleep 2
  $ADB -s "$S" push "$FILE" "$EXT" >/dev/null 2>&1 || die "cannot push $TAG physics_chains.txt"
  $ADB -s "$S" logcat -c >/dev/null 2>&1 || true
  $ADB -s "$S" shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
  ( $ADB -s "$S" logcat -v brief > "$LC" 2>/dev/null ) & local LP=$!
  sleep "$WATCH"
  kill "$LP" 2>/dev/null || true; wait "$LP" 2>/dev/null || true
  # the audit numbers, summed over every window line of the run
  local INJ PUSH RESID CVC WIN
  WIN=$(grep -ac '\[HD-PHYS5\] ag=' "$LC" || true)
  INJ=$(grep -a '\[HD-PHYS5\] ag=' "$LC" | grep -oE ' injected=[0-9]+' | grep -oE '[0-9]+' | awk '{s+=$1} END {print s+0}')
  CVC=$(grep -a '\[HD-PHYS5\] ag=' "$LC" | grep -oE ' chainvschain=[0-9]+' | grep -oE '[0-9]+' | awk '{s+=$1} END {print s+0}')
  PUSH=$(grep -a '\[HD-PHYS\] ag=' "$LC" | grep -oE ' push=[0-9]+' | grep -oE '[0-9]+' | awk '{s+=$1} END {print s+0}')
  RESID=$(grep -a '\[HD-PHYS\] ag=' "$LC" | grep -oE ' resid=[0-9]+' | grep -oE '[0-9]+' | awk '{s+=$1} END {print s+0}')
  say "leg $TAG: windows=$WIN injected=$INJ push=$PUSH resid=$RESID chainvschain=$CVC"
  echo "$WIN $INJ $PUSH $RESID $CVC"
}

read -r W_A I_A P_A R_A C_A <<<"$(run ARMED "$ARMED" | tail -1)"
read -r W_D I_D P_D R_D C_D <<<"$(run DISARMED "$BAK" | tail -1)"

say ""
say "=== POSITIVE CONTROL RESULT ==="
say "  ARMED    windows=$W_A injected=$I_A push=$P_A resid=$R_A chainvschain=$C_A"
say "  DISARMED windows=$W_D injected=$I_D push=$P_D resid=$R_D chainvschain=$C_D"
FAIL=0
[ "${W_A:-0}" -ge 1 ] || { say "FAIL: the ARMED run produced no [HD-PHYS5] window at all"; FAIL=1; }
[ "${W_D:-0}" -ge 1 ] || { say "FAIL: the DISARMED run produced no [HD-PHYS5] window at all"; FAIL=1; }
[ "${I_A:-0}" -gt 0 ] || { say "FAIL: injected=0 with the control ARMED — the injection never ran, so the control proves nothing"; FAIL=1; }
[ "${P_A:-0}" -gt "${P_D:-0}" ] || { say "FAIL: push did not CLIMB under a deliberate penetration ($P_A vs $P_D) — the audit cannot see one"; FAIL=1; }
[ "${I_D:-0}" -eq 0 ] || { say "FAIL: injected=$I_D with the control DISARMED — the shipped data carries an armed control"; FAIL=1; }
if [ "$FAIL" = 0 ]; then
  say "[poscontrol PASS] the counter RISES on a deliberate penetration and returns to zero without it"
else
  say "[poscontrol FAIL] see above"
fi
exit "$FAIL"
