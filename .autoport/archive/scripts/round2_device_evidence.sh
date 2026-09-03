#!/usr/bin/env bash
# round2_device_evidence.sh — Grecharged-hud-jak1 ROUND 2 device evidence (eae4df44).
# Freshly deployed HEAD build (deploy_verify PASS, fingerprint commit=9961dcb3d).
# Modeled on rhud2_ingame_capture.sh / _capture3.sh (inject/settings-push/fg/shot/boot
# idioms + event-driven F1-WARP wait via logcat poll, 180s timeout).
# Beats (in order, each shot bracketed with an fg check; focus must be jak1):
#   1 OFF round      — settings #f, warp, hold l2, off-l2 shots
#   2 ON-BOOT round  — settings #t (flag ON from BOOT = the zombie-fix case), warp,
#                      onboot-l2 shots + cellanim shots
#   3 gauge beats    — blue/red/yellow eco spawn ON Jak, gauge shots
#   4 green orb      — green eco pill spawn, greenorb shots
#   5 heart states   — drown-death die burst (66/33-blink/0), respawn shot
#   6 menu+circleback— nav to Recharged submenu, circle-back whitelist proof, unpause
#   7 cleanup        — clear all props, keep recharged-hud? #t, force-stop
#   8 logcat         — save per-round segments + crash scan + recharged-hud loaded count
# Manager reviews pixels; this script only harvests evidence + reports reach honestly.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
INJECT="/data/data/$PKG/files/cpad_inject"
SETF="/storage/emulated/0/OpenGOAL/jak1/settings.ini"
OUT=.autoport/reports/Grecharged-hud-jak1; SHOTS="$OUT/shots"; R2="$OUT/round2"
mkdir -p "$SHOTS" "$R2"
adb(){ "$ADB" -s "$S" "$@"; }
inject(){ printf '%s' "$1" | adb shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; }
clr(){ inject ""; }
tapb(){ inject "$1"; sleep 0.5; clr; sleep "${2:-1.2}"; }
fg(){ adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r'; }
shot(){ adb exec-out screencap -p > "$SHOTS/device-$1.png" 2>/dev/null
        local sz; sz=$(stat -c%s "$SHOTS/device-$1.png" 2>/dev/null || echo 0)
        local f; f=$(fg)
        case "$f" in *org.opengoal.gk.jak1*) local ok=OK ;; *) local ok=BAD-FOCUS ;; esac
        echo "    SHOT device-$1.png  size=${sz}B  focus=$ok  [$f]"
        printf '%s\t%s\t%s\t%s\n' "device-$1.png" "$sz" "$ok" "$f" >> "$R2/shot-table.tsv"; }

# push local settings (sha-verified) to device app-home relative path
push_appfile(){ local bn want got; bn=$(basename "$1"); want=$(sha256sum "$1" | awk '{print $1}')
  adb push "$1" "/data/local/tmp/$bn" >/dev/null 2>&1 || { echo "  PUSH-FAIL $bn"; return 1; }
  adb shell run-as $PKG cp "/data/local/tmp/$bn" "$2" || { echo "  CP-FAIL $bn"; return 1; }
  adb shell rm -f "/data/local/tmp/$bn" >/dev/null 2>&1 || true
  got=$(adb shell run-as $PKG sha256sum "$2" 2>/dev/null | awk '{print $1}' | tr -d '\r')
  [ "$got" = "$want" ] || { echo "  SHA-MISMATCH $bn (want=$want got=$got)"; return 1; }
  echo "  pushed+sha-verified $bn"; }

set_flag(){ # $1 = #t or #f  -> rewrite the recharged-hud? line, push sha-verified
  adb shell run-as $PKG cat "$SETF" 2>/dev/null | tr -d '\r' > /tmp/r2-set.gc
  if grep -qa 'recharged-hud?' /tmp/r2-set.gc; then
    sed -i "s/^recharged-hud? = #[tf]/recharged-hud? = $1/" /tmp/r2-set.gc
  else
    echo "  WARN: recharged-hud? line not present in settings; appending"
    printf '\n^recharged-hud? = %s\n' "$1" >> /tmp/r2-set.gc
  fi
  push_appfile /tmp/r2-set.gc "$SETF" || return 1
  echo "  device flag: $(adb shell run-as $PKG cat "$SETF" 2>/dev/null | grep -a recharged | tr -d '\r')"; }

# event-driven warp launch; returns 0 + prints timing, or 1 on timeout
warp_launch(){ # $1 = label for logging
  adb shell am force-stop $PKG >/dev/null 2>&1 || true
  sleep 2
  adb logcat -c >/dev/null 2>&1 || true
  adb shell setprop debug.opengoal.f1.warp 1 || true
  adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
  local t0 warped; t0=$(date +%s); warped=0
  echo "  [$1] launched $(date +%H:%M:%S); waiting for F1-WARP (max 180s)..."
  while [ $(( $(date +%s) - t0 )) -lt 180 ]; do
    if adb logcat -d -v brief 2>/dev/null | grep -aq "F1-WARP\] (start 'play game-start)"; then warped=1; break; fi
    sleep 1
  done
  local dt=$(( $(date +%s) - t0 ))
  if [ "$warped" = 1 ]; then echo "  [$1] F1-WARP fired at +${dt}s"; echo "$1 F1-WARP +${dt}s" >> "$R2/warp-timings.txt"; return 0
  else echo "  [$1] WARP LINE NEVER APPEARED (+${dt}s)"; echo "$1 WARP-TIMEOUT +${dt}s" >> "$R2/warp-timings.txt"; return 1; fi; }

hold_l2(){ inject "l2"; }   # l2 HELD to reveal the HUD; clear with clr

# ---- preflight ----
: > "$R2/shot-table.tsv"; : > "$R2/warp-timings.txt"
adb get-state >/dev/null 2>&1 || { echo "device not attached"; exit 1; }
adb shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
if adb shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1'; then echo "DEVICE_LOCKED"; exit 1; fi
echo "== preflight: no stale run scripts =="
pgrep -af 'round2_device_evidence' | grep -v $$ || true
adb logcat -c >/dev/null 2>&1 || true

########################################################################
echo "==================== BEAT 1: OFF round ===================="
set_flag '#f' || { echo "flag set #f failed"; exit 1; }
warp_launch OFF || echo "  WARN: OFF warp timeout — continuing to shoot anyway"
sleep 10
echo "  hold L2, 2s settle, 3 shots @1.2s"
hold_l2; sleep 2
shot R2-off-l2-1; sleep 1.2
shot R2-off-l2-2; sleep 1.2
shot R2-off-l2-3
clr
# capture OFF-round logcat before we force-stop for the ON round
adb logcat -d -v time 2>/dev/null > "$R2/device-R2-logcat-off.txt" || true

########################################################################
echo "==================== BEAT 2: ON-BOOT round (zombie-fix) ===================="
set_flag '#t' || { echo "flag set #t failed"; exit 1; }
warp_launch ONBOOT || echo "  WARN: ONBOOT warp timeout — continuing to shoot anyway"
sleep 10
echo "  hold L2, 2s settle, 4 onboot-l2 shots @1.2s (cell icon+glow must appear)"
hold_l2; sleep 2
shot R2-onboot-l2-1; sleep 1.2
shot R2-onboot-l2-2; sleep 1.2
shot R2-onboot-l2-3; sleep 1.2
shot R2-onboot-l2-4
echo "  3 cellanim shots @1.0s (anim-rate evidence)"
shot R2-cellanim-1; sleep 1.0
shot R2-cellanim-2; sleep 1.0
shot R2-cellanim-3
clr

########################################################################
echo "==================== BEAT 3: gauge beats (blue/red/yellow) ===================="
gauge_beat(){ # $1=eco-type-int  $2=color-name
  echo "  eco.spawn $1 ($2)"
  adb shell setprop debug.opengoal.eco.spawn "$1 300 0.5 0.5 0.5" || true
  sleep 8
  hold_l2; sleep 1
  shot "R2-gauge-$2-1"; sleep 1
  shot "R2-gauge-$2-2"
  clr
  adb shell setprop debug.opengoal.eco.spawn '""' || true
  sleep 2; }
gauge_beat 3 blue
gauge_beat 2 red
gauge_beat 1 yellow

########################################################################
echo "==================== BEAT 4: green orb ===================="
adb shell setprop debug.opengoal.eco.spawn "7 300 0.5 0.5 0.5" || true
sleep 8
hold_l2; sleep 1
shot R2-greenorb-1; sleep 1
shot R2-greenorb-2
clr
adb shell setprop debug.opengoal.eco.spawn '""' || true
sleep 2

########################################################################
echo "==================== BEAT 5: heart states (drown burst) ===================="
adb shell setprop debug.opengoal.die.mode drown-death || true
adb shell setprop debug.opengoal.die 1 || true
echo "  20-shot burst @0.6s (heart 66/33-blink/0 among them)"
hold_l2
for i in $(seq -w 1 20); do shot "R2-heart-burst-$i"; sleep 0.6; done
clr
adb shell setprop debug.opengoal.die '""' || true
adb shell setprop debug.opengoal.die.mode '""' || true
echo "  wait 15s for respawn"
sleep 15
hold_l2; sleep 1
shot R2-heart-respawn
clr

########################################################################
echo "==================== BEAT 6: menu + circle-back ===================="
# ensure not still holding a pad state
clr; sleep 0.8
echo "  pause -> OPTIONS -> down -> OPTIONS GRAPHIQUES"
tapb start 2.2
tapb circle 1.5
tapb down 0.8
tapb x 2.0
echo "  8x down to Recharged/Reglages row"
for i in 1 2 3 4 5 6 7 8; do tapb down 0.6; done
shot R2-menu-row
echo "  enter submenu"
tapb x 1.8
shot R2-menu-submenu
echo "  circle ONCE on the toggle row (NEW whitelist -> should return to Graphics Options)"
tapb circle 1.8
shot R2-menu-circleback
echo "  unpause (start x2)"
tapb start 1.5
tapb start 1.5
sleep 1
shot R2-unpaused

########################################################################
echo "==================== BEAT 7: cleanup ===================="
clr
adb shell setprop debug.opengoal.f1.warp 0 || true
adb shell setprop debug.opengoal.eco.spawn '""' || true
adb shell setprop debug.opengoal.die '""' || true
adb shell setprop debug.opengoal.die.mode '""' || true
echo "  props now:"
for p in f1.warp eco.spawn die die.mode; do
  echo "    debug.opengoal.$p = [$(adb shell getprop debug.opengoal.$p | tr -d '\r')]"; done
echo "  settings flag (must stay #t):"
adb shell run-as $PKG cat "$SETF" 2>/dev/null | grep -a recharged | tr -d '\r'
# capture ON-round logcat (covers beats 2-6) before force-stop
adb logcat -d -v time 2>/dev/null > "$R2/device-R2-logcat-on.txt" || true
adb shell am force-stop $PKG >/dev/null 2>&1 || true

########################################################################
echo "==================== BEAT 8: logcat scan ===================="
for tag in off on; do
  f="$R2/device-R2-logcat-$tag.txt"
  [ -f "$f" ] || { echo "  MISSING $f"; continue; }
  echo "  --- $tag ($(wc -l < "$f") lines) ---"
  crash=$(grep -acE 'Fatal signal|signal (11|6|4) \(SIG' "$f" || true)
  echo "    crash-signature lines (Fatal signal / signal 11|6|4): $crash"
  [ "$crash" -gt 0 ] && grep -aE 'Fatal signal|signal (11|6|4) \(SIG' "$f" | head -5 | sed 's/^/      /'
  rh=$(grep -acE 'recharged-hud: loaded' "$f" || true)
  echo "    'recharged-hud: loaded' count: $rh"
  grep -aE 'recharged-hud' "$f" | head -3 | sed 's/^/      /' || true
done

echo "==================== DONE ===================="
echo "shot table: $R2/shot-table.tsv"
echo "warp timings: $R2/warp-timings.txt"
column -t -s $'\t' "$R2/shot-table.tsv" 2>/dev/null || cat "$R2/shot-table.tsv"
