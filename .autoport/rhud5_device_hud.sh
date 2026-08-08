#!/usr/bin/env bash
# rhud5_device_hud.sh — ROUND 5 device leg #2: get the HUD ACTUALLY ON SCREEN on eae4df44.
#
# Why a second script: leg #1 proved freshness/boot/texture-load but every frame showed an
# empty HUD, because its input injection used the app-private FILE channel
# (`run-as <pkg> sh -c 'cat > files/cpad_inject'`) — the redirect is performed by the ADB-side
# shell in ITS working directory, so it lands nowhere (android_input_audio.cpp:677-686 documents
# exactly this failure) — and passed analog values as floats ("ly=0.4") when the parser is
# atoi() over 0..255 with 128 neutral (apply_inject_token, :621-630).
# Correct channel: `setprop debug.opengoal.cpad_inject "<tokens>"`. Holding l2 is what the stock
# tally-value uses to force EVERY hud element on screen (hud.gc:43), which is what makes the
# heart / eco gauge / 3d icons visible without playing the game.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-$HOME/Android/platform-tools/adb}"
S="${S:-eae4df44}"; PKG=org.opengoal.gk.jak1; ACT=org.opengoal.gk.LoaderActivity
OUT=.autoport/reports/Grecharged-hud-jak1/round5/device; mkdir -p "$OUT"
LOG="$OUT/device-hud.log"; : > "$LOG"
SETF=/storage/emulated/0/OpenGOAL/jak1/settings.ini
say(){ echo "$*" | tee -a "$LOG"; }
die(){ say "[rhud5-hud FAIL] $*"; exit 1; }
adbs(){ "$ADB" -s "$S" "$@"; }
fg(){ adbs shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r'; }
shot(){ adbs exec-out screencap -p > "$OUT/device-$1.png" 2>/dev/null
        say "  shot device-$1.png ($(stat -c%s "$OUT/device-$1.png" 2>/dev/null||echo 0) B) fg=$(fg)"; }
pad(){ adbs shell setprop debug.opengoal.cpad_inject "$1" >/dev/null 2>&1 || true; }
set_key(){
  adbs shell cat "$SETF" 2>/dev/null | tr -d '\r' > /tmp/rhud5h.ini || true
  [ -s /tmp/rhud5h.ini ] || die "no settings.ini on device"
  grep -q "^$1 " /tmp/rhud5h.ini && sed -i "s|^$1 .*|$1 = $2|" /tmp/rhud5h.ini \
     || sed -i "0,/^version /s|^\(version .*\)$|\1\n$1 = $2|" /tmp/rhud5h.ini
  adbs push /tmp/rhud5h.ini /sdcard/rhud5h.ini >/dev/null 2>&1
  adbs shell cp /sdcard/rhud5h.ini "$SETF" >/dev/null 2>&1
}
launch_fg(){
  local secs="$1" tries=0
  while [ $tries -lt 3 ]; do
    adbs shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
    local t=0
    while [ $t -lt 45 ]; do
      case "$(fg)" in *org.opengoal.gk.jak1*) sleep "$secs"; return 0;; esac
      sleep 5; t=$((t+5))
    done
    tries=$((tries+1)); say "  (launch attempt $tries missed the foreground, retrying)"
  done
  die "game never reached the foreground"
}

adbs devices | grep -qE "^${S}[[:space:]]+device$" || die "device $S not connected"
adbs shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
adbs shell svc power stayon true >/dev/null 2>&1 || true
if adbs shell dumpsys trust 2>/dev/null | grep -a '(current)' | grep -q 'deviceLocked=1'; then die "device PIN-LOCKED"; fi

leg(){ # leg <tag> <hud-on 0|1> <eco-type>
  local tag="$1" hud="$2" eco="$3"
  adbs shell am force-stop $PKG >/dev/null 2>&1 || true; sleep 2
  pad ""
  set_key "recharged-hud?" "$([ "$hud" = 1 ] && echo '#t' || echo '#f')"
  set_key "dynamic-render-scale?" "#f"; set_key "render-scale" "100.0"
  say "[$tag] settings: $(adbs shell cat "$SETF" 2>/dev/null | tr -d '\r' | grep -aE '^recharged-hud|^render-scale' | tr '\n' ' ')"
  adbs shell setprop debug.opengoal.f1.warp 1 >/dev/null 2>&1 || true
  adbs shell setprop debug.opengoal.eco.spawn "$eco 45 0.5 0.0 0.5" >/dev/null 2>&1 || true
  adbs logcat -c >/dev/null 2>&1 || true
  launch_fg 80
  say "[$tag] in-game, fg=$(fg)"
  # L2 held => every hud element forced on screen (heart, eco gauge, cell/fly icons, counters)
  pad "l2"; sleep 4; shot "$tag-hud"
  sleep 2; shot "$tag-hud2"
  # walk forward through the eco spawn point so an eco is actually COLLECTED (gauge fills,
  # green eco pops the heart). 128 = neutral, 210 = forward.
  pad "l2 ly=210"; sleep 3
  pad "l2 ly=46";  sleep 3
  pad "l2 ly=210"; sleep 3
  shot "$tag-collect"
  pad "l2"; sleep 3; shot "$tag-after"
  pad ""
  adbs logcat -d -v brief 2>/dev/null | grep -aE 'F1D-INJECT applied|ECO-SPAWN|F1-WARP' | tail -6 >> "$LOG" || true
}

say "=== LEG A: recharged HUD ON, GREEN eco (heart pop + green particle + leak check) ==="
leg "R5-ON-green" 1 4
say "=== LEG B: recharged HUD ON, BLUE eco (gauge fill + per-type centre particle) ==="
leg "R5-ON-blue" 1 3
say "=== LEG C: recharged HUD OFF (stock A/B), BLUE eco ==="
leg "R5-OFF-blue" 0 3

adbs shell setprop debug.opengoal.eco.spawn "" >/dev/null 2>&1 || true
adbs shell setprop debug.opengoal.cpad_inject "" >/dev/null 2>&1 || true
set_key "recharged-hud?" "#t"
NCRASH=$(adbs shell logcat -d 2>/dev/null | grep -acE 'Fatal signal|GK-DIAG sig=' || true)
say "crash markers: ${NCRASH:-0}"
adbs shell am force-stop $PKG >/dev/null 2>&1 || true
say "[rhud5-hud DONE]"
ls -la "$OUT"/device-R5-*.png 2>/dev/null
