#!/usr/bin/env bash
# Phase G1 (autoport): device run harness — TITLE-STABILITY verification.
#
# The floor for G1 is a crash-free, sustained, flying title after F1f's
# enter-state pop-RA regressed it (sig=11 at a title attract state transition,
# ~frame 252). This harness boots to the title and WATCHES it fly for ~150s
# (the e1f35 "3x149s clean boot" pattern) WITHOUT injecting any input that
# would drive a state transition into the documented G2 new-game residual.
# It only opens/closes the progress menu once (START) as a light liveness
# probe that exercises an in-place state change without leaving the title.
#
# NOT infra (lives outside .autoport/lib + .autoport/validators so the
# validator's forbidden-edit gate ignores it). Derived from f1f_run.sh.
#
# Usage: bash .autoport/g1_run.sh <run-number> [skip-install]
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
LOG="$RDIR/G1-routed-logcat-run${RUN}.log"
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

inject() {  printf '%s' "$1" | adb shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; echo "    inject: '$1'"; }
clear_inject() { inject ""; }

cap() {  # cap <name>
  local name="$1"
  adb shell am force-stop com.xiaoji.egggameplus >/dev/null 2>&1 || true
  local foc
  foc=$(adb shell dumpsys window 2>/dev/null | grep -iE "mCurrentFocus" | head -1 | tr -d '\r')
  echo "    [$name] focus: $foc"
  echo "$name :: $foc" >> "$RDIR/G1-focus-run${RUN}.txt"
  adb shell screencap -p /sdcard/g1.png >/dev/null 2>&1 || true
  adb pull /sdcard/g1.png "$RDIR/G1-device-run${RUN}-${name}.png" >/dev/null 2>&1 || true
  adb shell rm -f /sdcard/g1.png >/dev/null 2>&1 || true
  echo "    [$name] cap -> G1-device-run${RUN}-${name}.png ($(stat -c %s "$RDIR/G1-device-run${RUN}-${name}.png" 2>/dev/null || echo 0) bytes)"
}

frame_max() { grep -a "A35-RENDER frame=" "$LOG" 2>/dev/null | grep -oE "frame=[0-9]+" | grep -oE "[0-9]+" | sort -n | tail -1; }
sig_count() { grep -acE "GK-DIAG sig=11|exited due to signal 11|Fatal signal 11" "$LOG" 2>/dev/null || true; }

echo "== G1 run $RUN (title-stability, no new-game input) =="
device_require_attached
disable_interlopers
trap 'reenable_interlopers; kill ${LOGCAT_PID:-0} 2>/dev/null; adb shell am force-stop $PKG 2>/dev/null; device_stayon_restore 2>/dev/null' EXIT
device_stayon_on
device_require_free_space

: > "$RDIR/G1-focus-run${RUN}.txt"

if [ "$SKIP_INSTALL" != "skip" ]; then
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
adb shell am start -W -n "$PKG/$ACT" >/tmp/g1-amstart.out 2>&1 || true

echo "== watch the title fly (crash-free) for ~150s =="
CRASHED=""
for t in 15 30 45 60 75 90 105 120 135 150; do
  sleep 15
  cap "wait-t${t}"
  FM=$(frame_max); FM=${FM:-0}
  SC=$(sig_count); SC=${SC:-0}
  MM=$(grep -ac "set-master-mode" "$LOG" 2>/dev/null || true)
  echo "   t=${t}s frame_max=$FM sig11=$SC set-master-mode=$MM"
  if [ "${SC:-0}" -ge 1 ]; then
    echo "   CRASH detected (sig=11) — stopping watch"
    CRASHED=yes
    cap "crash-t${t}"
    break
  fi
done

# Light liveness probe: open + close the progress menu (in-place state change,
# stays on the title — does NOT enter new game / load game).
if [ -z "$CRASHED" ]; then
  echo "== liveness: START (open progress menu) then B (back to title) =="
  inject "start"; sleep 1.0; clear_inject; sleep 3
  cap "menu-open"
  inject "triangle"; sleep 0.6; clear_inject; sleep 2   # B/triangle backs out
  cap "menu-back"
  sleep 10
  cap "title-after"
fi

FM=$(frame_max); FM=${FM:-0}
SC=$(sig_count); SC=${SC:-0}
echo "== final: frame_max=$FM sig11=$SC =="

sleep 2
echo "== teardown =="
kill ${LOGCAT_PID:-0} 2>/dev/null || true
trap - EXIT
reenable_interlopers
adb shell am force-stop "$PKG" 2>/dev/null || true
device_stayon_restore 2>/dev/null || true

echo "== marker scoreboard (run $RUN) =="
for pat in "set-master-mode" "A35-RENDER frame" "GK-DIAG sig=11" "GK-DIAG sig=" \
           "link finish" "Displaying level" "enter-state" ; do
  n=$(grep -ac "$pat" "$LOG" 2>/dev/null || echo 0)
  printf "  %-28s %s\n" "$pat" "$n"
done
echo "log: $LOG ($(wc -l < "$LOG" 2>/dev/null || echo 0) lines), frame_max=$FM, sig11=$SC"
