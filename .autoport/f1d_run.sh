#!/usr/bin/env bash
# Phase F1d (autoport): device run harness — input → cpad → START → play.
#
# NOT infra (lives outside .autoport/lib + .autoport/validators so the
# validator's forbidden-edit gate ignores it). Drives the headless
# cpad-injection control file the F1d native code watches and captures the
# title → (START) → menu → (X) → training/Jak → (stick) → Jak-moved flow.
#
# Usage: bash .autoport/f1d_run.sh <run-number> [skip-install]
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh
. .autoport/lib/device-validate.sh

export ANDROID_SERIAL=eae4df44
RUN="${1:-1}"
SKIP_INSTALL="${2:-}"

PKG="org.opengoal.gk.jak1"
ACT=".LoaderActivity"
APK="android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk"
INJECT="/data/data/$PKG/files/cpad_inject"
RDIR=".autoport/reports"
LOG="$RDIR/F1d-routed-logcat-run${RUN}.log"
mkdir -p "$RDIR"

INTERLOPERS=(com.xiaoji.egggameplus com.ghplus.patcher dev.moukrea.sshxmobile dev.moukrea.sshxmobile.debug)

reenable_interlopers() {
  for p in "${INTERLOPERS[@]}"; do adb shell pm enable "$p" >/dev/null 2>&1 || true; done
}
disable_interlopers() {
  for p in "${INTERLOPERS[@]}"; do
    adb shell am force-stop "$p" >/dev/null 2>&1 || true
    adb shell pm disable-user --user 0 "$p" >/dev/null 2>&1 || true
  done
}

inject() {  # inject "<tokens>"  — held until cleared
  printf '%s' "$1" | adb shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true
  echo "    inject: '$1'"
}
clear_inject() { inject ""; }

cap() {  # cap <name>
  local name="$1"
  adb shell am force-stop com.xiaoji.egggameplus >/dev/null 2>&1 || true
  local foc
  foc=$(adb shell dumpsys window 2>/dev/null | grep -iE "mCurrentFocus" | head -1 | tr -d '\r')
  echo "    [$name] focus: $foc"
  echo "$name :: $foc" >> "$RDIR/F1d-focus-run${RUN}.txt"
  adb shell screencap -p /sdcard/f1d.png >/dev/null 2>&1 || true
  adb pull /sdcard/f1d.png "$RDIR/F1d-device-run${RUN}-${name}.png" >/dev/null 2>&1 || true
  adb shell rm -f /sdcard/f1d.png >/dev/null 2>&1 || true
  echo "    [$name] cap -> F1d-device-run${RUN}-${name}.png ($(stat -c %s "$RDIR/F1d-device-run${RUN}-${name}.png" 2>/dev/null || echo 0) bytes)"
}

echo "== F1d run $RUN =="
device_require_attached
disable_interlopers
trap 'reenable_interlopers; kill ${LOGCAT_PID:-0} 2>/dev/null; adb shell am force-stop $PKG 2>/dev/null; device_stayon_restore 2>/dev/null' EXIT
device_stayon_on
device_require_free_space

: > "$RDIR/F1d-focus-run${RUN}.txt"

if [ "$SKIP_INSTALL" != "skip" ]; then
  # Preserve the seeded iso_data sentinel — our APK doesn't change CGOs.
  device_install_and_launch "$PKG" "$ACT" "$APK"
else
  device_require_unlocked
fi

adb shell am force-stop "$PKG" 2>/dev/null || true
clear_inject
adb logcat -G 16M 2>/dev/null || true
adb logcat -c 2>/dev/null || true
adb logcat -v threadtime > "$LOG" 2>&1 &
LOGCAT_PID=$!

echo "  launch $PKG/$ACT"
adb shell am start -W -n "$PKG/$ACT" >/tmp/f1d-amstart.out 2>&1 || true

echo "== stage 1: warmup (title appears + flies + intro settles) =="
sleep 40
cap "01-title"

echo "== stage 2: inject START (open progress menu) -- proves BUTTON input =="
inject "start"; sleep 1.2; clear_inject
sleep 4
cap "02-menu"

echo "== stage 3: inject DOWN x2 (menu cursor moves) -- proves DIRECTIONAL input =="
inject "down"; sleep 0.4; clear_inject; sleep 1.5
cap "03-menu-down1"
inject "down"; sleep 0.4; clear_inject; sleep 1.5
cap "04-menu-down2"
echo "   back up to NEW GAME"
inject "up"; sleep 0.4; clear_inject; sleep 1
inject "up"; sleep 0.4; clear_inject; sleep 1.5
cap "05-menu-newgame"

echo "== stage 4: inject X (select NEW GAME -> save-file screen) =="
inject "x"; sleep 0.6; clear_inject; sleep 3
cap "06-savefile"

echo "== stage 5: navigate to CONTINUE WITHOUT SAVING + start game =="
inject "down"; sleep 0.4; clear_inject; sleep 1
inject "down"; sleep 0.4; clear_inject; sleep 1
inject "down"; sleep 0.4; clear_inject; sleep 1
inject "down"; sleep 0.4; clear_inject; sleep 1
cap "07-continue-sel"
inject "x"; sleep 0.6; clear_inject
sleep 6
cap "08-newgame-start"

echo "== stage 6: wait for level load attempt + Jak spawn =="
sleep 12
cap "09-load"

echo "== stage 7: inject left-stick forward (attempt Jak movement) =="
inject "ly=15"; sleep 3
cap "10-move-a"
sleep 3
cap "11-move-b"
clear_inject
sleep 2
cap "12-after"

sleep 2
echo "== teardown =="
kill ${LOGCAT_PID:-0} 2>/dev/null || true
trap - EXIT
reenable_interlopers
adb shell am force-stop "$PKG" 2>/dev/null || true
device_stayon_restore 2>/dev/null || true

echo "== marker scoreboard (run $RUN) =="
for pat in "F1D-INJECT armed" "F1D-INJECT applied" "F1D-CPAD-START" "kernel: pad: start" \
           "activate-progress" "progress-screen" "set-master-mode" "F1D target-spawn" \
           "F1D target-pos" "A35-RENDER frame" ; do
  n=$(grep -ac "$pat" "$LOG" 2>/dev/null || echo 0)
  printf "  %-28s %s\n" "$pat" "$n"
done
echo "log: $LOG ($(wc -l < "$LOG" 2>/dev/null || echo 0) lines)"
