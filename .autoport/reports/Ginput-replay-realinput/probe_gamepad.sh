#!/usr/bin/env bash
# Probe whether gamepad-flavoured input reaches on_pad_button on Android.
# (1) adb 'input gamepad keyevent' synthetic gamepad KeyEvents.
# (2) connecting a paired Bluetooth controller (does SDL open it? does overlay hide?).
set -uo pipefail
ADB=/home/emeric/Android/platform-tools/adb
S=eae4df44
PKG=org.opengoal.gk.jak1
OUT=/home/emeric/code/jak-project/.autoport/reports/Ginput-replay-realinput
LOG="$OUT/probe_gamepad_logcat.txt"

echo "=== input sources supported ==="
$ADB -s $S shell input 2>&1 | head -20

echo "=== paired BT controllers ==="
$ADB -s $S shell dumpsys bluetooth_manager 2>/dev/null | grep -iE "Controller|\[BR/EDR\]" | head

echo "=== try to CONNECT the Pro Controller (E4:17:D8:1C:1B:05) ==="
$ADB -s $S shell cmd bluetooth_manager connect E4:17:D8:1C:1B:05 2>&1 | head -3 || true
$ADB -s $S shell svc bluetooth enable 2>&1 | head -1 || true

echo "=== current input devices with gamepad/joystick source ==="
$ADB -s $S shell dumpsys input 2>/dev/null | grep -iE "Device [0-9]|Sources:|Name:" | grep -iB1 -A1 "joystick\|gamepad\|Controller" | head -20

# Launch app normally (no warp/record) just to observe input delivery into native.
$ADB -s $S shell am force-stop $PKG
$ADB -s $S shell "setprop debug.opengoal.f1.warp ''"
$ADB -s $S shell "setprop debug.opengoal.pad_replay ''"
$ADB -s $S shell svc power stayon true
$ADB -s $S shell input keyevent KEYCODE_WAKEUP
$ADB -s $S logcat -c
( $ADB -s $S logcat -v time > "$LOG" 2>&1 ) &
LOGPID=$!
$ADB -s $S shell am start -n $PKG/org.opengoal.gk.LoaderActivity >/dev/null
echo "=== wait for boot (overlay-map or A35 renderer) up to 90s ==="
for i in $(seq 1 45); do
  sleep 2
  if grep -qa "overlay-map:\|A35 game-content renderer wired\|SDL_Init: gamepad subsystem OK" "$LOG" 2>/dev/null; then echo "  up at ~$((i*2))s"; break; fi
  if grep -qaE "exited due to signal 4" "$LOG" 2>/dev/null; then echo "  BOOT FLAKE (SIGILL) — note but continue probing"; fi
done
sleep 3

echo "=== gamepad/SDL state in logcat ==="
grep -aE "SDL_GAMEPAD|GAMEPAD_ADDED|gamepad subsystem|open_gamepad|hiding touch overlay|opened '" "$LOG" | head

echo "=== inject synthetic GAMEPAD keyevents (buttons) ==="
for kc in KEYCODE_BUTTON_A KEYCODE_BUTTON_B KEYCODE_BUTTON_X KEYCODE_BUTTON_Y KEYCODE_BUTTON_START KEYCODE_BUTTON_SELECT; do
  $ADB -s $S shell input gamepad keyevent $kc 2>&1 | head -1
  $ADB -s $S shell input keyevent $kc 2>&1 | head -1   # also plain keyevent
done
sleep 2

echo "=== did gamepad events reach native? ==="
echo "  onPadButton(real gamepad) lines: $(grep -ac 'onPadButton: sdl_button=.*real gamepad' "$LOG")"
echo "  onPadButton(any JNI)       lines: $(grep -ac 'onPadButton: sdl_button' "$LOG")"
echo "  kernel: pad:               lines: $(grep -ac 'kernel: pad:' "$LOG")"
echo "  SDL_EVENT_GAMEPAD_BUTTON   evidence:"; grep -aE "GAMEPAD_BUTTON|pad-state poll: SDL event pump" "$LOG" | head
echo "  --- sample kernel: pad: ---"; grep -a 'kernel: pad:' "$LOG" | head

$ADB -s $S shell am force-stop $PKG
kill $LOGPID 2>/dev/null
echo "=== PROBE DONE ==="
