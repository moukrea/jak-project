#!/usr/bin/env bash
# crisplogo_device_native.sh — Grecharged-title-logo-fullres, the leg the first run got WRONG.
#
# Leg C ("RENDER SCALE 100") did NOT prove the split-inactive case: this device's persisted BASE
# game-size is 800x600, so at RENDER SCALE 100 the world FBO is still 800x600 against a 2400x1080
# panel — the Grender-split is ACTIVE and the logo (correctly) still replays at native. The real
# no-regression case is "the 3D already fills the screen", i.e. render FBO == draw region. Force it
# with the purpose-built debug lever debug.opengoal.renderscale.native=1 (fbo = window size).
#
# Expectation: ZERO "[crisp-logo] native replay" lines with the toggle still ON — begin_2d_ui_pass
# is nullptr, so handle_pc_model can never set defer_native and the stock path runs, structurally.
#
# Also fixes the first run's instrument leak: `kill $LCP` only killed the subshell, leaving the
# `adb logcat` client alive and appending to the previous leg's file (that is why the first run's
# SUMMARY block disagreed with its own per-leg lines — the per-leg numbers are the correct ones).
# Finally restores the owner's settings for his play-test.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
PCS='/storage/emulated/0/OpenGOAL/jak1/settings.ini'
OUT=.autoport/reports/Grecharged-title-logo-fullres; mkdir -p "$OUT"
LOGF="$OUT/device-legs-native.log"; : > "$LOGF"
say(){ echo "$*" | tee -a "$LOGF"; }
fg_ok(){ $ADB -s $S shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | grep -q "$PKG"; }
stop_loggers(){ pkill -f "logcat -v threadtime GK_STDOUT" >/dev/null 2>&1; sleep 1; }

seed(){ local CRISP="$1" SCALE="$2"
  $ADB -s $S shell am force-stop $PKG >/dev/null 2>&1; sleep 2
  $ADB -s $S shell cat "$PCS" > /tmp/crispn_pcs.ini 2>/dev/null || true
  grep -qa '^recharged-master? = ' /tmp/crispn_pcs.ini || { say "  SEED FAIL: no recharged-master? key"; return 1; }
  sed -i "s/^render-scale = .*/render-scale = ${SCALE}.0000/" /tmp/crispn_pcs.ini
  sed -i "s/^dynamic-render-scale? = #[tf]/dynamic-render-scale? = #f/" /tmp/crispn_pcs.ini
  sed -i "s/^recharged-master? = #[tf]/recharged-master? = #t/" /tmp/crispn_pcs.ini
  if grep -qa '^crisp-title-logo? = ' /tmp/crispn_pcs.ini; then
    sed -i "s/^crisp-title-logo? = #[tf]/crisp-title-logo? = #${CRISP}/" /tmp/crispn_pcs.ini
  else
    sed -i "/^recharged-master? = #[tf]/a\\crisp-title-logo? = #${CRISP}" /tmp/crispn_pcs.ini
  fi
  $ADB -s $S push /tmp/crispn_pcs.ini "$PCS" >/dev/null 2>&1
  local BACK; BACK=$($ADB -s $S shell cat "$PCS" 2>/dev/null \
    | grep -aoE '^(crisp-title-logo\?|render-scale|game-size|recharged-master\?) = .*' | tr '\n' ' ')
  say "  seeded: $BACK"
  case "$BACK" in *"crisp-title-logo? = #${CRISP}"*) : ;; *) say "  SEED READBACK FAIL"; return 1 ;; esac
  return 0; }

leg(){ local TAG="$1" CRISP="$2" SCALE="$3" NATIVE="$4" SECS="${5:-95}"
  say ""; say "######## LEG $TAG — crisp=#$CRISP render-scale=$SCALE renderscale.native=$NATIVE ########"
  stop_loggers
  seed "$CRISP" "$SCALE" || return 1
  if [ "$NATIVE" = 1 ]; then $ADB -s $S shell setprop debug.opengoal.renderscale.native 1 >/dev/null 2>&1
  else $ADB -s $S shell "setprop debug.opengoal.renderscale.native ''" >/dev/null 2>&1; fi
  say "  prop: debug.opengoal.renderscale.native='$($ADB -s $S shell getprop debug.opengoal.renderscale.native 2>/dev/null | tr -d '\r')'"
  $ADB -s $S shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
  $ADB -s $S logcat -c >/dev/null 2>&1 || true
  local LOG="$OUT/logcat-$TAG.log"; : > "$LOG"
  ( $ADB -s $S logcat -v threadtime GK_STDOUT:I GK_STDERR:I opengoal-gk:I '*:S' \
      | grep --line-buffered -aE 'crisp-logo|A35-RENDER FBO setup|Fatal signal|signal [0-9]+ \(SIG|GK-DIAG sig=' >> "$LOG" ) 2>/dev/null &
  $ADB -s $S shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
  sleep "$SECS"
  if fg_ok; then say "  foreground: OK"; else say "  foreground: NOT jak1"; fi
  $ADB -s $S shell screencap -p /sdcard/crispn.png >/dev/null 2>&1
  $ADB -s $S pull /sdcard/crispn.png "$OUT/device-$TAG.png" >/dev/null 2>&1
  $ADB -s $S shell rm -f /sdcard/crispn.png >/dev/null 2>&1
  sleep 6
  stop_loggers
  say "  capture       : $OUT/device-$TAG.png ($(stat -c%s "$OUT/device-$TAG.png" 2>/dev/null || echo 0) bytes)"
  say "  toggle line   : $(grep -a 'crisp-logo\] toggle' "$LOG" | tail -1 | sed 's/.*opengoal-gk: //' | tr -d '\r')"
  say "  world FBO     : $(grep -a 'A35-RENDER FBO setup' "$LOG" | tail -1 | sed 's/.*A35-RENDER/A35-RENDER/' | tr -d '\r')"
  say "  replay lines  : $(grep -ac 'crisp-logo\] native replay' "$LOG")"
  say "  last replay   : $(grep -a 'crisp-logo\] native replay' "$LOG" | tail -1 | sed 's/.*\[crisp-logo\]/[crisp-logo]/' | tr -d '\r')"
  say "  crash markers : $(grep -acE 'Fatal signal|signal [0-9]+ \(SIG|GK-DIAG sig=' "$LOG")"
  $ADB -s $S shell am force-stop $PKG >/dev/null 2>&1 || true
  return 0; }

# The no-regression leg: 3D already fills the panel => split inactive => stock path, toggle still ON.
leg NATIVE-ON t 100 1

say ""; say "######## restore the owner's play-test state ########"
$ADB -s $S shell "setprop debug.opengoal.renderscale.native ''" >/dev/null 2>&1
seed t 50   # his persisted render-scale was 50; leave CRISP TITLE LOGO ON so he sees it immediately
say "  (game-size left at his persisted value; CRISP TITLE LOGO left ON — the menu row toggles it live)"
$ADB -s $S shell am force-stop $PKG >/dev/null 2>&1 || true
stop_loggers
say "DONE"
