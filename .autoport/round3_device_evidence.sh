#!/bin/bash
# Round-3 device evidence for Grecharged-hud-jak1.
# Adapted from proven round2_device_evidence2.sh (setprop quoting + getprop verify + logcat hook-arming gates).
set -u
export ANDROID_SERIAL=eae4df44
ADB="/home/emeric/Android/platform-tools/adb"
PKG=org.opengoal.gk.jak1
ROOT=/home/emeric/code/jak-project/.autoport/reports/Grecharged-hud-jak1
SHOTS="$ROOT/shots"
R2="$ROOT/round2"
LOGCAT="$R2/device-R3-logcat.txt"
PCS='files/.config/OpenGOAL/jak1/settings/pc-settings.gc'
mkdir -p "$SHOTS" "$R2"

a(){ "$ADB" -s eae4df44 "$@"; }
ashell(){ "$ADB" -s eae4df44 shell "$@"; }
log(){ echo "[$(date +%H:%M:%S)] $*"; }
devok(){ [ "$(a get-state 2>/dev/null | tr -d '\r')" = "device" ]; }

setp(){ local name="$1"; shift; local val="$*"
  ashell "setprop $name '$val'"
  local got; got="$(ashell "getprop $name" | tr -d '\r')"
  echo "  setprop $name='$val' -> getprop='$got'"; }

focus(){ ashell "dumpsys window | grep mCurrentFocus" | tr -d '\r'; }

shot(){ local name="$1"; local f; f="$(focus)"
  a exec-out screencap -p > "$SHOTS/$name.png" 2>/dev/null
  local sz; sz="$(stat -c %s "$SHOTS/$name.png" 2>/dev/null)"
  echo "  SHOT $name.png bytes=$sz focus=$f"; }

waitlog(){ local pat="$1"; local secs="$2"; local label="$3"; local i=0
  while [ $i -lt "$secs" ]; do
    if grep -a -q "$pat" "$LOGCAT" 2>/dev/null; then
      echo "  ARMED [$label]: $(grep -a "$pat" "$LOGCAT" | tail -1)"; return 0; fi
    sleep 1; i=$((i+1)); done
  echo "  FAILED-TO-ARM [$label]: pattern '$pat' not seen in ${secs}s"; return 1; }

start_logcat(){ a logcat -c; ( a logcat -v time > "$LOGCAT" 2>&1 ) & LOGCAT_PID=$!; sleep 1; }
LOGCAT_PID=""

warp_launch(){
  log "force-stop + (re)start logcat + warp-launch"
  ashell "am force-stop $PKG"; sleep 1
  [ -n "$LOGCAT_PID" ] && kill "$LOGCAT_PID" 2>/dev/null
  start_logcat
  setp debug.opengoal.f1.warp 1
  ashell "am start -n $PKG/org.opengoal.gk.LoaderActivity" >/dev/null 2>&1
  log "launched, waiting for F1-WARP"
  waitlog "\[F1-WARP\]" 90 "F1-WARP" || log "warp wait timed out (continuing)"
  log "+10s settle"; sleep 10
  echo "post-launch focus: $(focus)"; }

# toggle (recharged-hud? #t|#f) via pull-edit-push (parens break device sed)
set_recharged(){ # $1 = "#t" or "#f"
  local want="$1"; local tmp=/tmp/pcs_r3.gc
  ashell "run-as $PKG cat $PCS" > "$tmp" 2>/dev/null
  if [ "$want" = "#f" ]; then sed -i 's/(recharged-hud? #t)/(recharged-hud? #f)/' "$tmp"
  else sed -i 's/(recharged-hud? #f)/(recharged-hud? #t)/' "$tmp"; fi
  a push "$tmp" /data/local/tmp/pcs_r3.gc >/dev/null 2>&1
  ashell "run-as $PKG cp /data/local/tmp/pcs_r3.gc $PCS"
  ashell "rm -f /data/local/tmp/pcs_r3.gc" 2>/dev/null; }

######## SESSION SETUP ########
log "=== session setup ==="
echo "settings check (recharged-hud? should be #t):"
ashell "run-as $PKG cat $PCS 2>/dev/null | grep -a recharged-hud" | tr -d '\r' || echo "  (not readable via run-as)"
warp_launch

######## BEAT A — green waver by heart (5 close shots) ########
log "=== BEAT A: green eco waver (eco-pill type 7) ==="
setp debug.opengoal.eco.spawn "7 120 0.4 0.3 0.4"
waitlog "\[ECO-SPAWN\] armed" 15 "eco-spawn-green" || echo "  (proceeding, eco-spawn hook not confirmed)"
sleep 6
setp debug.opengoal.cpad_inject "ly=40";  sleep 0.8; setp debug.opengoal.cpad_inject ""
setp debug.opengoal.cpad_inject "ly=215"; sleep 0.8; setp debug.opengoal.cpad_inject ""
for i in 1 2 3 4 5; do shot device-R3-green-$i; sleep 0.8; done
setp debug.opengoal.eco.spawn ""
echo "  eco.spawn cleared -> '$(ashell "getprop debug.opengoal.eco.spawn" | tr -d '\r')'"

######## BEAT B — gauge center particles per eco type ########
log "=== BEAT B: gauge center particles ==="
gauge_type(){ local tn="$1"; local color="$2"
  devok || { log "DEVICE VANISHED before gauge $color"; return 9; }
  log "--- gauge $color (type=$tn) ---"
  setp debug.opengoal.eco.spawn "$tn 120 0.4 0.3 0.4"
  waitlog "\[ECO-SPAWN\] armed" 15 "eco-spawn-$color" || echo "  (proceeding, eco-spawn hook not confirmed for $color)"
  sleep 6
  setp debug.opengoal.cpad_inject "ly=40";  sleep 0.8; setp debug.opengoal.cpad_inject ""
  setp debug.opengoal.cpad_inject "ly=215"; sleep 0.8; setp debug.opengoal.cpad_inject ""
  for i in 1 2 3; do shot device-R3-gauge-$color-$i; sleep 0.8; done
  setp debug.opengoal.eco.spawn ""
  echo "  eco.spawn cleared -> '$(ashell "getprop debug.opengoal.eco.spawn" | tr -d '\r')'"
  log "draining eco 25s"; sleep 25; }
gauge_type 3 blue
gauge_type 2 red
gauge_type 1 yellow

######## BEAT C — cell body + halo (hold l2) ########
log "=== BEAT C: cell body + halo (hold l2) ==="
if devok; then
  setp debug.opengoal.cpad_inject l2; sleep 2
  for i in 1 2 3 4; do shot device-R3-cell-$i; sleep 1.0; done
  setp debug.opengoal.cpad_inject ""
else log "DEVICE VANISHED before beat C"; fi

######## BEAT D — fade blink heart burst (die props set BEFORE launch) ########
log "=== BEAT D: fade-blink heart burst ==="
if devok; then
  setp debug.opengoal.die.mode "drown-death"
  setp debug.opengoal.die 1
  warp_launch
  log "walk to beach (ly=0 held 4s)"
  setp debug.opengoal.cpad_inject "ly=0"; sleep 4; setp debug.opengoal.cpad_inject ""
  waitlog "GDEATH-FIRE" 30 "die-hook" || echo "  (GDEATH-FIRE not confirmed in logcat)"
  log "heart burst 24 shots @0.5s"
  for i in $(seq -w 1 24); do shot device-R3-heart-$i; sleep 0.5; done
  setp debug.opengoal.die ""
  setp debug.opengoal.die.mode ""
  echo "  heart burst byte sizes:"
  for i in $(seq -w 1 24); do stat -c '  %n %s' "$SHOTS/device-R3-heart-$i.png" 2>/dev/null; done
else log "DEVICE VANISHED before beat D"; fi

######## BEAT E — OFF spot-check then restore ########
log "=== BEAT E: OFF spot-check ==="
if devok; then
  log "push settings recharged-hud? #f (pull-edit-push)"
  set_recharged "#f"
  ashell "run-as $PKG cat $PCS 2>/dev/null | grep -a recharged-hud" | tr -d '\r'
  warp_launch
  setp debug.opengoal.cpad_inject l2; sleep 2
  shot device-R3-off-1; sleep 1.0; shot device-R3-off-2
  setp debug.opengoal.cpad_inject ""
  log "RESTORE settings recharged-hud? #t (pull-edit-push)"
  set_recharged "#t"
  ashell "run-as $PKG cat $PCS 2>/dev/null | grep -a recharged-hud" | tr -d '\r'
else log "DEVICE VANISHED before beat E"; fi

######## CLEANUP ########
log "=== cleanup ==="
if devok; then
  for p in debug.opengoal.cpad_inject debug.opengoal.eco.spawn debug.opengoal.die debug.opengoal.die.mode debug.opengoal.f1.warp; do setp "$p" ""; done
  echo "final getprop check:"
  for p in debug.opengoal.cpad_inject debug.opengoal.eco.spawn debug.opengoal.die debug.opengoal.die.mode debug.opengoal.f1.warp; do
    echo "  $p='$(ashell "getprop $p" | tr -d '\r')'"; done
  ashell "am force-stop $PKG"; sleep 1
else log "DEVICE UNREACHABLE at cleanup — props may remain set"; fi
[ -n "$LOGCAT_PID" ] && kill "$LOGCAT_PID" 2>/dev/null
log "DONE. logcat -> $LOGCAT ; shots -> $SHOTS"
