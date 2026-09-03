#!/usr/bin/env bash
# Phase Gcine-pose device run: arm the GPOSE joint-sanity tripwire, drive
# NEW GAME -> intro cinematic via cpad_inject, and let the cinematic PLAY
# THROUGH to gameplay while the tripwire buckets per-frame cspace joint
# skips / bad bone matrices into "GPOSE-GLITCH frame=..." log lines.
#
# Output:
#   .autoport/reports/Gpose-routed-logcat-run<N>.log   (validator AFTER-run path)
#
# Usage: bash .autoport/Gpose_run.sh <run-number> [skip-install]
# Env:   WATCH_MIN=<minutes>  cinematic watch window (default 14)
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh
. .autoport/lib/device-validate.sh

export ANDROID_SERIAL=eae4df44
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
RUN="${1:-1}"
SKIP_INSTALL="${2:-}"
WATCH_MIN="${WATCH_MIN:-14}"

PKG="org.opengoal.gk.jak1"
ACT=".LoaderActivity"
APK="android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk"
INJECT="/data/data/$PKG/files/cpad_inject"
RDIR=".autoport/reports"
LOG="$RDIR/Gpose-routed-logcat-run${RUN}.log"
mkdir -p "$RDIR/Gpose"

INTERLOPERS=(com.xiaoji.egggameplus com.ghplus.patcher dev.moukrea.sshxmobile dev.moukrea.sshxmobile.debug)
reenable_interlopers() { for p in "${INTERLOPERS[@]}"; do adb shell pm enable "$p" >/dev/null 2>&1 || true; done; }
disable_interlopers() {
  for p in "${INTERLOPERS[@]}"; do
    adb shell am force-stop "$p" >/dev/null 2>&1 || true
    adb shell pm disable-user --user 0 "$p" >/dev/null 2>&1 || true
  done
}
inject() { printf '%s' "$1" | adb shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; echo "    inject: '$1'"; }
clear_inject() { inject ""; }

echo "== Gpose run $RUN (watch ${WATCH_MIN} min) =="
device_require_attached
disable_interlopers
trap 'reenable_interlopers; kill ${LOGCAT_PID:-0} 2>/dev/null; adb shell am force-stop $PKG 2>/dev/null; device_stayon_restore 2>/dev/null' EXIT
device_stayon_on
device_require_free_space

if [ "$SKIP_INSTALL" != "skip" ]; then
  device_install_and_launch "$PKG" "$ACT" "$APK"
else
  device_require_unlocked
fi

adb shell am force-stop "$PKG" 2>/dev/null || true
# ARM the joint-sanity tripwire BEFORE launch so the first cspace call (early
# in boot) latches it on. debug.* props are settable from adb shell.
adb shell setprop debug.opengoal.gpose.tripwire 1 2>/dev/null || true
echo "  armed debug.opengoal.gpose.tripwire=$(adb shell getprop debug.opengoal.gpose.tripwire | tr -d '\r')"
clear_inject
adb logcat -G 16M 2>/dev/null || true
adb logcat -c 2>/dev/null || true
adb logcat -v threadtime > "$LOG" 2>&1 &
LOGCAT_PID=$!

echo "  launch $PKG/$ACT"
adb shell am start -W -n "$PKG/$ACT" >/tmp/gpose-amstart.out 2>&1 || true

echo "== stage 1: warmup (title + flythrough settle) =="
sleep 40

echo "== stage 2: START (open progress menu) =="
inject "start"; sleep 1.2; clear_inject; sleep 4

echo "== stage 3: DOWN x2 then back UP to NEW GAME =="
inject "down"; sleep 0.4; clear_inject; sleep 1.5
inject "down"; sleep 0.4; clear_inject; sleep 1.5
inject "up"; sleep 0.4; clear_inject; sleep 1
inject "up"; sleep 0.4; clear_inject; sleep 1.5

echo "== stage 4: X (select NEW GAME -> save-file screen) =="
inject "x"; sleep 0.6; clear_inject; sleep 3

echo "== stage 5: navigate to CONTINUE WITHOUT SAVING + confirm =="
inject "down"; sleep 0.4; clear_inject; sleep 1
inject "down"; sleep 0.4; clear_inject; sleep 1
inject "down"; sleep 0.4; clear_inject; sleep 1
inject "down"; sleep 0.4; clear_inject; sleep 1
inject "x"; sleep 0.6; clear_inject
sleep 4

CONFIRM_OFS=$(wc -l < "$LOG" 2>/dev/null || echo 0)
echo "   post-confirm log offset: $CONFIRM_OFS"

echo "== stage 6: LONG cinematic play-through watch (${WATCH_MIN} min, poll 15s) =="
CRASH_RE="GK-DIAG sig=|Fatal signal [0-9]|signal 11 \(SIGSEGV\)|signal 4 \(SIGILL\)|signal 6 \(SIGABRT\)|A18-DIAG method-not-implemented"
ITERS=$(( WATCH_MIN * 60 / 15 ))
CRASHED=""
GONE=0
for ((i=1; i<=ITERS; i++)); do
  sleep 15
  FM=$(grep -a 'A35-RENDER frame=' "$LOG" | grep -oE 'frame=[0-9]+' | grep -oE '[0-9]+' | sort -n | tail -1)
  CR=$(grep -acE "$CRASH_RE" "$LOG" 2>/dev/null || true)
  GG=$(grep -ac 'GPOSE-GLITCH' "$LOG" 2>/dev/null || true)
  PID=$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r')
  FOC=$(adb shell dumpsys window 2>/dev/null | grep -iE "mCurrentFocus" | head -1 | tr -d '\r')
  echo "   [${i}/${ITERS}] frame=${FM:-0} glitch_frames=${GG:-0} crash=${CR:-0} pid='${PID:-gone}' focus='${FOC##*mCurrentFocus=}'"
  if [ "${CR:-0}" -ge 1 ]; then echo "   >>> CRASH/TRAP SIGNATURE detected"; CRASHED="trap"; sleep 3; break; fi
  if [ -z "$PID" ]; then GONE=$((GONE+1)); else GONE=0; fi
  if [ "$GONE" -ge 2 ]; then echo "   >>> app PROCESS GONE twice (crash/exit)"; CRASHED="procgone"; sleep 2; break; fi
  # Cinematic has played through well past the prior crash point — enough.
  if [ "${FM:-0}" -ge 9300 ]; then echo "   >>> cinematic played through (frame=$FM >= 9300)"; sleep 2; break; fi
done

echo "== teardown =="
kill ${LOGCAT_PID:-0} 2>/dev/null || true
trap - EXIT
reenable_interlopers
adb shell am force-stop "$PKG" 2>/dev/null || true
device_stayon_restore 2>/dev/null || true

echo "== scoreboard (run $RUN) =="
FM=$(grep -a 'A35-RENDER frame=' "$LOG" | grep -oE 'frame=[0-9]+' | grep -oE '[0-9]+' | sort -n | tail -1)
CR=$(grep -acE "$CRASH_RE" "$LOG" 2>/dev/null || true)
GG=$(grep -ac 'GPOSE-GLITCH' "$LOG" 2>/dev/null || true)
SKIPS=$(grep -ac 'GPOSE-SKIP' "$LOG" 2>/dev/null || true)
BADMAT=$(grep -ac 'GPOSE-BADMAT' "$LOG" 2>/dev/null || true)
ARMED=$(grep -ac 'GPOSE tripwire armed' "$LOG" 2>/dev/null || true)
echo "  GPOSE tripwire armed lines : $ARMED"
echo "  GPOSE-GLITCH frames        : $GG"
echo "  GPOSE-SKIP logged (cap 400): $SKIPS"
echo "  GPOSE-BADMAT logged        : $BADMAT"
echo "  highest A35-RENDER frame   : ${FM:-0}"
echo "  crash-signal lines         : ${CR:-0}"
echo "  CRASHED                    : ${CRASHED:-no}"
echo "log: $LOG ($(wc -l < "$LOG" 2>/dev/null || echo 0) lines)"
echo "-- sample GPOSE-GLITCH lines --"; grep -a 'GPOSE-GLITCH' "$LOG" 2>/dev/null | head -6
echo "-- sample GPOSE-SKIP lines --";   grep -a 'GPOSE-SKIP'   "$LOG" 2>/dev/null | head -10
echo "-- sample GPOSE-BADMAT lines --"; grep -a 'GPOSE-BADMAT' "$LOG" 2>/dev/null | head -10
