#!/bin/bash
# Round-2b device evidence for Grecharged-hud-jak1.
# All setprop multi-word values quoted INSIDE the shell string; every setprop verified.
set -u
export ANDROID_SERIAL=eae4df44
ADB="/home/emeric/Android/platform-tools/adb"
PKG=org.opengoal.gk.jak1
ROOT=/home/emeric/code/jak-project/.autoport/reports/Grecharged-hud-jak1
SHOTS="$ROOT/shots"
R2="$ROOT/round2"
LOGCAT="$R2/device-R2b-logcat.txt"
mkdir -p "$SHOTS" "$R2"

a(){ "$ADB" -s eae4df44 "$@"; }
ashell(){ "$ADB" -s eae4df44 shell "$@"; }

log(){ echo "[$(date +%H:%M:%S)] $*"; }

# setprop + verify it took
setp(){ # name value
  local name="$1"; shift
  local val="$*"
  ashell "setprop $name '$val'"
  local got
  got="$(ashell "getprop $name" | tr -d '\r')"
  echo "  setprop $name='$val' -> getprop='$got'"
}

focus(){
  local f
  f="$(ashell "dumpsys window | grep mCurrentFocus" | tr -d '\r')"
  echo "$f"
}

shot(){ # name
  local name="$1"
  local f
  f="$(focus)"
  a exec-out screencap -p > "$SHOTS/$name.png" 2>/dev/null
  local sz
  sz="$(stat -c %s "$SHOTS/$name.png" 2>/dev/null)"
  echo "  SHOT $name.png bytes=$sz focus=$f"
}

waitlog(){ # pattern seconds label
  local pat="$1"; local secs="$2"; local label="$3"
  local i=0
  while [ $i -lt "$secs" ]; do
    if grep -a -q "$pat" "$LOGCAT" 2>/dev/null; then
      echo "  ARMED [$label]: $(grep -a "$pat" "$LOGCAT" | tail -1)"
      return 0
    fi
    sleep 1; i=$((i+1))
  done
  echo "  FAILED-TO-ARM [$label]: pattern '$pat' not seen in ${secs}s"
  return 1
}

######## SESSION SETUP ########
log "=== session setup ==="
# verify recharged-hud setting is #t
echo "settings check:"
ashell "run-as $PKG cat files/pc-settings.gc 2>/dev/null | grep -a recharged" | tr -d '\r' || echo "  (pc-settings recharged line not readable via run-as)"

setp debug.opengoal.f1.warp 1

log "force-stop + start logcat capture"
ashell "am force-stop $PKG"
a logcat -c
# background logcat routing
( a logcat -v time > "$LOGCAT" 2>&1 ) &
LOGCAT_PID=$!
sleep 1
ashell "am start -n $PKG/org.opengoal.gk.LoaderActivity" >/dev/null 2>&1
log "launched, waiting for F1-WARP"
waitlog "\[F1-WARP\]" 60 "F1-WARP" || log "warp wait timed out (continuing, will still probe)"
log "+10s settle"
sleep 10
echo "post-launch focus: $(focus)"

######## BEAT A — boot-ON cell (warm lighting) ########
log "=== BEAT A: boot-ON cell ==="
setp debug.opengoal.cpad_inject l2
sleep 2
shot device-R2b-cell-1
sleep 1.2
shot device-R2b-cell-2
sleep 1.2
shot device-R2b-cell-3
setp debug.opengoal.cpad_inject ""

######## BEAT B — gauge fill + center orb per type ########
log "=== BEAT B: gauge fill per eco type ==="
gauge_type(){ # typenum colorname
  local tn="$1"; local color="$2"
  log "--- gauge $color (type=$tn) ---"
  setp debug.opengoal.eco.spawn "$tn 120 0.4 0.3 0.4"
  waitlog "\[ECO-SPAWN\] armed" 15 "eco-spawn-$color" || { echo "  (proceeding but eco-spawn hook not confirmed for $color)"; }
  sleep 6
  # walk wiggle forward+back through pickups
  setp debug.opengoal.cpad_inject "ly=40";  sleep 0.8; setp debug.opengoal.cpad_inject ""
  setp debug.opengoal.cpad_inject "ly=215"; sleep 0.8; setp debug.opengoal.cpad_inject ""
  shot device-R2b-gauge-$color-1
  sleep 1
  shot device-R2b-gauge-$color-2
  sleep 1
  shot device-R2b-gauge-$color-3
  # extra wiggle+shots if uncertain (we always do the fallback burst)
  setp debug.opengoal.cpad_inject "ly=40";  sleep 0.8; setp debug.opengoal.cpad_inject ""
  setp debug.opengoal.cpad_inject "ly=215"; sleep 0.8; setp debug.opengoal.cpad_inject ""
  shot device-R2b-gauge-$color-4
  sleep 1
  shot device-R2b-gauge-$color-5
  # clear + verify empty + drain
  setp debug.opengoal.eco.spawn ""
  local got
  got="$(ashell "getprop debug.opengoal.eco.spawn" | tr -d '\r')"
  echo "  eco.spawn cleared -> getprop='$got'"
  log "draining eco 25s before next type"
  sleep 25
}
gauge_type 3 blue
gauge_type 2 red
gauge_type 1 yellow

######## BEAT C — heart states (drown death) ########
log "=== BEAT C: heart states (drown) ==="
setp debug.opengoal.cpad_inject "ly=0"
sleep 4
setp debug.opengoal.cpad_inject ""
setp debug.opengoal.die.mode "drown-death"
setp debug.opengoal.die 1
waitlog "GDEATH-FIRE\|GDEATH-MOVIE\|GDEATH-ARM" 20 "die-hook" || echo "  (die hook not confirmed in logcat)"
log "heart burst 24 shots @0.7s"
for i in $(seq -w 1 24); do
  shot device-R2b-heart-$i
  sleep 0.7
done
setp debug.opengoal.die ""
setp debug.opengoal.die.mode ""
# byte-size variance across burst (no interpretation, just objective spread)
echo "  heart burst byte sizes:"
for i in $(seq -w 1 24); do stat -c '%n %s' "$SHOTS/device-R2b-heart-$i.png" 2>/dev/null; done

######## BEAT D — circle-back clean menu nav ########
log "=== BEAT D: circle-back menu nav ==="
tap(){ ashell "input keyevent $1"; }
# start = pause
ashell "input keyevent KEYCODE_BUTTON_START"; sleep 2.2
ashell "input keyevent KEYCODE_BUTTON_B"; sleep 1.0    # circle -> options
ashell "input keyevent KEYCODE_DPAD_DOWN"; sleep 0.5
ashell "input keyevent KEYCODE_BUTTON_A"; sleep 1.0    # x -> graphics
for n in 1 2 3 4 5 6 7 8; do ashell "input keyevent KEYCODE_DPAD_DOWN"; sleep 0.5; done
ashell "input keyevent KEYCODE_BUTTON_A"; sleep 1.5    # x -> recharged submenu (cursor on toggle, NOT edit)
shot device-R2b-circleback-before
ashell "input keyevent KEYCODE_BUTTON_B"; sleep 1.5    # single circle -> back to Graphics Options
shot device-R2b-circleback-after
ashell "input keyevent KEYCODE_BUTTON_B"; sleep 0.6
ashell "input keyevent KEYCODE_BUTTON_B"; sleep 0.6
ashell "input keyevent KEYCODE_BUTTON_START"; sleep 1.0  # unpause
shot device-R2b-unpaused

######## CLEANUP ########
log "=== cleanup ==="
for p in debug.opengoal.cpad_inject debug.opengoal.eco.spawn debug.opengoal.die debug.opengoal.die.mode debug.opengoal.f1.warp; do
  setp "$p" ""
done
echo "final getprop check:"
for p in debug.opengoal.cpad_inject debug.opengoal.eco.spawn debug.opengoal.die debug.opengoal.die.mode debug.opengoal.f1.warp; do
  echo "  $p='$(ashell "getprop $p" | tr -d '\r')'"
done
ashell "am force-stop $PKG"
sleep 1
kill $LOGCAT_PID 2>/dev/null
log "DONE. logcat -> $LOGCAT ; shots -> $SHOTS"
