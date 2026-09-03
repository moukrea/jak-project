#!/usr/bin/env bash
# crisplogo_device.sh — Grecharged-title-logo-fullres device evidence on the Redmi (eae4df44).
#
# Three legs, each a fresh boot with a seeded+read-back settings.ini:
#   A  OFF  @ RENDER SCALE 40  -> pixelated logo (stock pipeline) ................ device-OFF-rs40.png
#   B  ON   @ RENDER SCALE 40  -> crisp logo, world still scaled ................. device-ON-rs40.png
#   C  ON   @ RENDER SCALE 100 -> split inactive: MUST take the stock path ....... device-ON-rs100.png
#
# The DECISIVE proof is code-level, not visual (no visual-measurement campaign):
#   * "A35-RENDER FBO setup: WxH"        -> the size the 3D world renders at
#   * "[crisp-logo] native replay: ... fb=WxH" -> the size the LOGO renders at
# Leg B must show a logo fb strictly larger than the world fbo; legs A and C must show NO replay
# line at all (A: feature off, C: split inactive => structurally the stock path).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
PCS='/storage/emulated/0/OpenGOAL/jak1/settings.ini'   # external-asset mode; files/.config is DEAD
OUT=.autoport/reports/Grecharged-title-logo-fullres; mkdir -p "$OUT"
LOGF="$OUT/device-legs.log"; : > "$LOGF"
say(){ echo "$*" | tee -a "$LOGF"; }
fg_ok(){ $ADB -s $S shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | grep -q "$PKG"; }

# Seed crisp-title-logo? + render-scale INSIDE the [settings] section (never append at EOF: the
# tail lands in [music] and gets dropped), then READ BACK and die if the values did not land.
seed(){ local CRISP="$1" SCALE="$2"
  $ADB -s $S shell am force-stop $PKG >/dev/null 2>&1; sleep 2
  $ADB -s $S shell cat "$PCS" > /tmp/crisp_pcs.ini 2>/dev/null || true
  grep -qa '^recharged-master? = ' /tmp/crisp_pcs.ini || { say "  SEED FAIL: no recharged-master? key in $PCS"; return 1; }
  # render-scale is a float; dynamic OFF so the controller cannot move it under us
  sed -i "s/^render-scale = .*/render-scale = ${SCALE}.0000/" /tmp/crisp_pcs.ini
  sed -i "s/^dynamic-render-scale? = #[tf]/dynamic-render-scale? = #f/" /tmp/crisp_pcs.ini
  sed -i "s/^recharged-master? = #[tf]/recharged-master? = #t/" /tmp/crisp_pcs.ini
  if grep -qa '^crisp-title-logo? = ' /tmp/crisp_pcs.ini; then
    sed -i "s/^crisp-title-logo? = #[tf]/crisp-title-logo? = #${CRISP}/" /tmp/crisp_pcs.ini
  else
    sed -i "/^recharged-master? = #[tf]/a\\crisp-title-logo? = #${CRISP}" /tmp/crisp_pcs.ini
  fi
  $ADB -s $S push /tmp/crisp_pcs.ini "$PCS" >/dev/null 2>&1
  local BACK; BACK=$($ADB -s $S shell cat "$PCS" 2>/dev/null \
    | grep -aoE '^(crisp-title-logo\?|render-scale|dynamic-render-scale\?|recharged-master\?) = [^ ]+' | tr '\n' ' ')
  say "  seeded: $BACK"
  case "$BACK" in *"crisp-title-logo? = #${CRISP}"*) : ;; *) say "  SEED READBACK FAIL (crisp)"; return 1 ;; esac
  case "$BACK" in *"render-scale = ${SCALE}."*)      : ;; *) say "  SEED READBACK FAIL (scale)"; return 1 ;; esac
  return 0; }

leg(){ local TAG="$1" CRISP="$2" SCALE="$3" SECS="${4:-95}"
  say ""; say "######## LEG $TAG — crisp-title-logo? = #$CRISP, RENDER SCALE $SCALE ########"
  seed "$CRISP" "$SCALE" || return 1
  $ADB -s $S shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
  $ADB -s $S logcat -c >/dev/null 2>&1 || true
  local LOG="$OUT/logcat-$TAG.log"; : > "$LOG"
  ( $ADB -s $S logcat -v threadtime GK_STDOUT:I GK_STDERR:I opengoal-gk:I '*:S' \
      | grep --line-buffered -aE 'crisp-logo|CRISPLOGO-MENU|A35-RENDER FBO setup|A35-RENDER frame=|link finish|Fatal signal|signal [0-9]+ \(SIG|GK-DIAG sig=' >> "$LOG" ) 2>/dev/null &
  local LCP=$!
  $ADB -s $S shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
  sleep "$SECS"
  if fg_ok; then say "  foreground: OK ($PKG)"; else say "  foreground: NOT jak1 — $($ADB -s $S shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r')"; fi
  $ADB -s $S shell screencap -p /sdcard/crisp.png >/dev/null 2>&1
  $ADB -s $S pull /sdcard/crisp.png "$OUT/device-$TAG.png" >/dev/null 2>&1
  $ADB -s $S shell rm -f /sdcard/crisp.png >/dev/null 2>&1
  sleep 6   # let a second replay-throttle window and more FBO lines land
  kill $LCP >/dev/null 2>&1 || true; sleep 1
  say "  capture: $OUT/device-$TAG.png ($(stat -c%s "$OUT/device-$TAG.png" 2>/dev/null || echo 0) bytes)"
  say "  toggle line   : $(grep -a 'crisp-logo\] toggle' "$LOG" | tail -1 | sed 's/.*GK[_A-Z]*: *//' | tr -d '\r')"
  say "  menu wiring   : $(grep -a 'CRISPLOGO-MENU' "$LOG" | tail -1 | sed 's/.*GK[_A-Z]*: *//' | tr -d '\r')"
  say "  world FBO     : $(grep -a 'A35-RENDER FBO setup' "$LOG" | tail -1 | sed 's/.*A35-RENDER/A35-RENDER/' | tr -d '\r')"
  say "  logo replay   : $(grep -ac 'crisp-logo\] native replay' "$LOG") line(s); last: $(grep -a 'crisp-logo\] native replay' "$LOG" | tail -1 | sed 's/.*\[crisp-logo\]/[crisp-logo]/' | tr -d '\r')"
  say "  crash markers : $(grep -acE 'Fatal signal|signal [0-9]+ \(SIG|GK-DIAG sig=' "$LOG")"
  $ADB -s $S shell am force-stop $PKG >/dev/null 2>&1 || true
  return 0; }

leg OFF-rs40  f 40
leg ON-rs40   t 40
leg ON-rs100  t 100

say ""; say "######## SUMMARY ########"
for T in OFF-rs40 ON-rs40 ON-rs100; do
  L="$OUT/logcat-$T.log"
  say "$T: replay_lines=$(grep -ac 'crisp-logo\] native replay' "$L" 2>/dev/null) world_fbo=$(grep -a 'A35-RENDER FBO setup' "$L" 2>/dev/null | tail -1 | grep -oE '[0-9]+x[0-9]+' | head -1) logo_fb=$(grep -a 'crisp-logo\] native replay' "$L" 2>/dev/null | tail -1 | grep -oE 'fb=[0-9]+x[0-9]+') crashes=$(grep -acE 'Fatal signal|signal [0-9]+ \(SIG' "$L" 2>/dev/null)"
done
